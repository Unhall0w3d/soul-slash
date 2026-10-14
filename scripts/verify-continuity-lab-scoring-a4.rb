#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/continuity_lab/qualification_scorer"
require_relative "../lib/soul_core/continuity_lab/config"

Scorer = SoulCore::ContinuityLab::QualificationScorer
LINEAGE = "a" * 32
CONFIG = SoulCore::ContinuityLab::Config.new("context_mode" => "explicit_v1")

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  puts "- #{label}: #{condition ? 'ok' : 'FAIL'}"
  failures << label unless condition
end

action = lambda do |tool, arguments|
  { "action" => "tool", "tool" => tool, "arguments" => arguments }
end
call = lambda do |parsed_action, result, context = nil|
  entry = { "response" => JSON.generate(parsed_action), "result" => result }
  entry["context"] = context if context
  entry
end
event = lambda do |calls, state: "complete", reason: "reply", reply: "done"|
  { "event_id" => "scoring-fixture", "state" => state, "reason" => reason,
    "reply" => reply, "calls" => calls }
end
score = lambda do |record, contract, before = {}, after = {}|
  Scorer.evaluate(event: record, config: CONFIG, lineage_id: LINEAGE, contract:, before_notes: before, after_notes: after)
end

write_action = action.call("note.write", { "note_id" => "memo", "expected_revision" => 0, "content" => "first" })
write_result = { "ok" => true, "note_id" => "memo", "revision" => 1 }
read_action = action.call("read", { "lineage_id" => "$lineage", "collection" => "notes", "id" => "memo", "revision" => 1, "start" => 0, "length" => 5 })
source = { "lineage_id" => LINEAGE, "collection" => "notes", "id" => "memo", "revision" => 1,
           "content_digest" => "b" * 64, "span" => [0, 5], "text" => "first" }
read_result = { "ok" => true, "source" => source }
delete_action = action.call("note.tombstone", { "note_id" => "memo", "expected_revision" => 1 })
delete_result = { "ok" => true, "note_id" => "memo", "revision" => 2 }
search_action = action.call("search", { "lineage_id" => "$lineage", "collection" => "notes", "query" => "first", "limit" => 8 })
search_result = { "ok" => true, "hits" => [] }
steps = [
  { "action" => write_action, "result" => { "ok" => true, "note_id" => "memo", "revision" => 1 } },
  { "action" => read_action, "result" => { "ok" => true, "source" => { "id" => "memo", "revision" => 1, "span" => [0, 5] } } },
  { "action" => delete_action, "result" => { "ok" => true, "revision" => 2 } },
  { "action" => search_action, "result" => { "ok" => true, "hits" => [] } }
]
positive = event.call([
  call.call(write_action, write_result), call.call(read_action.merge("arguments" => read_action.dig("arguments").merge("lineage_id" => LINEAGE)), read_result),
  call.call(delete_action, delete_result), call.call(search_action.merge("arguments" => search_action.dig("arguments").merge("lineage_id" => LINEAGE)), search_result)
])
single_read_contract = { "steps" => [{ "action" => read_action, "result" => { "ok" => true, "source" => { "id" => "memo" } } }] }
single_read_event = event.call([call.call(read_action.merge("arguments" => read_action["arguments"].merge("lineage_id" => LINEAGE)), read_result)])
check.call("lineage placeholder resolves to the supplied lineage", score.call(single_read_event, single_read_contract)["passed"])
contract = { "steps" => steps, "requires_notes" => { "seed" => { "content" => "ready" } },
             "final_notes" => { "memo" => { "revision" => 2, "tombstone" => true } },
             "reply" => "done" }
result = score.call(positive, contract, { "seed" => { "content" => "ready", "extra" => true } },
                    { "memo" => { "revision" => 2, "tombstone" => true, "provenance" => "unverified" } })
check.call("positive exact write/read/tombstone/search evidence passes in order", result["passed"] && result["matched_call_indices"] == [0, 1, 2, 3])

missing_prerequisite = score.call(positive, contract, {}, { "memo" => { "revision" => 2, "tombstone" => true } })
check.call("missing before-note prerequisite is distinguished", missing_prerequisite["status"] == "unmet_prerequisite" && !missing_prerequisite["passed"])

wrong_lineage_event = event.call([call.call(read_action.merge("arguments" => read_action["arguments"].merge("lineage_id" => "c" * 32)), read_result)])
check.call("wrong lineage fails after literal resolution", !score.call(wrong_lineage_event, single_read_contract)["passed"])
wrong_revision_steps = [{ "action" => read_action.merge("arguments" => read_action["arguments"].merge("revision" => 2)), "result" => { "ok" => true } }]
check.call("wrong revision and wrong span results fail", !score.call(positive, { "steps" => wrong_revision_steps })["passed"] &&
  !score.call(positive, { "steps" => [{ "action" => read_action, "result" => { "ok" => true, "source" => { "span" => [1, 5] } } }] })["passed"])
wrong_id = read_action.merge("arguments" => read_action["arguments"].merge("id" => "other"))
out_of_order = event.call([call.call(read_action.merge("arguments" => read_action["arguments"].merge("lineage_id" => LINEAGE)), read_result),
                           call.call(write_action, write_result)])
check.call("wrong target ID and out-of-order successful calls fail", !score.call(positive, { "steps" => [{ "action" => wrong_id, "result" => { "ok" => true } }] })["passed"] &&
  !score.call(out_of_order, { "steps" => [steps[0], steps[1]] })["passed"])

