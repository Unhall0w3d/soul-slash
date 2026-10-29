# frozen_string_literal: true

require "digest"
require "json"
require_relative "chat_replacement_evaluator"
require_relative "chat_replacement_calibration_cases"

module SoulCore
  class ChatReplacementCalibrationEvaluator < ChatReplacementEvaluator
    MINISTRAL_MODEL = "ministral3-8b-instruct".freeze
    GEMMA_MODEL = "gemma4-e4b-it".freeze
    SUPPORTED_MODELS = [MINISTRAL_MODEL, GEMMA_MODEL].freeze
    MAX_OUTPUT_TOKENS = 1536
    MINISTRAL_MAX_REQUESTS = 32
    GEMMA_MAX_REQUESTS = 48
    AVAILABILITY_NOTICE = "Evaluation environment: only the fictional dialogue supplied here is available. No search, filesystem, external tools, or durable-memory writes are available in this call.".freeze
    FOCUSED_SYSTEM_PROMPT = "You are Soul, a local-first assistant being developed with the user. Be an attentive technical and creative counterpart: composed, perceptive, quietly warm, inventive, and concise. Respond to the actual request naturally; personality belongs in judgment and phrasing, not a performance. Use supplied conversation and evidence. Do not invent missing facts, observations, sources, access, or completed actions. A user correction supersedes the earlier mistaken interpretation. Ask a focused question only when missing information blocks a useful answer. End when the answer is complete. Explicit deterministic skills, approvals, and reviewed durable memory are managed outside this model call; this conversation cannot bypass their boundaries. Give conclusions and useful explanations, not private reasoning.".freeze

    attr_reader :request_count

    def initialize(root:, client:, provider:, temperature:, reasoning_mode:)
      super
      raise ArgumentError, "unsupported calibration model: #{@provider.model}" unless SUPPORTED_MODELS.include?(@provider.model)
      expected_temperature = @provider.model == GEMMA_MODEL ? 1.0 : 0.05
      raise ArgumentError, "calibration temperature must match the model asset" unless @temperature == expected_temperature

      @request_count = 0
      @ran = false
    end

    def run
      raise RuntimeError, "evaluator may only run once" if @ran

      @ran = true
      cases = ChatReplacementCalibrationCases.cases
      raise RuntimeError, "calibration catalog must contain exactly eight cases" unless cases.length == 8
      raise RuntimeError, "calibration catalog must contain exactly four reasoning probes" unless cases.count { |item| item.fetch("reasoning_probe") } == 4

      records = []
      maximum = @provider.model == GEMMA_MODEL ? GEMMA_MAX_REQUESTS : MINISTRAL_MAX_REQUESTS

      cases.each_with_index do |item, case_index|
        (1..SAMPLE_COUNT).each do |sample_number|
          conditions_for(item).rotate((case_index + sample_number) % conditions_for(item).length).each do |context_mode, thinking|
            record = run_condition(item, case_index, sample_number, context_mode, thinking)
            records << record
            yield record if block_given?
          end
        end
      end
      raise RuntimeError, "calibration request schedule mismatch" unless @request_count == maximum && records.length == maximum

      records
    end

    private

    def conditions_for(item)
      direct = [["full", false], ["focused", false]]
      return direct unless @provider.model == GEMMA_MODEL && item.fetch("reasoning_probe")

      direct + [["full", true], ["focused", true]]
    end

    def run_condition(item, case_index, sample_number, context_mode, thinking)
      sample_seed = 841_000 + case_index * 10 + sample_number
      chat_id = @store.create_chat(initial_title: "Calibration #{item.fetch('id')} sample #{sample_number}").fetch("id")
      item.fetch("messages").each do |message|
        @store.add_message(chat_id, role: message.fetch("role"), content: message.fetch("content"),
          metadata: { "synthetic_calibration" => true })
      end

      messages = @context_builder.build(chat_id: chat_id, provider_privacy_class: @provider.privacy_class,
        provider_model: @provider.model).fetch("messages")
      messages = project_context(messages, item, context_mode)
      calibration = {
        "seed" => sample_seed,
        "condition" => "#{context_mode}/#{thinking ? 'thinking' : 'direct'}",
        "context_mode" => context_mode,
        "thinking" => thinking
      }
      request = Contract::RequestEnvelope.new(
        conversation_id: chat_id,
        messages: messages,
        model: @provider.model,
        temperature: @temperature,
        max_output_tokens: MAX_OUTPUT_TOKENS,
        tools: [],
        reasoning_mode: thinking ? "default" : @reasoning_mode,
        privacy_requirement: @provider.privacy_class,
        metadata: { "synthetic_calibration" => true, "case_id" => item.fetch("id"), "calibration" => calibration }
      )
      raise ArgumentError, request.validation_errors.join("; ") unless request.valid?

      response = perform_calibration(request)
      failure = protocol_failure(response, allow_tool_call: false)
      @store.add_message(chat_id, role: "assistant", content: response.content,
        metadata: { "synthetic_calibration" => true, "response_envelope" => response.to_h })
      system_content = messages.first.fetch("content")
      {
        "kind" => "case",
        "condition" => calibration.fetch("condition"),
        "case_id" => item.fetch("id"),
        "sample" => sample_number,
        "seed" => sample_seed,
        "chat_id" => chat_id,
        "messages_sha256" => Digest::SHA256.hexdigest(JSON.generate(messages)),
        "system_sha256" => Digest::SHA256.hexdigest(system_content),
        "response_envelopes" => [response.to_h],
        "expected_checks" => item.fetch("expected").fetch("checks"),
        "protocol_failure" => failure,
        "needs_review" => true
      }.compact
    end

    def project_context(messages, item, context_mode)
      projected = messages.map(&:dup)
      dialogue = item.fetch("messages")
      supplied_dialogue = projected.drop(1).map { |message| message.slice("role", "content") }
      raise RuntimeError, "context builder changed supplied dialogue" unless supplied_dialogue == dialogue

      if context_mode == "focused"
        projected[0]["content"] = FOCUSED_SYSTEM_PROMPT
      end
      projected[0]["content"] = "#{projected[0].fetch('content').rstrip}\n\n#{AVAILABILITY_NOTICE}"
      projected
    end

    def perform_calibration(request)
      maximum = @provider.model == GEMMA_MODEL ? GEMMA_MAX_REQUESTS : MINISTRAL_MAX_REQUESTS
      raise RuntimeError, "maximum calibration request count exceeded" if @request_count >= maximum

      @request_count += 1
      @client.chat(provider: @provider, request: request)
    end

    def protocol_failure(response, allow_tool_call: false)
      return "response_error" unless response.error.nil?
      return "finish_length" if response.finish_reason.to_s == "length"
      return "unexpected_tool_call" unless response.tool_calls.empty?
      return "empty_reply" if response.content.to_s.strip.empty?

      nil
    end
  end
end
