# frozen_string_literal: true

require_relative "actions"
require_relative "context_builder"
require_relative "token_context"

module SoulCore
  module ContinuityLab
    # Mechanical A18 screening with context and tool evidence reconstructed
    # from the journal. It does not claim semantic or human acceptance.
    module QualificationUsabilityAssessmentA18
      RECENT_POLICY = "recent_dialogue_v1"

      def self.evaluate(event:, config:, spec:, before:, after:)
        calls = event.fetch("calls")
        reply = event["reply"].to_s
        reasons = []
        reasons << "event_identity_mismatch" unless event["event_id"] == spec["id"] && event["content"] == spec["content"] && after["lineage_id"] == before["lineage_id"]
        reasons << "not_completed_reply" unless event["state"] == "complete" && event["reason"] == "reply" && !reply.strip.empty?
        reasons << "terminal_action_missing_or_budget" unless calls.length.between?(1, config["max_model_calls"]) && Actions.parse(calls.last["response"], config) == { "action" => "reply", "content" => reply }

        # Snapshot JSON preserves journal insertion order, which is recent-event order.
        state = JSON.parse(JSON.generate(before))
        state.fetch("events")[event.fetch("event_id")] = event.merge("state" => "pending", "calls" => [],
          "tool_count" => 0, "invalid_count" => 0)
        sources, tools, failures, invalid = [], [], 0, 0
        reply_context_sources = []
        calls.each_with_index do |call, index|
          context = call.fetch("context")
          envelope = verify_context!(state: state, config: config, event_id: event.fetch("event_id"), call: call, index: index)
          reasons << "context_replay_mismatch" unless envelope
          if envelope
            recent = recent_dialogue_enabled?(config) ? valid_recent_sources(state, event.fetch("event_id"), envelope) : []
            direct = direct_evidence_enabled?(config) ? envelope.fetch("direct_corpus", []) : []
            sources.concat(recent)
            sources.concat(direct)
            if index == calls.length - 1 && Actions.parse(call["response"], config)["action"] == "reply"
              reply_context_sources = recent + direct + envelope.fetch("tool_groups", []).flat_map do |group|
                result = group.fetch("tool_result")
                result["source"] ? [result.fetch("source")] : result.fetch("hits", [])
              end
            end
          end

          action = Actions.parse(call.fetch("response"), config)
          if action.empty?
            invalid += 1
            reasons << "invalid_action_result_mismatch" unless call["result"] == { "ok" => false, "reason" => "invalid_action" }
            state.fetch("events").fetch(event.fetch("event_id")).fetch("calls") << call
            next
          end
          unless action["action"] == "tool"
            reasons << "terminal_action_mismatch" unless index == calls.length - 1 && action == { "action" => "reply", "content" => reply } && call["result"].nil?
            state.fetch("events").fetch(event.fetch("event_id")).fetch("calls") << call
            next
          end

          tools << action.fetch("tool")
          expected = Actions.tool_result(state, action, config, event.fetch("event_id"))
          result = expected.fetch("result")
          reasons << "tool_result_replay_mismatch" unless call["result"] == result
          failures += 1 unless result["ok"]
          sources.concat(result["source"] ? [result["source"]] : result.fetch("hits", [])) if result["ok"]
          state.fetch("events").fetch(event.fetch("event_id")).fetch("calls") << call
          next unless expected["note"]

          note = expected.fetch("note")
          previous = state.fetch("notes")[note.fetch("note_id")]
          state.fetch("notes")[note["note_id"]] = note.merge("ancestry" => previous ? previous.fetch("ancestry") + [previous.fetch("revision")] : [])
        end

        reasons << "durable_notes_mismatch" unless state.fetch("notes") == after.fetch("notes")
        reasons << "invalid_action" if invalid.positive?
        reasons << "missing_expected_fact_tokens" unless spec.fetch("facts").all? { |pattern| QualificationCasesA18.matches?(pattern, reply) }
        reasons << "exact_reply_mismatch" if spec["exact"] && reply != spec["exact"]
        reasons << "unnecessary_tools" if spec["no_tools"] && !tools.empty?

        eligible = reply_context_sources.select do |source|
          source["collection"] != "notes" || before.fetch("notes").values.any? do |note|
            !note["tombstone"] && note["note_id"] == source["id"] && note["revision"] == source["revision"] && note["content_digest"] == source["content_digest"]
          end
        end
        spec.fetch("support").each do |kind, *patterns|
          support_sources = if kind == "recent_dialogue"
                              eligible.select { |source| source["collection"] == "history" && source["provenance"] == "observed_exchange_not_verified_fact" }
                            else
                              eligible.select { |source| kind == "any" || source["collection"] == kind ||
                                (kind == "prior" && %w[notes history].include?(source["collection"])) }
                            end
          text = support_sources.map { |source| source.fetch("text") }.join("\n")
          reasons << "missing_retrieved_support" unless patterns.all? { |pattern| QualificationCasesA18.matches?(pattern, text) }
        end
        if spec["lookup"]
          looked = calls.any? do |call|
            action = Actions.parse(call["response"], config)
            action["tool"] == "search" && call.dig("result", "ok") && QualificationCasesA18.matches?(spec["lookup"], action.dig("arguments", "query").to_s)
          end
          looked ||= eligible.any? { |source| QualificationCasesA18.matches?(spec["lookup"], source.fetch("text")) }
          reasons << "no_relevant_lookup" unless looked
        end

        { "passed" => reasons.empty?, "status" => reasons.empty? ? "eligible_for_primary_assessment" : "mechanical_failure",
          "reasons" => reasons.uniq, "semantic_review_required" => true, "semantic_only" => !!spec["semantic_only"],
          "reply" => reply, "tool_failures" => failures, "invalid_actions" => invalid, "sources" => sources,
          "note_actions" => tools.grep(/\Anote\./), "notes_changed" => before.fetch("notes") != after.fetch("notes"),
          "peak_input_tokens" => calls.filter_map { |call| call.dig("context", "manifest", "input_tokens") }.max }
      rescue StandardError => error
        { "passed" => false, "status" => "invalid_evidence", "reasons" => [error.class.name], "semantic_review_required" => true }
      end

      def self.verify_context!(state:, config:, event_id:, call:, index:)
        context = call.fetch("context")
        observed = ContinuityLab.parse(context.fetch("formatted"))
        if recent_dialogue_enabled?(config)
          valid = valid_recent_sources(state, event_id, observed)
          return unless valid.length == observed.fetch("recent_dialogue", []).length
        end
        if config.tokenized_context?
          finalized = TokenContext.finalize(state: state, event_id: event_id, config: config,
            preparation: context.fetch("preparation"))
          expected = finalized.fetch("formatted")
          expected_manifest = finalized.fetch("manifest")
          return unless context["formatted"] == expected && context["manifest"] == expected_manifest
        else
          expected = ContextBuilder.build(state: state, event_id: event_id, config: config).fetch("formatted")
          return unless context["formatted"] == expected
        end
        envelope = ContinuityLab.parse(context.fetch("formatted"))
        return unless envelope.is_a?(Hash) && envelope["user"] == { "event_id" => event_id, "content" => state.fetch("events").fetch(event_id).fetch("content") } &&
          envelope["lineage_id"] == state.fetch("lineage_id") && state.fetch("events").fetch(event_id).fetch("calls").length == index

        if recent_dialogue_enabled?(config)
          return unless envelope["recent_dialogue_policy"] == RECENT_POLICY && envelope["recent_dialogue"].is_a?(Array)
        else
          return if envelope.key?("recent_dialogue_policy") || envelope.key?("recent_dialogue")
        end
        if direct_evidence_enabled?(config)
          return unless envelope["direct_corpus"].is_a?(Array)
        else
          return if envelope.key?("direct_corpus")
        end
        envelope
      rescue KeyError, ValidationError, JSON::ParserError
        nil
      end
      private_class_method :verify_context!

      def self.recent_dialogue_enabled?(config)
        config.respond_to?(:recent_dialogue?) && config.recent_dialogue?
      end
      private_class_method :recent_dialogue_enabled?

      def self.direct_evidence_enabled?(config)
        config.respond_to?(:direct_evidence?) && config.direct_evidence?
      end
      private_class_method :direct_evidence_enabled?

      # A manifest alone is not evidence. Accept only full source objects that
      # exactly match a source regenerated from preceding journal exchanges.
      def self.valid_recent_sources(state, event_id, envelope)
        return [] unless envelope.is_a?(Hash) && envelope["recent_dialogue"].is_a?(Array)
        docs = Retrieval.documents(state, "history", event_id).to_h { |doc| [doc.fetch("id"), doc] }
        envelope.fetch("recent_dialogue").filter_map do |source|
          next unless source.is_a?(Hash) && source.keys.sort == %w[collection content_digest id lineage_id provenance revision span text]
          doc = docs[source["id"]]
          next unless doc && Retrieval.source(state, "history", doc, 0, doc.fetch("content").length) == source

          source
        end
      end
      private_class_method :valid_recent_sources
    end
  end
end
