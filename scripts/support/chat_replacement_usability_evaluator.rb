# frozen_string_literal: true

require_relative "chat_replacement_calibration_evaluator"
require_relative "chat_replacement_usability_cases"

module SoulCore
  class ChatReplacementUsabilityEvaluator < ChatReplacementEvaluator
    MAX_REQUESTS = 24
    MAX_OUTPUT_TOKENS = 1536
    AVAILABILITY_NOTICE = ChatReplacementCalibrationEvaluator::AVAILABILITY_NOTICE

    def initialize(**arguments)
      super
      raise ArgumentError, "Usability trial requires native Gemma direct mode" unless
        @provider.model == "gemma4-e4b-it" && @temperature == 1.0 && @reasoning_mode == "disabled"
    end

    def run
      raise RuntimeError, "evaluator may only run once" if @ran
      @ran = true
      conversations = ChatReplacementUsabilityCases.conversations
      raise RuntimeError, "Unexpected usability schedule" unless conversations.size == 4 &&
        conversations.all? { |item| item.fetch("turns").size == 3 }
      records = []
      conversations.each_with_index do |item, conversation_index|
        (1..SAMPLE_COUNT).each do |sample|
          chat_id = @store.create_chat(initial_title: "Usability #{item.fetch('id')} sample #{sample}").fetch("id")
          dialogue = []
          item.fetch("turns").each_with_index do |turn, index|
            @store.add_message(chat_id, role: "user", content: turn.fetch("user"), metadata: { "synthetic_usability" => true })
            dialogue << { "role" => "user", "content" => turn.fetch("user") }
            messages = @context_builder.build(chat_id: chat_id, provider_privacy_class: @provider.privacy_class,
              provider_model: @provider.model).fetch("messages").map(&:dup)
            # A silently pruned history would not qualify the intended three-turn
            # conversation. Refuse instead of filling it with an idealized reply.
            raise RuntimeError, "Usability dialogue was altered or truncated" unless
              messages.drop(1).map { |message| message.slice("role", "content") } == dialogue
            messages[0]["content"] = "#{messages[0].fetch('content').rstrip}\n\n#{AVAILABILITY_NOTICE}"
            seed = 851_000 + conversation_index * 100 + sample * 10 + index + 1
            request = Contract::RequestEnvelope.new(conversation_id: chat_id, messages: messages,
              model: @provider.model, temperature: @temperature, max_output_tokens: MAX_OUTPUT_TOKENS,
              tools: [], reasoning_mode: "disabled", privacy_requirement: @provider.privacy_class,
              metadata: { "synthetic_usability" => true, "usability_seed" => seed })
            raise ArgumentError, request.validation_errors.join("; ") unless request.valid?
            raise RuntimeError, "Usability request budget exceeded" if @request_count >= MAX_REQUESTS
            @request_count += 1
            response = @client.chat(provider: @provider, request: request)
            failure = protocol_failure(response, allow_tool_call: false)
            record = {
              "kind" => "case", "case_id" => "#{item.fetch('id')}-turn-#{index + 1}",
              "conversation" => item.fetch("id"), "sample" => sample, "turn" => index + 1,
              "condition" => "full/direct", "chat_id" => chat_id, "seed" => seed,
              "messages_sha256" => Digest::SHA256.hexdigest(JSON.generate(messages)),
              "system_sha256" => Digest::SHA256.hexdigest(messages.first.fetch("content")),
              "dialogue" => dialogue.map(&:dup), "expected" => turn.fetch("expected"),
              "response_envelopes" => [response.to_h], "protocol_failure" => failure,
              "needs_review" => failure.nil?
            }.compact
            records << record
            yield record if block_given?
            # Do not invent an assistant turn or retry a failed interaction.
            raise RuntimeError, "Usability protocol failure: #{failure}; later turns unstarted" if failure
            @store.add_message(chat_id, role: "assistant", content: response.content,
              metadata: { "synthetic_usability" => true, "response_envelope" => response.to_h })
            dialogue << { "role" => "assistant", "content" => response.content }
          end
        end
      end
      raise RuntimeError, "Usability schedule incomplete" unless records.size == MAX_REQUESTS
      records
    end
  end
end
