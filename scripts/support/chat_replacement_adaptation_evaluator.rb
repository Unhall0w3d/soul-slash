# frozen_string_literal: true

require_relative "chat_replacement_usability_evaluator"
require_relative "chat_replacement_adaptation_cases"

module SoulCore
  class ChatReplacementAdaptationEvaluator < ChatReplacementUsabilityEvaluator
    MAX_REQUESTS = 48
    CONDITIONS = %w[baseline guided].freeze
    GUIDANCE = <<~TEXT.freeze
      Task-specific fidelity guidance:
      When rewriting or summarizing supplied facts, preserve qualifications, uncertainty, conditions, and action state. Ability or permission is not a promise; a possible date is not a scheduled or targeted date; starting an action is not finishing it. Apply explicit corrections without upgrading unchanged facts.
      When interpreting an event timeline or incident, distinguish reported observations from hypotheses and established causes. Temporal order alone does not establish cause. Say when cause or outcome is not established; suggest a concrete check without presenting it as performed.
      In ordinary conversation or open-ended creative help, respond naturally to the user's preferences rather than imposing an audit checklist.
    TEXT

    def self.schedule
      ChatReplacementAdaptationCases.conversations.each_with_index.flat_map do |item, index|
        (1..SAMPLE_COUNT).flat_map do |sample|
          order = (index + sample).even? ? CONDITIONS : CONDITIONS.reverse
          order.map { |condition| { "case" => item, "case_index" => index, "sample" => sample, "condition" => condition } }
        end
      end
    end

    def run
      raise RuntimeError, "evaluator may only run once" if @ran
      @ran = true
      catalog = ChatReplacementAdaptationCases.conversations
      raise RuntimeError, "Unexpected adaptation schedule" unless catalog.size == 6 &&
        catalog.all? { |item| item.fetch("turns").size == 2 } &&
        catalog.map { |item| item.fetch("family") }.tally == { "rewrite" => 2, "incident" => 2, "conversation" => 1, "creative" => 1 }
      records = []
      self.class.schedule.each do |entry|
        item, case_index, sample, condition = entry.values_at("case", "case_index", "sample", "condition")
        chat_id = @store.create_chat(initial_title: "Adaptation #{item.fetch('id')} #{sample} #{condition}").fetch("id")
        dialogue = []
        item.fetch("turns").each_with_index do |turn, index|
          @store.add_message(chat_id, role: "user", content: turn.fetch("user"), metadata: { "synthetic_adaptation" => true })
          dialogue << { "role" => "user", "content" => turn.fetch("user") }
          messages = @context_builder.build(chat_id: chat_id, provider_privacy_class: @provider.privacy_class,
            provider_model: @provider.model).fetch("messages").map(&:dup)
          raise RuntimeError, "Adaptation dialogue was altered or truncated" unless
            messages.drop(1).map { |message| message.slice("role", "content") } == dialogue
          base_system = "#{messages.first.fetch('content').rstrip}\n\n#{AVAILABILITY_NOTICE}"
          messages[0]["content"] = condition == "guided" ? "#{base_system}\n\n#{GUIDANCE.rstrip}" : base_system
          # Equal seeds pair the budget/settings, not the later generated history.
          # Each condition carries its own actual reply into the second turn.
          seed = 851_001 + case_index * 40 + (sample - 1) * 10 + index
          request = Contract::RequestEnvelope.new(conversation_id: chat_id, messages: messages,
            model: @provider.model, temperature: @temperature, max_output_tokens: MAX_OUTPUT_TOKENS,
            tools: [], reasoning_mode: "disabled", privacy_requirement: @provider.privacy_class,
            metadata: { "synthetic_adaptation" => true, "usability_seed" => seed })
          raise ArgumentError, request.validation_errors.join("; ") unless request.valid?
          raise RuntimeError, "Adaptation request budget exceeded" if @request_count >= MAX_REQUESTS
          @request_count += 1
          response = @client.chat(provider: @provider, request: request)
          failure = protocol_failure(response, allow_tool_call: false)
          record = {
            "kind" => "case", "case_id" => "#{item.fetch('id')}-turn-#{index + 1}",
            "conversation" => item.fetch("id"), "family" => item.fetch("family"),
            "sample" => sample, "turn" => index + 1, "condition" => condition,
            "chat_id" => chat_id, "seed" => seed,
            "messages_sha256" => Digest::SHA256.hexdigest(JSON.generate(messages)),
            "base_system_sha256" => Digest::SHA256.hexdigest(base_system),
            "system_sha256" => Digest::SHA256.hexdigest(messages.first.fetch("content")),
            "guidance_sha256" => condition == "guided" ? Digest::SHA256.hexdigest(GUIDANCE.rstrip) : nil,
            "dialogue" => dialogue.map(&:dup), "expected" => turn.fetch("expected"),
            "response_envelopes" => [response.to_h], "protocol_failure" => failure,
            "needs_review" => failure.nil?
          }.compact
          records << record
          yield record if block_given?
          raise RuntimeError, "Adaptation protocol failure: #{failure}; later turns unstarted" if failure
          @store.add_message(chat_id, role: "assistant", content: response.content,
            metadata: { "synthetic_adaptation" => true, "response_envelope" => response.to_h })
          dialogue << { "role" => "assistant", "content" => response.content }
        end
      end
      raise RuntimeError, "Adaptation schedule incomplete" unless records.size == MAX_REQUESTS
      records
    end
  end
end