negative_action = action.call("read", { "lineage_id" => "$lineage", "collection" => "notes", "id" => "missing", "revision" => 1, "start" => 0, "length" => 5 })
negative_result = { "ok" => false, "reason" => "not_found" }
negative_record = event.call([call.call(negative_action.merge("arguments" => negative_action["arguments"].merge("lineage_id" => LINEAGE)), negative_result)])
check.call("expected negative result matches exact action and result", score.call(negative_record, {
  "steps" => [{ "action" => negative_action, "result" => negative_result }]
})["passed"])
check.call("wrong expected negative result fails", !score.call(negative_record, {
  "steps" => [{ "action" => negative_action, "result" => { "ok" => false, "reason" => "revision_conflict" } }]
})["passed"])
check.call("empty expected result cannot assert success or failure", !score.call(negative_record, {
  "steps" => [{ "action" => negative_action, "result" => {} }]
})["passed"])

duplicate_json = '{"action":"tool","action":"wait","tool":"note.write","arguments":{"note_id":"memo","expected_revision":0,"content":"first"}}'
duplicate_record = event.call([{ "response" => duplicate_json, "result" => write_result }])
check.call("duplicate-key JSON cannot satisfy an expected successful tool step", !score.call(duplicate_record, {
  "steps" => [steps[0]]
})["passed"])

substring = event.call([], reply: "The answer is not done, actually.")
check.call("reply substring cannot satisfy an exact reply contract", !score.call(substring, { "reply" => "done" })["passed"])
unexpected_write = event.call([call.call(write_action, write_result)])
check.call("unexpected successful write is rejected with no expected steps", !score.call(unexpected_write, {})["passed"])
check.call("missing terminal and blocked terminal cannot pass", score.call({ "calls" => [] }, {})["status"] == "unmet_prerequisite" &&
  score.call(event.call([], state: "blocked_for_human_review", reason: "unresolved_model_intent"), {})["status"] == "unmet_prerequisite")

read_only_step = [{ "action" => read_action, "result" => { "ok" => true, "source" => { "id" => "memo" } } }]
original_call = call.call(read_action.merge("arguments" => read_action["arguments"].merge("lineage_id" => LINEAGE)), read_result)
reread_context = { "manifest" => { "omitted_groups" => [{ "call_index" => 0 }], "included_groups" => [1] } }
reread_call = call.call(read_action.merge("arguments" => read_action["arguments"].merge("lineage_id" => LINEAGE)), read_result, reread_context)
omission_record = event.call([original_call, reread_call])
omission_contract = { "steps" => [read_only_step[0], read_only_step[0]], "omitted_before_step" => { "omitted_step" => 0, "reread_step" => 1 } }
check.call("omitted result followed by same successful source reread is qualified", score.call(omission_record, omission_contract)["passed"])
present_context = { "manifest" => { "omitted_groups" => [], "included_groups" => [0, 1] } }
present_record = event.call([original_call, call.call(reread_call["response"], read_result, present_context)])
wrong_call_context = { "manifest" => { "omitted_groups" => [{ "call_index" => 9 }], "included_groups" => [1] } }
wrong_context_record = event.call([original_call, call.call(reread_call["response"], read_result, wrong_call_context)])
wrong_action_record = event.call([original_call, call.call(JSON.generate(read_action.merge("arguments" => read_action["arguments"].merge("lineage_id" => LINEAGE, "start" => 1))), read_result, reread_context)])
missing_identity = source.reject { |key, _| key == "content_digest" }
partial_read_result = { "ok" => true, "source" => missing_identity }
partial_identity_record = event.call([
  call.call(original_call["response"], partial_read_result),
  call.call(reread_call["response"], partial_read_result, reread_context)
])
check.call("omission requires absent inclusion, correct omitted call index and same reread action", !score.call(present_record, omission_contract)["passed"] &&
  !score.call(wrong_context_record, omission_contract)["passed"] && !score.call(wrong_action_record, omission_contract)["passed"] &&
  !score.call(omission_record, { "steps" => omission_contract["steps"], "omitted_before_step" => { "omitted_step" => 1, "reread_step" => 0 } })["passed"] &&
  !score.call(partial_identity_record, omission_contract)["passed"])

failed_attempt = call.call({ "action" => "tool", "tool" => "read", "arguments" => {} }, { "ok" => false, "reason" => "invalid" })
failure_report = score.call(event.call([failed_attempt]), {})
check.call("failed or malformed attempts are counted without becoming successful evidence", failure_report["passed"] && failure_report["reasons"].include?("failed_or_malformed_attempts=1"))
reply_record = event.call([{ "response" => JSON.generate("action" => "reply", "content" => "done"), "result" => nil }])
check.call("ordinary recorded reply and wait calls are excluded from failed-attempt counts", score.call(reply_record, {})["reasons"].empty?)

mutable = [positive, contract, { "memo" => { "revision" => 2, "tombstone" => true } }, steps]
before = Marshal.dump(mutable)
score.call(mutable[0], mutable[1], {}, mutable[2])
score.call(mutable[0], { "steps" => mutable[3] }, {}, mutable[2])
check.call("evaluation leaves event and contracts untouched", Marshal.dump(mutable) == before)

puts "Continuity Lab A4 scoring verification: #{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
