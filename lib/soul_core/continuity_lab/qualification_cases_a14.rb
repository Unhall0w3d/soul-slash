# frozen_string_literal: true

require_relative "qualification_cases_a4"
require_relative "qualification_scorer"

module SoulCore
  module ContinuityLab
    # Directed qualification only. Expected answers and actions never enter the
    # live worker as fixtures or controller hints beyond the recorded request.
    module QualificationCasesA14
      VERSION = "records_notes_fresh_worker_a14_v3_structured_reads"
      SOURCE = "The survey archive records the calibration phrase as copper heron 58. This phrase is a synthetic fixture, not a credential."
      LOCATOR = "Survey source locator: collection corpus, id survey, revision 1. Contents not stored in this note."
      CORPUS = [{ "id" => "survey", "content" => SOURCE }].freeze
      BASE = QualificationCasesA4

      def self.read(collection, id, revision, content = "", length = 100)
        BASE.read_step(collection, id, revision, content, 0, length)
      end

      def self.negative_read(collection, id, revision, reason)
        read(collection, id, revision).merge("result" => { "ok" => false, "reason" => reason })
      end

      def self.empty_search(collection, query)
        { "action" => BASE.action("search", { "lineage_id" => "$lineage", "collection" => collection, "query" => query, "limit" => 2 }),
          "result" => { "ok" => true, "hits" => [] } }
      end

      def self.cases(batch)
        original = BASE.cases.to_h { |spec| [spec.fetch("id"), spec] }
        rows = case batch
        when "notes"
          stale_write = BASE.write_step("beacon", 0, "stale candidate code 12").merge("result" => { "ok" => false, "reason" => "revision_conflict" })
          [
            original.fetch("note-seed").merge("requires_events" => []),
            original.fetch("note-read").merge("requires_events" => ["note-seed"]),
            { "id" => "note-revision-boundary", "requires_events" => ["note-read"],
              "content" => "Exercise these four operations IN ORDER on note_id beacon: first note.write expected_revision 0 with content exactly stale candidate code 12 (this must be rejected as stale); then note.write expected_revision 1 with content exactly amber beacon code 91. Next read notes id beacon revision 1 start 0 length 100 (expect revision_conflict), then read the same note at revision 2 start 0 length 100. Use current lineage_id for reads. After all four results, reply only with the current note text from the final read. Do not retry the intentionally stale operations.",
              "contract" => { "requires_notes" => BASE.note("beacon", 1, "amber beacon code 73"),
                "steps" => [stale_write, BASE.write_step("beacon", 1, "amber beacon code 91"),
                  negative_read("notes", "beacon", 1, "revision_conflict"), read("notes", "beacon", 2, "amber beacon code 91")],
                "final_notes" => BASE.note("beacon", 2, "amber beacon code 91"), "reply" => "amber beacon code 91" } },
            { "id" => "note-deleted-boundary", "requires_events" => ["note-revision-boundary"],
              "content" => "Use note.tombstone with note_id beacon and expected_revision 2. After success, search notes for amber with limit 2, then read notes id beacon revision 2 start 0 length 100. Use current lineage_id. If search is empty and read returns not_found, reply only NOT FOUND. Do not recreate the note or recover old text from history.",
              "contract" => { "requires_notes" => BASE.note("beacon", 2, "amber beacon code 91"),
                "steps" => [BASE.delete_step("beacon", 2), empty_search("notes", "amber"), negative_read("notes", "beacon", 2, "not_found")],
                "final_notes" => BASE.note("beacon", 3, "", true), "reply" => "NOT FOUND" } }
          ]
        when "sources"
          access = { "id" => "source-access", "requires_events" => [],
            "content" => "Read corpus id survey revision 1 start 0 length 256 using current lineage_id. After success, use note.write note_id locator expected_revision 0 with content equal to this exact string, including both sentences and punctuation (without the surrounding quotes): #{LOCATOR.to_json}\nAfter the write succeeds, reply only ACCESSED. Do not copy the source contents into the note or reply.",
            "contract" => { "steps" => [read("corpus", "survey", 1, SOURCE, 256), BASE.write_step("locator", 0, LOCATOR)],
              "final_notes" => BASE.note("locator", 1, LOCATOR), "reply" => "ACCESSED" } }
          exchange = ContinuityLab.encode({ "user" => access.fetch("content"), "assistant" => "ACCESSED" })
          [access,
            { "id" => "source-after-restart", "requires_events" => ["source-access"],
              "content" => "Perform these three read operations IN ORDER, using current lineage_id for each:\n1. collection=history, id=\"source-access\", revision=1, start=0, length=1024.\n2. collection=notes, id=\"locator\", revision=1, start=0, length=256.\n3. collection=corpus, id taken from the source locator returned by step 2, revision=1, start=0, length=256.\nThe history and locator do not contain the source text. After the third read, reply only with the value of the calibration phrase found in that source, without its label or trailing punctuation. Do not create or change notes.",
              "contract" => { "requires_notes" => BASE.note("locator", 1, LOCATOR),
                "steps" => [read("history", "source-access", 1, exchange, 1024), read("notes", "locator", 1, LOCATOR, 256), read("corpus", "survey", 1, SOURCE, 256)],
                "reply" => "copper heron 58" } },
            { "id" => "unretained-fact", "requires_events" => [],
              "content" => "What is the fictional windmill serial? First search notes for windmill with limit 2, then read corpus id windmill revision 1 start 0 length 100, using current lineage_id. If neither result provides the serial, reply only UNKNOWN. Do not infer a serial from unrelated records or create a note.",
              "contract" => { "steps" => [empty_search("notes", "windmill"), negative_read("corpus", "windmill", 1, "not_found")], "reply" => "UNKNOWN" } }
          ]
        else raise ValidationError, "unsupported A14 batch"
        end
        rows.map { |spec| spec.merge("group" => batch) }
      end

      # Qualification-only checks supplement, never weaken, the frozen scorer.
      def self.evaluate(event:, config:, lineage_id:, spec:, before_notes:, after_notes:)
        score = QualificationScorer.evaluate(event: event, config: config, lineage_id: lineage_id,
          contract: spec.fetch("contract"), before_notes: before_notes, after_notes: after_notes)
        calls = event.fetch("calls", [])
        steps = spec.fetch("contract").fetch("steps", [])
        exact_attempts = calls.length == steps.length + 1 && score.fetch("matched_call_indices") == (0...steps.length).to_a
        first = calls.first&.dig("context", "formatted")
        envelope = first && ContinuityLab.parse(first)
        clean_start = envelope.is_a?(Hash) && envelope["tool_groups"] == [] && envelope["execution_receipts"] == [] &&
          envelope["context_policy"] == ReceiptContext::POLICY && envelope["lineage_id"] == lineage_id &&
          envelope["user"] == { "event_id" => event.fetch("event_id"), "content" => spec.fetch("content") } &&
          envelope["system"] == ContextBuilder::SYSTEM && envelope["tool_contract"] == ContextBuilder::PROTOCOL &&
          envelope["max_note_bytes"] == config["max_note_bytes"] &&
          envelope.keys.sort == %w[context_policy execution_receipts lineage_id max_note_bytes system tool_contract tool_groups user].sort
        coverage = calls.each_with_index.all? do |call, index|
          manifest = call.dig("context", "manifest") || {}
          receipt_ids = manifest.fetch("retained_receipts", []).map { |r| r.fetch("call_index") }
          manifest["context_policy"] == ReceiptContext::POLICY && manifest["included_groups"].is_a?(Array) &&
            receipt_ids + manifest["included_groups"] == (0...index).to_a
        end
        expected_notes = ContinuityLab.parse(ContinuityLab.encode(before_notes))
        # Reconstruct only the requested successful note effects. This detects
        # extra mutations even if the requested final note is also present.
        steps.each do |step|
          action = step.fetch("action")
          next unless action.fetch("tool").start_with?("note.") && step.dig("result", "ok")
          applied = Actions.tool_result({ "notes" => expected_notes }, action, config, event.fetch("event_id"))
          raise ValidationError, "invalid expected note transition" unless applied.dig("result", "ok")
          note = applied.fetch("note")
          previous = expected_notes[note.fetch("note_id")]
          ancestry = previous ? previous.fetch("ancestry") + [previous.fetch("revision")] : []
          expected_notes[note.fetch("note_id")] = note.merge("ancestry" => ancestry)
        end
        boundaries = { "exact_attempts" => exact_attempts, "clean_initial_context" => clean_start,
                       "receipt_coverage" => coverage, "exact_durable_notes" => expected_notes == after_notes }
        passed = score.fetch("passed") && boundaries.values.all?
        score.merge("passed" => passed, "status" => passed ? "passed" : "failed", "boundaries" => boundaries,
          "reasons" => score.fetch("reasons") + boundaries.filter_map { |key, ok| "a14_#{key}" unless ok })
      rescue StandardError
        { "passed" => false, "status" => "failed", "reasons" => ["malformed_a14_evidence"] }
      end
    end
  end
end
