# frozen_string_literal: true

require_relative "chat_replacement_usability_evaluator"
require_relative "chat_replacement_source_check_evaluator"
require_relative "chat_replacement_entailment_cases"

module SoulCore
  class ChatReplacementEntailmentEvaluator < ChatReplacementSourceCheckEvaluator
    MAX_REQUESTS = 48
    GUIDANCE = <<~TEXT.freeze
      Before the final verdict, compare each claim's exact proposition to the source, including dates, bounds, quantities, conditions, and negation. A quotation is evidence only if its meaning entails the claim, not merely because it contains similar words.
      Ask: could the source be true while this claim is false? If yes, it is not supported. Then ask: does the source positively rule out the claim? If not, use not established, not contradicted. Missing inspection or missing information is not proof of the opposite. Do not infer contents from packaging or an exact time from a time interval. Preserve valid paraphrases and necessary arithmetic.
      For each A and B, briefly give the source evidence and the logical gap or support, then finish with a separate line 'A: supported', 'A: contradicted', or 'A: not established' (and likewise for B). No rewriting or external knowledge.
    TEXT

    def self.schedule
      ChatReplacementEntailmentCases.cases.each_with_index.flat_map do |item, index|
        [1, 2].flat_map do |sample|
          order = (index + sample).even? ? %w[faithful distorted] : %w[distorted faithful]
          order.flat_map do |variant|
            conditions = (index + sample).even? ? %w[baseline entailment] : %w[entailment baseline]
            conditions.map { |condition| [item, index, sample, variant, condition] }
          end
        end
      end
    end

    def run
      raise RuntimeError, "evaluator may only run once" if @ran
      @ran = true
      self.class.schedule.map do |item, index, sample, variant, condition|
        draft = "A: #{item.fetch('a')}\nB: #{item.fetch(variant)}"
        instruction = condition == "entailment" ? "#{INSTRUCTION}\n#{GUIDANCE}" : INSTRUCTION
        prompt = "#{instruction}\nSOURCE:\n#{item.fetch('source')}\n\nDRAFT:\n#{draft}"
        chat_id = @store.create_chat(initial_title: "Source check").fetch("id")
        @store.add_message(chat_id, role: "user", content: prompt, metadata: { "synthetic_source_check" => true })
        messages = @context_builder.build(chat_id: chat_id, provider_privacy_class: @provider.privacy_class,
          provider_model: @provider.model).fetch("messages").map(&:dup)
        raise "Source-check context changed" unless messages.drop(1) == [{ "role" => "user", "content" => prompt }]
        messages[0]["content"] = "#{messages[0].fetch('content').rstrip}\n\n#{AVAILABILITY_NOTICE}"
        seed = 851_001 + index * 40 + (sample - 1) * 10
        request = Contract::RequestEnvelope.new(conversation_id: chat_id, messages: messages,
          model: @provider.model, temperature: @temperature, max_output_tokens: MAX_OUTPUT_TOKENS,
          tools: [], reasoning_mode: "disabled", privacy_requirement: @provider.privacy_class,
          metadata: { "synthetic_source_check" => true, "usability_seed" => seed })
        raise ArgumentError, request.validation_errors.join("; ") unless request.valid?
        raise "Source-check budget exceeded" if @request_count >= MAX_REQUESTS
        @request_count += 1
        response = @client.chat(provider: @provider, request: request)
        failure = protocol_failure(response, allow_tool_call: false)
        record = { "kind" => "case", "case_id" => item.fetch("id"), "sample" => sample,
          "condition" => "#{condition}-#{variant}", "prompt_condition" => condition, "variant" => variant, "chat_id" => chat_id, "seed" => seed,
          "source" => item.fetch("source"), "draft" => draft,
          "source_revision" => Digest::SHA256.hexdigest(item.fetch("source")),
          "draft_revision" => Digest::SHA256.hexdigest(draft),
          "messages_sha256" => Digest::SHA256.hexdigest(JSON.generate(messages)),
          "expected" => { "A" => "supported", "B" => variant == "faithful" ? "supported" : item.fetch("bad_label"),
            "rationale" => item.fetch("rationale") },
          "response_envelopes" => [response.to_h], "protocol_failure" => failure, "needs_review" => failure.nil? }
        yield record if block_given?
        raise "Source-check protocol failure: #{failure}" if failure
        record
      end
    end
  end
end
