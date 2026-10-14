# frozen_string_literal: true

require_relative "store"

module SoulCore
  module ContinuityLab
    # Explicit synthetic test data, never loaded by ordinary Soul chat.
    module QualificationCasesA4
      VERSION = "result_bound_focused_a4_v1"
      CORPUS = [
        { "id" => "charter", "content" => "The synthetic charter beacon is blue." },
        { "id" => "long", "content" => ("x" * 1024) + ("y" * 1024) + ("z" * 1024) + ("w" * 950) + " Final marker TEAL-42." },
        { "id" => "rollover", "content" => "Marker OPAL-19.".ljust(1024, "x") + ("y" * 1024) + ("z" * 1024) }
      ].freeze

      def self.action(tool, arguments) = { "action" => "tool", "tool" => tool, "arguments" => arguments }
      def self.note(id, revision, content, tombstone = false)
        { id => { "revision" => revision, "content" => content, "tombstone" => tombstone } }
      end

      def self.write_step(id, prior, content)
        { "action" => action("note.write", { "note_id" => id, "expected_revision" => prior, "content" => content }),
          "result" => { "ok" => true, "note_id" => id, "revision" => prior + 1 } }
      end

      def self.delete_step(id, prior)
        { "action" => action("note.tombstone", { "note_id" => id, "expected_revision" => prior }),
          "result" => { "ok" => true, "note_id" => id, "revision" => prior + 1 } }
      end

      def self.read_step(collection, id, revision, content, start = 0, length = 100)
        text = content[start, length] || ""
        { "action" => action("read", { "lineage_id" => "$lineage", "collection" => collection, "id" => id,
                                      "revision" => revision, "start" => start, "length" => length }),
          "result" => { "ok" => true, "source" => { "lineage_id" => "$lineage", "collection" => collection,
            "id" => id, "revision" => revision, "content_digest" => Digest::SHA256.hexdigest(content),
            "span" => [start, start + text.length], "text" => text } } }
      end

      def self.cases
        charter = CORPUS[0]["content"]
        search = action("search", { "lineage_id" => "$lineage", "collection" => "notes", "query" => "amber", "limit" => 2 })
        corpus_search = action("search", { "lineage_id" => "$lineage", "collection" => "corpus", "query" => "charter", "limit" => 1 })
        missing = read_step("corpus", "absent", 1, "")
        missing["result"] = { "ok" => false, "reason" => "not_found" }
        rows = [
          ["reply", "chain", "Reply with the single word four. Do not echo this instruction or use tools.", { "reply" => "four" }],
          ["note-seed", "chain", "Use note.write with note_id beacon, expected_revision 0, content exactly amber beacon code 73. After successful write reply SAVED; do not write twice.",
           { "steps" => [write_step("beacon", 0, "amber beacon code 73")], "final_notes" => note("beacon", 1, "amber beacon code 73"), "reply" => "SAVED" }],
          ["note-read", "chain", "Read collection notes, id beacon, revision 1, start 0, length 100 using actual current lineage_id. Reply with its exact text.",
           { "requires_notes" => note("beacon", 1, "amber beacon code 73"), "steps" => [read_step("notes", "beacon", 1, "amber beacon code 73")], "reply" => "amber beacon code 73" }],
          ["note-correct", "chain", "Use note.write with note_id beacon (not its content), expected_revision 1, content exactly amber beacon code 91. After successful write reply UPDATED; do not write twice.",
           { "requires_notes" => note("beacon", 1, "amber beacon code 73"), "steps" => [write_step("beacon", 1, "amber beacon code 91")], "final_notes" => note("beacon", 2, "amber beacon code 91"), "reply" => "UPDATED" }],
          ["note-read-corrected", "chain", "Read collection notes, id beacon, revision 2, start 0, length 100 using actual current lineage_id. Reply with its exact text.",
           { "requires_notes" => note("beacon", 2, "amber beacon code 91"), "steps" => [read_step("notes", "beacon", 2, "amber beacon code 91")], "reply" => "amber beacon code 91" }],
          ["note-tombstone", "chain", "Use note.tombstone with note_id beacon and expected_revision 2. After successful result reply REMOVED.",
           { "requires_notes" => note("beacon", 2, "amber beacon code 91"), "steps" => [delete_step("beacon", 2)], "final_notes" => note("beacon", 3, "", true), "reply" => "REMOVED" }],
          ["tombstone-search", "chain", "Search collection notes for amber with limit 2 and current lineage_id. If results are empty reply NOT FOUND.",
           { "requires_notes" => note("beacon", 3, "", true), "steps" => [{ "action" => search, "result" => { "ok" => true, "hits" => [] } }], "reply" => "NOT FOUND" }],
          ["independent-correct", "independent", "A deterministic fixture seeded note_id correction at revision 1. Use note.write with note_id correction, expected_revision 1, content exactly repaired code 82. After success reply UPDATED.",
           { "requires_notes" => note("correction", 1, "initial code 41"), "steps" => [write_step("correction", 1, "repaired code 82")], "final_notes" => note("correction", 2, "repaired code 82"), "reply" => "UPDATED" }],
          ["independent-tombstone", "independent", "A deterministic fixture seeded note_id deletion at revision 1. Use note.tombstone with note_id deletion, expected_revision 1. After success reply REMOVED.",
           { "requires_notes" => note("deletion", 1, "disposable code 66"), "steps" => [delete_step("deletion", 1)], "final_notes" => note("deletion", 2, "", true), "reply" => "REMOVED" }],
          ["missing-source", "independent", "Read collection corpus id absent revision 1 start 0 length 100 using current lineage_id. Only if the tool returns not_found reply MISSING; a malformed or failed request does not establish absence.",
           { "steps" => [missing], "reply" => "MISSING" }],
          ["search-read", "independent", "First search corpus for charter, limit 1. Then read corpus id charter revision 1 start 0 length 100. Use current lineage_id. After both successful results reply with the beacon color only.",
           { "steps" => [{ "action" => corpus_search, "result" => { "ok" => true, "hits" => [read_step("corpus", "charter", 1, charter)["result"]["source"]] } }, read_step("corpus", "charter", 1, charter)], "reply" => "blue" }],
          ["four-reads", "independent", "Read corpus id long revision 1 using current lineage_id. Perform four reads IN ORDER: start 0 length 1024, start 1024 length 1024, start 2048 length 1024, start 3072 length 1024. Do not skip a read even if the marker is found early. Then reply only with the final marker.",
           { "steps" => [0, 1024, 2048, 3072].map { |offset| read_step("corpus", "long", 1, CORPUS[1]["content"], offset, 1024) }, "reply" => "TEAL-42" }],
          ["omitted-reread", "rollover", "Read corpus id rollover revision 1 using current lineage_id. Perform four reads IN ORDER: start 0 length 1024, start 1024 length 1024, start 2048 length 1024, then start 0 length 1024 AGAIN. The second read of start 0 is required after older context is omitted. Then reply only with the marker in that final read.",
           { "steps" => [0, 1024, 2048, 0].map { |offset| read_step("corpus", "rollover", 1, CORPUS[2]["content"], offset, 1024) }, "reply" => "OPAL-19",
             "omitted_before_step" => { "omitted_step" => 0, "reread_step" => 3 } }]
        ]
        rows.map { |id, group, content, contract| { "id" => id, "group" => group, "content" => content, "contract" => contract } }
      end

      # Seed through the same validated journal transitions, not an unrecorded
      # snapshot edit. These events are explicitly not claims of live inference.
      def self.seed_note(store, id, content)
        action = write_step(id, 0, content)["action"]
        event_id = "fixture-#{id}"
        text = "DETERMINISTIC HARNESS FIXTURE, NOT MODEL OUTPUT: seed #{id}"
        store.synchronize do |state|
          store.append("accepted", { "event_id" => event_id, "content" => text, "content_digest" => Digest::SHA256.hexdigest(text) })
          [action, { "action" => "wait" }].each_with_index do |item, index|
            store.append("model_intent", { "event_id" => event_id, "call_index" => index,
              "context" => ContextBuilder.build(state: state, event_id: event_id, config: store.config) })
            store.append("model_response", { "event_id" => event_id, "call_index" => index, "response" => ContinuityLab.encode(item) })
            if item["action"] == "tool"
              payload = { "event_id" => event_id, "call_index" => index,
                "operation_id" => ContinuityLab.digest({ "event_id" => event_id, "call_index" => index }), "invalid" => false, "tool_attempt" => true }
              store.append("action_result", payload.merge(Actions.tool_result(state, item, store.config, event_id)))
            else
              store.append("terminal", { "event_id" => event_id, "state" => "complete", "reason" => "wait" })
            end
          end
        end
        { "source" => "deterministic_fixture_not_model", "event_id" => event_id, "integrity" => store.integrity }
      end
    end
  end
end
