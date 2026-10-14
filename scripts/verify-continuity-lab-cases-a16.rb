#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a15"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a16"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA16
Prior = Lab::QualificationCasesA15

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
config = Lab::Config.qwen_v6_qualification

tool = ->(name, arguments) { { "action" => "tool", "tool" => name, "arguments" => arguments } }
reply = ->(content) { { "action" => "reply", "content" => content } }
read = lambda do |collection, id, lineage|
  tool.call("read", { "lineage_id" => lineage, "collection" => collection, "id" => id,
    "revision" => 1, "start" => 0, "length" => 1024 })
end
search = lambda do |collection, query, lineage|
  tool.call("search", { "lineage_id" => lineage, "collection" => collection,
    "query" => query, "limit" => 4 })
end
write = ->(id, content) { tool.call("note.write", { "note_id" => id, "expected_revision" => 0, "content" => content }) }

scripts = lambda do |spec, lineage|
  case spec.fetch("id")
  when "t-plan"
    [search.call("corpus", "Nova markers", lineage), reply.call("Nova is the least expensive pack with at least eight markers, at 24 credits.")]
  when "t-change"
    [search.call("corpus", "Orbit markers", lineage),
     write.call("field-kit-choice", "Northstar field kit: two Orbit packs, 20 markers altogether, 50 credits."),
     reply.call("Two Orbit packs provide 20 markers altogether and cost 50 credits.")]
  when "t-callback"
    [read.call("history", "t-change", lineage), reply.call("You switched to two Orbit packs, for a combined cost of 50 credits.")]
  when "t-absent"
    [search.call("corpus", "Northstar warranty", lineage), reply.call("No warranty period is recorded in the available catalog.")]
  else
    raise "missing deterministic script for #{spec.fetch('id')}"
  end
end

backend_for = lambda do |spec|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-a16-prompt", Array.new(100, 17))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    envelope = Lab.parse(input)
    Lab.encode(scripts.call(spec, envelope.fetch("lineage_id")).fetch(call_index))
  end
  backend
end

check.call("planning, holdout and conversation cases and corpora exactly match A15") do
  %w[planning holdout conversation].all? do |batch|
    same_rows = Cases.cases(batch) == Prior.cases(batch)
    same_corpus = Cases.corpus(batch) == Prior.corpus(batch)
    same_evaluation = Cases.cases(batch).all? do |spec|
      arguments = { event: {}, config: {}, spec: spec, before: {}, after: {} }
      Cases.evaluate(**arguments) == Prior.evaluate(**arguments)
    end
    same_rows && same_corpus && same_evaluation
  end
end

