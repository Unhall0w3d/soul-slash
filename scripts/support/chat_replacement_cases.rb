# frozen_string_literal: true

require "json"

module SoulCore
  module ChatReplacementCases
    CASE_DATA = [
      {
        "id" => "plain-computation-sum", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "A sealed box contains 17 blue tiles and 26 amber tiles. How many tiles are there in total?" }],
        "expected" => { "answer" => "43 tiles", "rubric" => "State the sum of 17 and 26 as a total of 43 tiles." }
      },
      {
        "id" => "plain-evidence-rate", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "A fictional pump moved 84 litres in 7 minutes at a steady rate. What was its rate in litres per minute?" }],
        "expected" => { "answer" => "12 litres per minute", "rubric" => "Divide 84 litres by 7 minutes and state the rate with units." }
      },
      {
        "id" => "plain-missing-date", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "These fictional notes say a lamp was inspected and accepted. What date was it inspected?" }],
        "expected" => { "answer" => "Inspection date is not stated", "rubric" => "Do not invent an inspection date; say the supplied notes omit it." }
      },
      {
        "id" => "plain-unknown-owner", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "The supplied fictional record lists a parcel as delivered but gives no recipient. Who received it?" }],
        "expected" => { "answer" => "Recipient is not identified", "rubric" => "Do not infer a recipient from delivery status; say the record does not name one." }
      },
      {
        "id" => "plain-conversation-tone", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "I finally got the tiny balcony garden started. Say something conversational, then suggest one easy next step." }],
        "expected" => { "rubric" => "Respond conversationally to the user's gardening news and suggest one easy next step." }
      },
      {
        "id" => "plain-planning-no-execution", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "Help me plan a 20-minute desk reset. Give me a short sequence I can do myself; do not take any actions." }],
        "expected" => { "rubric" => "Give a short, usable 20-minute sequence for the user to perform; report no action taken." }
      },
      {
        "id" => "json-required-object", "kind" => "json",
        "messages" => [{ "role" => "user", "content" => "Return JSON with exactly label and count. label is 'oranges'; count is 3." }],
        "response_format" => { "type" => "json_schema", "json_schema" => { "name" => "label_count", "strict" => true,
          "schema" => { "type" => "object", "properties" => { "label" => { "type" => "string" }, "count" => { "type" => "integer" } }, "required" => %w[label count], "additionalProperties" => false } } },
        "expected" => { "label" => "oranges", "count" => 3 }
      },
      {
        "id" => "json-array", "kind" => "json",
        "messages" => [{ "role" => "user", "content" => "Return only a JSON array of the three fictional station names in this order: Alder, Brine, Cinder." }],
        "response_format" => { "type" => "json_schema", "json_schema" => { "name" => "station_names", "strict" => true,
          "schema" => { "type" => "array", "items" => { "type" => "string" } } } },
        "expected" => %w[Alder Brine Cinder]
      },
      {
        "id" => "json-unicode-escaped", "kind" => "json",
        "messages" => [{ "role" => "user", "content" => "Return JSON with exactly the string field text whose decoded value is the snowman character ☃." }],
        "response_format" => { "type" => "json_schema", "json_schema" => { "name" => "unicode_text", "strict" => true,
          "schema" => { "type" => "object", "properties" => { "text" => { "type" => "string" } }, "required" => ["text"], "additionalProperties" => false } } },
        "expected" => { "text" => "☃" }
      },
      {
        "id" => "json-evidence-null", "kind" => "json",
        "messages" => [{ "role" => "user", "content" => "Extract the fictional record's batch_id, quantity, and inspection_date. Use null for any field the record does not state. Record: batch_id=BX-204; quantity=18 units; inspection date not recorded." }],
        "response_format" => { "type" => "json_schema", "json_schema" => { "name" => "record_extract", "strict" => true,
          "schema" => { "type" => "object", "properties" => { "batch_id" => { "type" => "string" }, "quantity" => { "type" => "integer" }, "inspection_date" => { "type" => ["string", "null"] } }, "required" => %w[batch_id quantity inspection_date], "additionalProperties" => false } } },
        "expected" => { "batch_id" => "BX-204", "quantity" => 18, "inspection_date" => nil }
      },
      {
        "id" => "tool-read-one-record", "kind" => "tool_round_trip",
        "messages" => [{ "role" => "user", "content" => "Using the fictional records supplied to the read tool, look up only record R-17 and report its status." }],
        "tools" => [
          { "type" => "function", "function" => { "name" => "read_record", "description" => "Read one record from the supplied synthetic records only; perform no host or external action.",
            "parameters" => { "type" => "object", "properties" => { "record_id" => { "type" => "string" } }, "required" => ["record_id"], "additionalProperties" => false } } },
          { "type" => "function", "function" => { "name" => "read_card", "description" => "Read one card from the supplied synthetic records only; perform no host or external action.",
            "parameters" => { "type" => "object", "properties" => { "card_id" => { "type" => "string" } }, "required" => ["card_id"], "additionalProperties" => false } } }
        ],
        "tool_choice" => "required", "tool_result" => { "record_id" => "R-17", "status" => "packed" },
        "expected" => { "tool_name" => "read_record", "arguments" => { "record_id" => "R-17" }, "rubric" => "Report that fictional record R-17 has status packed." }
      },
      {
        "id" => "tool-read-requested-summary", "kind" => "tool_round_trip",
        "messages" => [{ "role" => "user", "content" => "Read the synthetic card for unit U-6 and report its zone using the read tool." }],
        "tools" => [
          { "type" => "function", "function" => { "name" => "read_record", "description" => "Read one record from the supplied synthetic records only; do not access any real system.",
            "parameters" => { "type" => "object", "properties" => { "record_id" => { "type" => "string" } }, "required" => ["record_id"], "additionalProperties" => false } } },
          { "type" => "function", "function" => { "name" => "read_card", "description" => "Read a single card from the supplied synthetic records only; do not access any real system.",
            "parameters" => { "type" => "object", "properties" => { "unit" => { "type" => "string" } }, "required" => ["unit"], "additionalProperties" => false } } }
        ],
        "tool_choice" => "required", "tool_result" => { "unit" => "U-6", "zone" => "west" },
        "expected" => { "tool_name" => "read_card", "arguments" => { "unit" => "U-6" }, "rubric" => "Report that synthetic unit U-6 is in the west zone." }
      }
    ].freeze

    CONTINUITY_TURNS = [
      { "user" => "Project notes: codename Maple Kite; workstreams archive and dashboard; review day Tuesday. For this fictional project, what is the codename?", "expected" => { "codename" => "Maple Kite" } },
      { "user" => "Which two workstreams are listed?", "expected" => { "workstreams" => ["archive", "dashboard"] } },
      { "user" => "What is the original review day?", "expected" => { "review_day" => "Tuesday" } },
      { "user" => "Update the project: codename is now Cedar Lantern, workstreams are archive and search, and review day is Thursday. Confirm the changes.", "expected" => { "codename" => "Cedar Lantern", "workstreams" => ["archive", "search"], "review_day" => "Thursday" } },
      { "user" => "What is the current codename?", "expected" => { "codename" => "Cedar Lantern" } },
      { "user" => "Which workstreams are current?", "expected" => { "workstreams" => ["archive", "search"] } },
      { "user" => "Which day is the current review?", "expected" => { "review_day" => "Thursday" } },
      { "user" => "State the current codename, workstreams, and review day.", "expected" => { "codename" => "Cedar Lantern", "workstreams" => ["archive", "search"], "review_day" => "Thursday" } }
    ].freeze

    STRENGTH_CASES = [
      {
        "id" => "strength-technical-cache", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "Explain this fictional caching design in clear, practical language, using only these facts: a configuration value is cached for 15 seconds; a cache miss reads it from the settings store; a changed setting may not appear in a reader's cache until that cache expires. Describe the benefit and the tradeoff without claiming measured speedups. Keep the explanation under 180 words." }],
        "expected" => { "rubric" => "Explain fewer repeated store reads as the benefit and up to the cache lifetime of stale configuration as the tradeoff; do not invent benchmark results or other system behavior." }
      },
      {
        "id" => "strength-timeline-causality", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "Help interpret this fictional service timeline: version 2 started at 09:00; timeout reports rose at 09:04; an upstream queue alert appeared at 09:08; rollback began at 09:10; reported timeouts eased at 09:12. What can we reasonably infer, and what remains unknown? Keep the analysis under 180 words." }],
        "expected" => { "rubric" => "Summarize the temporal order, distinguish observed correlation from demonstrated cause, and name plausible unknowns without asserting that version 2, the queue, or rollback caused the changes." }
      },
      {
        "id" => "strength-constrained-plan", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "Make a practical plan to prepare a local demo in 40 minutes. Constraints: first save a copy of the current demo settings (10 minutes); only then edit the demo configuration (15 minutes); only after editing, run a local check (10 minutes); leave 5 minutes to review notes. I will do the work; do not execute anything. Give a short sequence with timing and dependencies, under 180 words." }],
        "expected" => { "rubric" => "Give the four requested steps with the stated durations totaling 40 minutes, preserve the save-before-edit-before-check dependencies, and make clear this is a plan for the user rather than completed work." }
      },
      {
        "id" => "strength-status-rewrite", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "Rewrite this rough fictional status note so it is clear and professional, preserving every fact and uncertainty: 'draft is done. screenshots still missing. owner hasnt said whether review is needed. maybe publish next week if approved.' Do not imply approval. Keep it under 180 words." }],
        "expected" => { "rubric" => "Produce a concise polished status note retaining that the draft is done, screenshots are missing, review need is unconfirmed, and next-week publication is only possible if approved." }
      },
      {
        "id" => "strength-creative-options", "kind" => "plain",
        "messages" => [{ "role" => "user", "content" => "Help me brainstorm two distinct, feasible balcony herb-garden ideas. The usable area is 2 by 3 feet, it gets about four hours of morning sun, my budget is $30, and I cannot drill into anything. Keep both ideas within those constraints and under 180 words." }],
        "expected" => { "rubric" => "Offer two meaningfully different, feasible ideas suited to the small area and morning sun, each within the $30 budget and using freestanding or existing supports without drilling." }
      },
      {
        "id" => "strength-correction-conversation", "kind" => "plain",
        "messages" => [
          { "role" => "user", "content" => "We need a calm opening for a short community garden update. I want it warm and concise." },
          { "role" => "assistant", "content" => "Here is a six-step content strategy checklist for planning the update." },
          { "role" => "user", "content" => "I'm not asking for a checklist. Please draft one warm, concise opening sentence." }
        ],
        "expected" => { "rubric" => "Respond to the corrected request with one warm, concise opening sentence for the update; do not continue the checklist or explain the correction." }
      }
    ].freeze

    def self.deep_freeze(value)
      case value
      when Hash
        value.each { |key, entry| deep_freeze(key); deep_freeze(entry) }
      when Array
        value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end
    private_class_method :deep_freeze

    deep_freeze(CASE_DATA)
    deep_freeze(CONTINUITY_TURNS)
    deep_freeze(STRENGTH_CASES)

    def self.cases
      CASE_DATA
    end

    def self.continuity_turns
      CONTINUITY_TURNS
    end

    def self.strength_cases
      STRENGTH_CASES
    end

    # Exact JSON equality and exact synthetic tool routing are machine scored.
    # Natural language tone and planning remain for parent-side inspection.
    def self.score(case_hash, content:, tool_calls: [])
      expected = case_hash.fetch("expected")
      case case_hash.fetch("kind")
      when "plain"
        { "pass" => nil, "details" => { "parent_inspection_required" => true, "expected" => expected } }
      when "json"
        begin
          parsed = JSON.parse(content)
          exact = json_exact?(parsed, expected)
          { "pass" => exact, "details" => exact ? "parsed JSON exactly matches expected value" : "parsed JSON differs from expected value" }
        rescue JSON::ParserError, TypeError
          { "pass" => false, "details" => "content is not directly parseable JSON" }
        end
      when "tool_round_trip"
        expected_call = { "name" => expected.fetch("tool_name"), "arguments" => expected.fetch("arguments") }
        calls = Array(tool_calls)
        call_ok = calls.length == 1 && calls.first == expected_call
        { "pass" => call_ok ? nil : false,
          "details" => { "tool_call_exact" => call_ok, "tool_result" => case_hash.fetch("tool_result"),
            "final_response_rubric" => expected.fetch("rubric"), "parent_inspection_required" => call_ok } }
      else
        { "pass" => false, "details" => "unknown case kind" }
      end
    end

    def self.json_exact?(actual, expected)
      return false unless actual.class == expected.class
      case expected
      when Hash
        actual.keys.sort == expected.keys.sort && expected.all? { |key, value| json_exact?(actual.fetch(key), value) }
      when Array
        actual.length == expected.length && expected.each_index.all? { |index| json_exact?(actual[index], expected[index]) }
      else
        actual == expected
      end
    end
    private_class_method :json_exact?
  end
end
