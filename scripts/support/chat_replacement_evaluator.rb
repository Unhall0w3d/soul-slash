# frozen_string_literal: true

require "json"
require_relative "../../lib/soul_core/chat_store"
require_relative "../../lib/soul_core/conversation_context_builder"
require_relative "../../lib/soul_core/conversation_provider_contract"
require_relative "chat_replacement_cases"

module SoulCore
  class ChatReplacementEvaluator
    Contract = ConversationProviderContract
    SAMPLE_COUNT = 2
    MAX_REQUESTS = 42
    MAX_OUTPUT_TOKENS = 768

    attr_reader :request_count

    def initialize(root:, client:, provider:, temperature:, reasoning_mode:)
      @root = validate_isolated_root!(root)
      @client = client
      @provider = provider
      @temperature = temperature
      @reasoning_mode = reasoning_mode.to_s
      raise ArgumentError, "client must respond to chat" unless @client.respond_to?(:chat)
      raise ArgumentError, "provider must supply actual model and privacy class" unless @provider.respond_to?(:model) && @provider.respond_to?(:privacy_class)
      raise ArgumentError, "unsupported reasoning mode" unless Contract::REASONING_MODES.include?(@reasoning_mode)
      raise ArgumentError, "temperature must be between 0.0 and 2.0" unless @temperature.is_a?(Numeric) && @temperature.between?(0.0, 2.0)

      @store = ChatStore.new(root: @root)
      @identity_profile = TrialIdentityProfile.new(ConversationIdentityProfile.new)
      @context_builder = ConversationContextBuilder.new(store: @store, identity_profile: @identity_profile)
      @request_count = 0
      @ran = false
    end

    def run
      raise RuntimeError, "evaluator may only run once" if @ran

      @ran = true
      records = []
      ChatReplacementCases.cases.each do |item|
        SAMPLE_COUNT.times do |sample_index|
          record = run_case_sample(item, sample_index + 1)
          records << record
          yield record if block_given?
        end
      end
      ChatReplacementCases.strength_cases.each do |item|
        record = run_case_sample(item, 1)
        records << record
        yield record if block_given?
      end
      run_continuity(records) { |record| yield record if block_given? }
      records
    end

    private

    # Keep the shared identity unchanged while removing guidance tuned to a
    # different model family from this comparison's context projection.
    class TrialIdentityProfile
      def initialize(profile)
        @profile = profile
      end

      def context_for(**arguments)
        @profile.context_for(**arguments)
      end

      def render_system_guidance(**arguments)
        @profile.render_system_guidance(**arguments).lines.reject do |line|
          line.match?(/Gemma calibration:/)
        end.join
      end
    end

    def run_case_sample(item, sample_number)
      chat_id = @store.create_chat(initial_title: "Synthetic replacement #{item.fetch('id')} sample #{sample_number}").fetch("id")
      item.fetch("messages").each do |message|
        @store.add_message(chat_id, role: message.fetch("role"), content: message.fetch("content"),
          metadata: { "synthetic_evaluation" => true })
      end

      request = request_for(chat_id, item, tools: item["tools"], tool_choice: item["tool_choice"], response_format: item["response_format"])
      response = perform(request)
      envelopes = [response.to_h]
      failure = protocol_failure(response, allow_tool_call: item.fetch("kind") == "tool_round_trip")
      score = nil
      if failure
        score = { "pass" => false, "details" => "protocol failure: #{failure}" }
      elsif item.fetch("kind") == "tool_round_trip"
        normalized = normalize_tool_calls(response.tool_calls)
        score = ChatReplacementCases.score(item, content: response.content, tool_calls: normalized)
        call_exact = score.fetch("details").fetch("tool_call_exact")
        call_id = response.tool_calls.first.is_a?(Hash) ? response.tool_calls.first["id"].to_s : ""
        @store.add_message(chat_id, role: "assistant", content: response.content,
          metadata: { "synthetic_evaluation" => true, "response_envelope" => response.to_h, "tool_calls" => response.tool_calls })
        if call_exact && call_id.empty?
          failure = "missing_tool_call_id"
          score = { "pass" => false, "details" => "protocol failure: #{failure}" }
        end
        if call_exact && !call_id.empty?
          tool_id = call_id
          tool_name = item.fetch("expected").fetch("tool_name")
          tool_message = { "role" => "tool", "tool_call_id" => tool_id, "name" => tool_name,
            "content" => JSON.generate(item.fetch("tool_result")) }
          @store.add_message(chat_id, role: "tool", content: tool_message.fetch("content"),
            metadata: { "synthetic_evaluation" => true, "tool_call_id" => tool_id, "name" => tool_name })
          followup = request_for(chat_id, item, tools: item.fetch("tools"), tool_choice: "auto",
            base_messages: request.messages,
            extra_messages: [assistant_tool_message(response), tool_message])
          final_response = perform(followup)
          envelopes << final_response.to_h
          failure = protocol_failure(final_response, allow_tool_call: false)
          score = if failure
                    { "pass" => false, "details" => "protocol failure: #{failure}" }
                  else
                    { "pass" => nil, "details" => { "tool_call_exact" => true,
                      "final_response_rubric" => item.fetch("expected").fetch("rubric"), "parent_inspection_required" => true } }
                  end
          @store.add_message(chat_id, role: "assistant", content: final_response.content,
            metadata: { "synthetic_evaluation" => true, "response_envelope" => final_response.to_h })
        end
      else
        score = ChatReplacementCases.score(item, content: response.content)
        @store.add_message(chat_id, role: "assistant", content: response.content,
          metadata: { "synthetic_evaluation" => true, "response_envelope" => response.to_h })
      end

      {
        "kind" => "case", "case_id" => item.fetch("id"), "sample" => sample_number,
        "chat_id" => chat_id, "response_envelopes" => envelopes, "score" => score,
        "protocol_failure" => failure, "needs_review" => failure.nil? && score.fetch("pass").nil?
      }.compact
    end

    def run_continuity(records)
      turns = ChatReplacementCases.continuity_turns
      chat_id = @store.create_chat(initial_title: "Synthetic replacement continuity").fetch("id")
      turns.each_with_index do |turn, index|
        @store.add_message(chat_id, role: "user", content: turn.fetch("user"),
          metadata: { "synthetic_evaluation" => true, "turn" => index + 1 })
        request = request_for(chat_id, { "id" => "continuity-#{index + 1}" })
        response = perform(request)
        failure = protocol_failure(response, allow_tool_call: false)
        @store.add_message(chat_id, role: "assistant", content: response.content,
          metadata: { "synthetic_evaluation" => true, "response_envelope" => response.to_h, "turn" => index + 1 })
        record = {
          "kind" => "continuity", "turn" => index + 1, "chat_id" => chat_id,
          "user" => turn.fetch("user"), "answer" => response.content,
          "expected_facts" => turn.fetch("expected"), "response_envelopes" => [response.to_h],
          "needs_review" => true, "protocol_failure" => failure
        }.compact
        records << record
        yield record
      end
    end

    def request_for(chat_id, item, tools: nil, tool_choice: nil, response_format: nil, base_messages: nil, extra_messages: [])
      messages = if base_messages
                   base_messages
                 else
                   @context_builder.build(chat_id: chat_id, provider_privacy_class: @provider.privacy_class,
                     provider_model: @provider.model).fetch("messages")
                 end
      messages = messages + extra_messages
      Contract::RequestEnvelope.new(
        conversation_id: chat_id,
        messages: messages,
        model: @provider.model,
        temperature: @temperature,
        max_output_tokens: MAX_OUTPUT_TOKENS,
        tools: tools || [],
        tool_choice: tool_choice,
        response_format: response_format,
        reasoning_mode: @reasoning_mode,
        privacy_requirement: @provider.privacy_class,
        metadata: { "synthetic_evaluation" => true, "case_id" => item.fetch("id") }
      )
    end

    def perform(request)
      raise RuntimeError, "maximum evaluator request count exceeded" if @request_count >= MAX_REQUESTS

      @request_count += 1
      @client.chat(provider: @provider, request: request)
    end

    def protocol_failure(response, allow_tool_call:)
      return "response_error" unless response.error.nil?
      return "finish_length" if response.finish_reason.to_s == "length"
      return allow_tool_call ? nil : "unexpected_tool_call" unless response.tool_calls.empty?
      return "empty_reply" if response.content.to_s.strip.empty?

      nil
    end

    def normalize_tool_calls(calls)
      Array(calls).map do |call|
        function = call.fetch("function")
        arguments = function.fetch("arguments")
        arguments = JSON.parse(arguments) if arguments.is_a?(String)
        { "name" => function.fetch("name"), "arguments" => arguments }
      rescue JSON::ParserError, KeyError, TypeError
        { "invalid" => true }
      end
    end

    def assistant_tool_message(response)
      {
        "role" => "assistant",
        "content" => response.content,
        "tool_calls" => response.tool_calls
      }
    end

    def validate_isolated_root!(root)
      path = File.expand_path(root.to_s)
      stat = File.lstat(path)
      realpath = File.realpath(path)
      raise ArgumentError, "evaluation root must be a real directory" unless stat.directory? && !stat.symlink? && realpath == path
      raise ArgumentError, "evaluation root must be owned by the calling user" unless stat.uid == Process.uid
      raise ArgumentError, "evaluation root must be private to the calling user" unless (stat.mode & 0o077).zero?
      raise ArgumentError, "evaluation root must be empty" unless Dir.empty?(path)

      path
    rescue Errno::ENOENT
      raise ArgumentError, "evaluation root must exist as a new isolated directory"
    end
  end
end
