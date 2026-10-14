# frozen_string_literal: true

require_relative "actions"
require_relative "context_builder"

module SoulCore
  module ContinuityLab
    # Necessary mechanical screening only. Natural-language correctness and
    # conversation quality still require the separately recorded primary review.
    module QualificationCasesA15
      VERSION = "foreground_usability_a15_v1"
      RENTALS = "Marigold workshop rental catalog. Alder costs 28 credits per day and has HDMI. Birch costs 42 credits per day and has HDMI plus battery power. Cedar costs 55 credits per day and has HDMI plus battery power. All units are available. Delivery arrangements are not recorded."
      GARDEN = "Copperfield garden supply list. Birch compost holds 8 litres per bag and costs 6 credits. Meadow compost holds 12 litres per bag and costs 9 credits. Summit compost holds 10 litres per bag and costs 11 credits. These are fictional planning figures; no purchase has been made."

      def self.corpus(batch)
        case batch
        when "planning" then [{ "id" => "rental-sheet", "content" => RENTALS }]
        when "holdout" then [{ "id" => "garden-sheet", "content" => GARDEN }]
        when "conversation" then []
        else raise ValidationError, "unsupported A15 batch"
        end
      end

      def self.row(id, content, facts: [], support: [], requires: [], **extra)
        { "id" => id, "content" => content, "facts" => facts, "support" => support,
          "requires_events" => requires }.merge(extra.transform_keys(&:to_s))
      end

      def self.cases(batch)
        rows = case batch
        when "planning"
          [row("m-plan", "For our fictional Marigold workshop, choose the least expensive projector with HDMI and battery power from the rental catalog. What would one day cost?",
               facts: ['\\bBirch\\b', '\\b42\\b'], support: [['corpus', '\\bBirch\\b', '\\b42\\b', 'battery']]),
           row("m-change", "For the Marigold workshop, let's use two Cedar projectors for one day instead. What is our revised rental total?",
               facts: ['\\bCedar\\b', '\\b110\\b'], support: [['any', '\\bCedar\\b', '\\b55\\b']]),
           row("m-recall", "Picking up the Marigold workshop again: which projector did we settle on, how many, and what is the total for one day?",
               facts: ['\\bCedar\\b', '\\b(?:2|two)\\b', '\\b110\\b'], support: [['prior', '\\bCedar\\b', '\\b(?:2|two)\\b']], requires: ['m-change']),
           row("m-unknown", "What delivery time did the Marigold workshop supplier confirm?",
               facts: ["not (?:recorded|provided|specified|confirmed|available)|no .*?(?:time|delivery|information|confirmation)|unknown|unspecified|haven't|hasn't|don't (?:have|know)|cannot (?:confirm|determine)|can't (?:confirm|determine)"], lookup: 'marigold|delivery|workshop')]
        when "holdout"
          [row("c-uppercase", "Please turn 'bring the blue notebook' into uppercase.", exact: "BRING THE BLUE NOTEBOOK", no_tools: true),
           row("c-plan", "Using the Copperfield garden supply list, how many Meadow bags would cover 36 litres, and what would they cost?",
               facts: ['\\bMeadow\\b', '\\b(?:3|three)\\b', '\\b27\\b'], support: [['corpus', '\\bMeadow\\b', '\\b12\\b', '\\b9\\b']]),
           row("c-change", "For Copperfield, revise that to four Birch bags. Please confirm their combined volume and cost.",
               facts: ['\\bBirch\\b', '\\b32\\b', '\\b24\\b'], support: [['any', '\\bBirch\\b', '\\b8\\b', '\\b6\\b']]),
           row("c-recall", "Back to Copperfield: what bag type, quantity, total volume and cost did we finish with?",
               facts: ['\\bBirch\\b', '\\b(?:4|four)\\b', '\\b32\\b', '\\b24\\b'], support: [['prior', '\\bBirch\\b', '\\b(?:4|four)\\b']], requires: ['c-change'])]
        when "conversation"
          [row("chat-walk", "Good evening. I've just got back from a long walk and finally sat down with some tea. How's it going?", semantic_only: true),
           row("chat-reason", "It was mostly to clear my head. Nothing dramatic; I just needed a break.", semantic_only: true),
           row("chat-drink", "By the way, the tea was a mistake—I've swapped it for hot chocolate.", semantic_only: true),
           row("chat-recall", "What am I drinking now, and what got me out of the house earlier?",
               facts: ['hot\\s+chocolate', 'clear.*head|break'], support: [['prior', 'hot\\s+chocolate', 'clear.*head|break']], requires: ['chat-reason', 'chat-drink'])]
        else raise ValidationError, "unsupported A15 batch"
        end
        rows.map { |spec| spec.merge("group" => batch) }
      end

      def self.matches?(pattern, text) = Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE).match?(text)

      def self.evaluate(event:, config:, spec:, before:, after:)
        calls = event.fetch("calls")
        reply = event["reply"].to_s
        reasons = []
        reasons << "event_identity_mismatch" unless event["event_id"] == spec["id"] && event["content"] == spec["content"] && after["lineage_id"] == before["lineage_id"]
        reasons << "not_completed_reply" unless event["state"] == "complete" && event["reason"] == "reply" && !reply.strip.empty?
        reasons << "terminal_action_missing_or_budget" unless calls.length.between?(1, config["max_model_calls"]) && Actions.parse(calls.last["response"], config) == { "action" => "reply", "content" => reply }
        envelope = calls.first && ContinuityLab.parse(calls.first.dig("context", "formatted"))
        clean = envelope.is_a?(Hash) && envelope.keys.sort == %w[context_policy execution_receipts lineage_id max_note_bytes system tool_contract tool_groups user].sort &&
          envelope["user"] == { "event_id" => spec.fetch("id"), "content" => spec.fetch("content") } &&
          envelope["lineage_id"] == before.fetch("lineage_id") && envelope["system"] == ContextBuilder::SYSTEM &&
          envelope["tool_contract"] == ContextBuilder::PROTOCOL && envelope["max_note_bytes"] == config["max_note_bytes"] &&
          envelope["context_policy"] == ReceiptContext::POLICY && envelope["tool_groups"] == [] && envelope["execution_receipts"] == []
        reasons << "initial_context_leak_or_mismatch" unless clean
        state = ContinuityLab.parse(ContinuityLab.encode(before))
        sources, tools, failures, invalid = [], [], 0, 0
        calls.each_with_index do |call, index|
          manifest = call.dig("context", "manifest") || {}
          covered = manifest.fetch("retained_receipts", []).map { |r| r.fetch("call_index") } + manifest.fetch("included_groups", [])
          reasons << "context_coverage_mismatch" unless manifest["context_policy"] == ReceiptContext::POLICY && covered == (0...index).to_a
          action = Actions.parse(call["response"], config)
          if action.empty?
            invalid += 1
            reasons << "invalid_action_result_mismatch" unless call["result"] == { "ok" => false, "reason" => "invalid_action" }
            next
          end
          unless action["action"] == "tool"
            reasons << "terminal_action_mismatch" unless index == calls.length - 1 && action == { "action" => "reply", "content" => reply } && call["result"].nil?
            next
          end
          tools << action.fetch("tool")
          expected = Actions.tool_result(state, action, config, event.fetch("event_id"))
          result = expected.fetch("result")
          reasons << "tool_result_replay_mismatch" unless call["result"] == result
          failures += 1 unless result["ok"]
          sources.concat(result["source"] ? [result["source"]] : result.fetch("hits", [])) if result["ok"]
          next unless expected["note"]
          note = expected.fetch("note")
          previous = state.fetch("notes")[note.fetch("note_id")]
          state["notes"][note["note_id"]] = note.merge("ancestry" => previous ? previous.fetch("ancestry") + [previous.fetch("revision")] : [])
        end
        reasons << "durable_notes_mismatch" unless state.fetch("notes") == after.fetch("notes")
        reasons << "invalid_action" if invalid.positive?
        reasons << "missing_expected_fact_tokens" unless spec.fetch("facts").all? { |p| matches?(p, reply) }
        reasons << "exact_reply_mismatch" if spec["exact"] && reply != spec["exact"]
        reasons << "unnecessary_tools" if spec["no_tools"] && !tools.empty?
        # A note written during this event cannot manufacture prior support.
        eligible = sources.select do |src|
          src["collection"] != "notes" || before.fetch("notes").values.any? do |note|
            !note["tombstone"] && note["note_id"] == src["id"] && note["revision"] == src["revision"] && note["content_digest"] == src["content_digest"]
          end
        end
        spec.fetch("support").each do |kind, *patterns|
          text = eligible.select { |s| kind == "any" || (kind == "prior" ? %w[notes history].include?(s["collection"]) : s["collection"] == kind) }.map { |s| s.fetch("text") }.join("\n")
          reasons << "missing_retrieved_support" unless patterns.all? { |p| matches?(p, text) }
        end
        if spec["lookup"]
          looked = calls.any? do |call|
            action = Actions.parse(call["response"], config)
            action["tool"] == "search" && call.dig("result", "ok") && matches?(spec["lookup"], action.dig("arguments", "query").to_s)
          end
          looked ||= eligible.any? { |s| matches?(spec["lookup"], s.fetch("text")) }
          reasons << "no_relevant_lookup" unless looked
        end
        { "passed" => reasons.empty?, "status" => reasons.empty? ? "eligible_for_primary_assessment" : "mechanical_failure", "reasons" => reasons.uniq,
          "semantic_review_required" => true, "semantic_only" => !!spec["semantic_only"], "reply" => reply, "tool_failures" => failures, "invalid_actions" => invalid,
          "sources" => sources, "note_actions" => tools.grep(/\Anote\./), "notes_changed" => before.fetch("notes") != after.fetch("notes"),
          "peak_input_tokens" => calls.filter_map { |c| c.dig("context", "manifest", "input_tokens") }.max }
      rescue StandardError => error
        { "passed" => false, "status" => "invalid_evidence", "reasons" => [error.class.name], "semantic_review_required" => true }
      end
    end
  end
end
