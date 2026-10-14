#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a12"
Lab = SoulCore::ContinuityLab
checks = 0
check = ->(label, value) { checks += 1; raise label unless value; puts "PASS: #{label}" }
specs = Lab::QualificationCasesA12.cases
check.call("two visible cases only", specs.length == 2 && specs.all? { |s| s["condition"] == "visible" })
check.call("corpus unchanged", Lab::QualificationCasesA12::CORPUS == Lab::QualificationCasesA8::CORPUS)
specs.each do |spec|
  prior = Lab::QualificationCasesA8.cases.find { |s| s["id"] == spec["id"] }
  check.call("same actions/scoring #{spec["id"]}", spec["contract"] == prior["contract"])
  check.call("output specification without answer #{spec["id"]}",
    spec["content"].start_with?(prior["content"]) && !spec["content"].include?(spec.dig("contract", "reply")) &&
    spec["content"].include?("uppercase letters, a hyphen and digits"))
  state = Lab::QualificationCasesA12.expected_state(spec, "a" * 32, 4)
  check.call("expected prefix uses revised request and no terminal #{spec["id"]}",
    state.dig("events", "comparison", "content") == spec["content"] &&
    state.dig("events", "comparison", "calls").length == 4)
  calls = state.dig("events", "comparison", "calls")
  calls << { "response" => Lab.encode({ "action" => "reply", "content" => spec.dig("contract", "reply") }) }
  event = { "state" => "complete", "reason" => "reply", "reply" => spec.dig("contract", "reply"), "calls" => calls }
  score = ->(e) { Lab::QualificationScorer.evaluate(event: e, config: Lab::Config.qwen_v5_qualification,
    lineage_id: "a" * 32, contract: spec["contract"], before_notes: {}, after_notes: {}) }
  check.call("exact identifier passes #{spec["id"]}", score.call(event)["passed"])
  check.call("label/punctuation/omitted/extra read still fail #{spec["id"]}",
    ["Marker " + event["reply"], event["reply"] + "."].none? { |text| score.call(event.merge("reply" => text))["passed"] } &&
    !score.call(event.merge("calls" => calls.drop(1)))["passed"] &&
    !score.call(event.merge("calls" => [calls.first] + calls))["passed"])
end
puts "#{checks}/#{checks} checks passed"
