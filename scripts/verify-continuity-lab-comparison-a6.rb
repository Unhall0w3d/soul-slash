#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/continuity_lab/qualification_cases_a6"
require_relative "../lib/soul_core/continuity_lab/token_context"

Lab = SoulCore::ContinuityLab
Catalog = Lab::QualificationCasesA6
checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
lineage = "a" * 32
cases = Catalog.cases
check.call("exact bounded four-case counterbalanced design") do
  cases.map { |s| [s["pair"], s["condition"]] } == [["four-reads", "visible"], ["reread", "rollover"], ["four-reads", "rollover"], ["reread", "visible"]]
end
cases.group_by { |s| s["pair"] }.each do |pair, arms|
  check.call("#{pair}: same request and strict contract in both arms") { arms[0]["content"] == arms[1]["content"] && arms[0]["contract"] == arms[1]["contract"] }
  check.call("#{pair}: only context_tokens differs in existing configurations") do
    left, right = arms.map { |s| Catalog.config(s).to_h }
    left.reject { |k, _| k == "context_tokens" } == right.reject { |k, _| k == "context_tokens" } &&
      arms.map { |s| Lab::TokenContext.budget(Catalog.config(s)) }.sort == [2048, 3072]
  end
end
check.call("sources have exact complete 768-character spans and final marker placement") do
  Catalog::CORPUS[0]["content"].length == 3072 && Catalog::CORPUS[0]["content"][2304, 768].end_with?("TEAL-42.") &&
    !Catalog::CORPUS[0]["content"][0, 2304].include?("TEAL-42") && Catalog::CORPUS[1]["content"].length == 2304
end
cases.each do |spec|
  config = Catalog.config(spec)
  expected = Catalog.expected_state(spec, lineage, 4)
  calls = expected.dig("events", "comparison", "calls")
  calls << { "response" => Lab.encode({ "action" => "reply", "content" => spec.dig("contract", "reply") }) }
  calls.each_with_index do |call, index|
    included = (0...index).to_a
    boundary = spec["pair"] == "reread" ? 3 : 4
    omitted = spec["condition"] == "rollover" && index >= boundary ? [included.shift] : []
    call["context"] = { "manifest" => { "input_tokens" => 1500, "included_groups" => included,
      "omitted_groups" => omitted.map { |id| { "call_index" => id } } } }
  end
  event = { "state" => "complete", "reason" => "reply", "reply" => spec.dig("contract", "reply"), "calls" => calls }
  score = ->(e) { Lab::QualificationScorer.evaluate(event: e, config: config, lineage_id: lineage, contract: spec["contract"], before_notes: {}, after_notes: {}) }
  check.call("#{spec['id']}: exact sequence and final reply pass") { score.call(event)["passed"] }
  check.call("#{spec['id']}: expected condition measured separately") { Catalog.condition_evidence(event, spec)["intended_condition_observed"] }
  check.call("#{spec['id']}: wrong answer, skipped, reordered and repeated successes fail") do
    wrong = copy.call(event); wrong["reply"] = "wrong"
    skipped = copy.call(event); skipped["calls"].delete_at(1)
    reordered = copy.call(event); reordered["calls"][0], reordered["calls"][1] = reordered["calls"].values_at(1, 0)
    repeated = copy.call(event); repeated["calls"].insert(4, copy.call(calls[0]))
    [wrong, skipped, reordered, repeated].none? { |e| score.call(e)["passed"] }
  end
  check.call("#{spec['id']}: altered retrieved content fails") do
    wrong = copy.call(event); wrong["calls"][0]["result"]["source"]["text"] = "invented"
    !score.call(wrong)["passed"]
  end
  check.call("#{spec['id']}: absent manifest cannot establish contrast") do
    wrong = copy.call(event); wrong["calls"].each { |c| c.delete("context") }
    !Catalog.condition_evidence(wrong, spec)["intended_condition_observed"]
  end
  check.call("#{spec['id']}: early exit cannot establish planned decision boundary") do
    early = copy.call(event); early["calls"] = early["calls"].first(2)
    !Catalog.condition_evidence(early, spec)["intended_condition_observed"]
  end
  check.call("#{spec['id']}: budget failure stays failed despite correct conditions") do
    failed = copy.call(event); failed.merge!("state" => "failed", "reason" => "model_call_budget"); failed.delete("reply")
    !score.call(failed)["passed"] && Catalog.condition_evidence(failed, spec)["intended_condition_observed"]
  end
  check.call("#{spec['id']}: expected prefix has no reply, note or answer injection") do
    (0..4).all? do |index|
      state = Catalog.expected_state(spec, lineage, index)
      envelope = Lab.parse(Lab::TokenContext.initial(state: state, event_id: "comparison", config: config))
      envelope["tool_groups"].length == index && !envelope["user"]["content"].include?(spec.dig("contract", "reply")) &&
        envelope["tool_groups"].all? { |g| Lab.parse(g["model_output"])["tool"] == "read" }
    end
  end
end
visible = cases.find { |s| s["condition"] == "visible" }
check.call("empty history never counts as a successful visible comparison") { !Catalog.condition_evidence({ "calls" => [] }, visible)["intended_condition_observed"] }
puts "PASS: #{checks} A6 deterministic comparison checks; no live inference"
