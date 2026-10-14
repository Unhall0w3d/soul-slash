# frozen_string_literal: true

require_relative "context_builder"

module SoulCore
  module ContinuityLab
    # Pure reconstruction of host-attested token preparation. Replay validates
    # eligible data and receipt bindings without contacting or rerunning a model.
    module TokenContext
      VERSION = "qwen_tokenized_v1"
      PROTOCOL = "qwen_envelope_v4_token_preparation"
      TEMPLATE = "57f1fd00f0013a2be96aa79b857391f27e23df5b5f847072b524c897e24d0361"
      COUNTER = "installed_llama_b9851_tokenize_v1"
      MAX_BYTES = 12_288
      DIGEST = /\A[0-9a-f]{64}\z/

      def self.budget(config)
        value = config["context_tokens"] - config["output_tokens"] - config["context_margin"]
        raise ValidationError, "unsupported token profile" unless config.tokenized_context? && [2048, 3072].include?(value)
        value
      end

      def self.initial(state:, event_id:, config:)
        budget(config)
        envelope = ContextBuilder.envelope(state: state, event_id: event_id, config: config)
        while ContinuityLab.encode(envelope).bytesize > MAX_BYTES
          raise ContextBudgetExceeded, "essential input exceeds pipe bound" unless ContextBuilder.omittable?(envelope)
          ContextBuilder.omit_oldest!(envelope)
        end
        ContinuityLab.encode(envelope)
      end

      def self.measurement(envelope, prompt, tokens)
        { "envelope_sha256" => Digest::SHA256.hexdigest(envelope), "prompt_sha256" => Digest::SHA256.hexdigest(prompt),
          "input_tokens" => tokens.length, "token_ids_sha256" => ContinuityLab.digest(tokens) }
      end

      def self.preparation(initial:, formatted:, measurements:, input_budget:, call_index:, status: "ready")
        { "version" => VERSION, "protocol_version" => PROTOCOL, "template_sha256" => TEMPLATE,
          "status" => status,
          "call_index" => call_index, "initial_sha256" => Digest::SHA256.hexdigest(initial),
          "formatted" => formatted, "input_budget" => input_budget, "measurements" => measurements }
      end

      def self.finalize(state:, event_id:, config:, preparation:, rejected: false)
        input = initial(state: state, event_id: event_id, config: config)
        prep = preparation
        fields = %w[version protocol_version template_sha256 call_index initial_sha256 formatted input_budget measurements status]
        unless prep.is_a?(Hash) && prep.keys.sort == fields.sort && prep["version"] == VERSION &&
               prep["protocol_version"] == PROTOCOL && prep["template_sha256"] == TEMPLATE &&
               prep["status"] == (rejected ? "rejected" : "ready") &&
               prep["call_index"].is_a?(Integer) && prep["call_index"] == state.fetch("events").fetch(event_id).fetch("calls").length &&
               prep["initial_sha256"] == Digest::SHA256.hexdigest(input) && prep["input_budget"].is_a?(Integer) && prep["input_budget"] == budget(config) &&
               prep["measurements"].is_a?(Array) && prep["measurements"].length.between?(1, config.recent_dialogue? ? 9 : 6)
          raise ValidationError, "invalid context preparation binding"
        end
        envelope = ContinuityLab.parse(input)
        measured = prep.fetch("measurements")
        measured.each_with_index do |row, index|
          unless row.is_a?(Hash) && row.keys.sort == %w[envelope_sha256 input_tokens prompt_sha256 token_ids_sha256] &&
                 row["envelope_sha256"] == Digest::SHA256.hexdigest(ContinuityLab.encode(envelope)) &&
                 %w[prompt_sha256 token_ids_sha256].all? { |key| row[key].is_a?(String) && row[key].match?(DIGEST) } &&
                 row["input_tokens"].is_a?(Integer) && row["input_tokens"].between?(1, 131_072)
            raise ValidationError, "invalid token measurement"
          end
          over_budget = row["input_tokens"] > budget(config) || ContinuityLab.encode(envelope).bytesize > MAX_BYTES
          if index == measured.length - 1
            valid = rejected ? over_budget && !ContextBuilder.omittable?(envelope) : !over_budget
            raise ValidationError, "prepared context budget mismatch" unless valid
          else
            unless over_budget && ContextBuilder.omittable?(envelope)
              raise ValidationError, "unjustified context omission"
            end
            ContextBuilder.omit_oldest!(envelope)
          end
        end
        formatted = ContinuityLab.encode(envelope)
        raise ValidationError, "selected context mismatch" unless prep["formatted"] == formatted
        all = ContextBuilder.envelope(state: state, event_id: event_id, config: config)
        initial_ids = ContinuityLab.parse(input)["tool_groups"].map { |g| g["call_index"] }
        included = envelope["tool_groups"].map { |g| g["call_index"] }
        omitted = all["tool_groups"].reject { |g| included.include?(g["call_index"]) }.map do |group|
          { "call_index" => group["call_index"], "reason" => initial_ids.include?(group["call_index"]) ? "actual_input_budget" : "input_byte_limit",
            "sources" => ContextBuilder.group_sources(group) }
        end
        event = state.fetch("events").fetch(event_id)
        sources = [{ "kind" => "current_request", "id" => event_id, "revision" => 1,
                     "content_digest" => event.fetch("content_digest"), "span" => [0, event.fetch("content").length] }]
        envelope["tool_groups"].each { |group| sources.concat(ContextBuilder.group_sources(group)) }
        manifest = { "lineage_id" => state["lineage_id"], "config_digest" => config.digest,
          "corpus_digest" => state["corpus_digest"], "formatter" => PROTOCOL, "counter" => COUNTER,
          "preparation_digest" => ContinuityLab.digest(prep), "formatted_digest" => Digest::SHA256.hexdigest(formatted),
          "input_tokens" => measured.last["input_tokens"], "total_tokens" => config["context_tokens"],
          "output_reserve" => config["output_tokens"], "margin" => config["context_margin"],
          "included_groups" => included, "omitted_groups" => omitted, "sources" => sources }
        manifest["retrieval_policy"] = Config::RANKED_RETRIEVAL if config.ranked_retrieval?
        if config.recent_dialogue?
          RecentDialogue.validate_envelope!(envelope)
          selected = envelope.fetch("recent_dialogue")
          initial_recent = ContinuityLab.parse(input).fetch("recent_dialogue").map { |source| source.fetch("id") }
          manifest["recent_dialogue_policy"] = Config::RECENT_DIALOGUE
          manifest["included_recent_dialogue"] = selected.map { |source| source.fetch("id") }
          manifest["omitted_recent_dialogue"] = RecentDialogue.candidates(state, event_id).reject do |source|
            manifest["included_recent_dialogue"].include?(source.fetch("id"))
          end.map do |source|
            source.reject { |key, _| key == "text" }.merge(
              "reason" => initial_recent.include?(source.fetch("id")) ? "actual_input_budget" : "input_byte_limit")
          end
          sources.concat(selected.map { |source| source.reject { |key, _| key == "text" }.merge("kind" => "recent_dialogue") })
        end
        if config.direct_evidence?
          DirectEvidence.validate_envelope!(envelope)
          manifest["answer_policy"] = Config::DIRECT_EVIDENCE
          sources.concat(envelope.fetch("direct_corpus").map { |source| source.reject { |key, _| key == "text" }.merge("kind" => "direct_corpus") })
        end
        if config.receipt_context?
          ReceiptContext.validate_envelope!(envelope, call_index: prep.fetch("call_index"))
          manifest["context_policy"] = ReceiptContext::POLICY
          # 'sources' still means fully included groups. Receipt metadata does
          # not imply that their old source text is present or understood.
          manifest["retained_receipts"] = envelope.fetch("execution_receipts").map do |receipt|
            group = all.fetch("tool_groups").find { |entry| entry["call_index"] == receipt["call_index"] }
            ContextBuilder.group_sources(group).first.merge("receipt_digest" => ContinuityLab.digest(receipt))
          end
        end
        { "formatted" => formatted, "manifest" => manifest, "preparation" => prep }
      end
    end
  end
end