Dir.mktmpdir("continuity-a16-cases-") do |root|
  directory = File.join(root, "transfer")
  Dir.mkdir(directory, 0o700)
  path = File.join(directory, "store")
  store = Lab::Store.create(path: path, config: config, corpus: Cases.corpus("transfer"))
  initial = store.snapshot
  outcomes = {}
  Cases.cases("transfer").each do |spec|
    before = store.snapshot
    dependencies = spec.fetch("requires_events").all? { |event_id| outcomes[event_id]&.fetch("score")&.fetch("passed") }
    raise "synthetic dependency missing: #{spec.fetch('id')}" unless dependencies
    receipt = Lab::Runtime.new(store: store, backend: backend_for.call(spec)).submit(
      event_id: spec.fetch("id"), content: spec.fetch("content"))
    after = store.snapshot
    event = after.fetch("events").fetch(spec.fetch("id"))
    score = Cases.evaluate(event: event, config: config, spec: spec, before: before, after: after)
    raise "synthetic trace failed: #{spec.fetch('id')} #{score.inspect}" unless receipt["reason"] == "reply" && score["passed"]
    outcomes[spec.fetch("id")] = { "event" => event, "score" => score, "before" => before, "after" => after }
  end
  store.close
  store = Lab::Store.open(path: path, config: config)
  replayed = store.snapshot

  check.call("four held-out transfer events complete with grounded lookup, changed choice, history callback and unknown handling") do
    replayed.fetch("events").keys.sort == %w[t-absent t-callback t-change t-plan] &&
      outcomes.values.all? { |entry| entry.fetch("score").fetch("passed") && entry.fetch("score").fetch("semantic_review_required") } &&
      outcomes.fetch("t-callback").fetch("score").fetch("sources").any? { |source| source["collection"] == "history" } &&
      outcomes.fetch("t-absent").fetch("score").fetch("sources").any? { |source| source["collection"] == "corpus" }
  end
  check.call("durable choice effect and complete event history survive store replay") do
    store.integrity.fetch("ok") && replayed.fetch("lineage_id") == initial.fetch("lineage_id") &&
      replayed.fetch("events") == outcomes.fetch("t-absent").fetch("after").fetch("events") &&
      replayed.fetch("notes").fetch("field-kit-choice").fetch("content").include?("two Orbit packs")
  end
  check.call("requests omit computed answers, tool names, note instructions and absent catalog facts") do
    specs = Cases.cases("transfer")
    specs.none? do |spec|
      content = spec.fetch("content").downcase
      content.match?(/24 credits|20 markers|50 credits|warranty period is not recorded|note\.write|search\(|read\(/)
    end && !specs.fetch(0).fetch("content").include?("Nova") && !specs.fetch(2).fetch("content").include?("50")
  end

  changed = outcomes.fetch("t-change")
  replayed_effect = copy.call(changed.fetch("event"))
  replayed_effect.fetch("calls").find { |call| Lab.parse(call.fetch("response"))["tool"] == "note.write" }
    .fetch("result")["revision"] = 2
  replayed_effect_score = Cases.evaluate(event: replayed_effect, config: config,
    spec: Cases.cases("transfer").fetch(1), before: changed.fetch("before"), after: changed.fetch("after"))

  callback = outcomes.fetch("t-callback")
  stale = copy.call(callback.fetch("event"))
  stale["reply"] = "You switched to Nova, for 24 credits."
  stale.fetch("calls").last["response"] = Lab.encode(reply.call(stale.fetch("reply")))
  stale_score = Cases.evaluate(event: stale, config: config, spec: Cases.cases("transfer").fetch(2),
    before: callback.fetch("before"), after: callback.fetch("after"))

  plan = outcomes.fetch("t-plan")
  forged = copy.call(plan.fetch("event"))
  forged.fetch("calls").first["result"] = { "ok" => true, "hits" => [], "truncated" => false }
  forged_score = Cases.evaluate(event: forged, config: config, spec: Cases.cases("transfer").first,
    before: plan.fetch("before"), after: plan.fetch("after"))
  check.call("mechanical screening rejects stale callback, fabricated support and replayed effects") do
    replayed_effect_score.fetch("reasons").include?("tool_result_replay_mismatch") &&
      stale_score.fetch("reasons").include?("missing_expected_fact_tokens") &&
      forged_score.fetch("reasons").include?("tool_result_replay_mismatch")
  end

  absent = outcomes.fetch("t-absent")
  fabricated_absence = copy.call(absent.fetch("event"))
  fabricated_absence["reply"] = "The supplier promises a three year warranty."
  fabricated_absence.fetch("calls").last["response"] = Lab.encode(reply.call(fabricated_absence.fetch("reply")))
  absent_score = Cases.evaluate(event: fabricated_absence, config: config, spec: Cases.cases("transfer").fetch(3),
    before: absent.fetch("before"), after: absent.fetch("after"))
  check.call("fabricated warranty answer fails the frozen unknown response heuristic") do
    absent_score.fetch("reasons").include?("missing_expected_fact_tokens")
  end
  store.close
end

puts "PASS: #{checks} A16 deterministic held-out fixture checks; synthetic traces only, no live inference"
