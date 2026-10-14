#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/continuity_lab/qualification_cases_a8"
require_relative "../lib/soul_core/continuity_lab/token_context"

Lab = SoulCore::ContinuityLab
Catalog = Lab::QualificationCasesA8
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

check.call("A7 requests, case ordering, actions and final markers are unchanged") do
  old = Lab::QualificationCasesA6.cases
  cases.zip(old).all? do |current, original|
    current.reject { |k, _| k == "contract" } == original.reject { |k, _| k == "contract" } &&
      current["contract"]["reply"] == original["contract"]["reply"] &&
      current["contract"]["steps"].map { |s| s["action"] } == original["contract"]["steps"].map { |s| s["action"] }
  end
end
repeated_run = /([^\s])\1{7}/
check.call("repeated-letter detector catches filler without rejecting varied prose") do
  repeated_run.match?("xxxxxxxx") && !repeated_run.match?(Catalog::PASSAGES.join)
end
check.call("new corpus contains varied meaningful sentences, not repeated-letter filler") do
  Catalog::PASSAGES.length == 7 && Catalog::PASSAGES.uniq.length == 7 &&
    Catalog::PASSAGES.all? { |p| p.split.length >= 100 && !repeated_run.match?(p) } &&
    Lab.digest(Catalog::CORPUS) != Lab.digest(Lab::QualificationCasesA6::CORPUS)
end
check.call("bounded alignment padding never replaces passage content") do
  Catalog::CORPUS.all? do |source|
    source["content"].scan(/.{768}/m).all? { |span| span.length == 768 && (span.scan(/ +/).map(&:length).max || 0) <= 80 }
  end
end
check.call("markers occur once, in their original target spans only") do
  long, reread = Catalog::CORPUS.map { |d| d["content"] }
  long.scan("TEAL-42").length == 1 && long[2304, 768].include?("TEAL-42") &&
    reread.scan("OPAL-19").length == 1 && reread[0, 768].include?("OPAL-19") &&
    !long.include?("OPAL-19") && !reread.include?("TEAL-42")
end
check.call("every expected source result belongs to the new corpus and digest") do
  cases.all? do |spec|
    state = Catalog.expected_state(spec, lineage, 4)
    state["corpus_digest"] == Lab.digest(Catalog::CORPUS) &&
      state["events"]["comparison"]["calls"].all? do |call|
        source = call["result"]["source"]
        doc = Catalog::CORPUS.find { |d| d["id"] == source["id"] }["content"]
        source["text"] == doc[source["span"][0]...source["span"][1]] &&
          source["content_digest"] == Digest::SHA256.hexdigest(doc)
      end
  end
end
check.call("A7 execution configurations remain identical per condition") do
  cases.all? { |spec| Catalog.config(spec).to_h == Lab::Config.qwen_v5_qualification(rollover: spec["condition"] == "rollover").to_h }
end
cases.each do |spec|
  check.call("#{spec['id']}: 64-token sizing margin passes, 63 fails") do
    visible = spec["condition"] == "visible"
    budget = Lab::TokenContext.budget(Catalog.config(spec))
    boundary = spec["pair"] == "reread" ? 3 : 4
    rows = (0..4).map do |i|
      { "call_index" => i, "input_tokens" => budget - 64, "full_input_tokens" => budget + 64,
        "included_groups" => visible || i < boundary ? (0...i).to_a : (1...i).to_a }
    end
    good = Catalog.calibration_evidence(spec, rows)
    near = copy.call(rows)
    visible ? near.last["input_tokens"] += 1 : near[boundary]["full_input_tokens"] -= 1
    wrong = copy.call(rows)
    wrong[boundary]["included_groups"] = visible ? [1, 2] : (0...boundary).to_a
    good["valid"] && good["boundary_margin_tokens"] == 64 &&
      !Catalog.calibration_evidence(spec, near)["valid"] && !Catalog.calibration_evidence(spec, wrong)["valid"]
  end
end
check.call("incomplete sizing trace cannot authorize generation") do
  begin
    Catalog.calibration_evidence(cases.first, [])
    false
  rescue Lab::ValidationError
    true
  end
end
check.call("rollover permits multiple oldest omissions, never empty, reordered or gapped retention") do
  spec = cases.find { |s| s["id"] == "four-reads-rollover" }
  rows = (0..4).map { |i| { "call_index" => i, "input_tokens" => 1600, "full_input_tokens" => 2200, "included_groups" => (0...i).to_a } }
  rows[4]["included_groups"] = [2, 3]
  good = Catalog.calibration_evidence(spec, rows)["valid"]
  bad = [[], [1, 3], [3, 2], [2], [4], ["2", 3]].all? do |retained|
    probe = copy.call(rows)
    probe[4]["included_groups"] = retained
    !Catalog.calibration_evidence(spec, probe)["valid"]
  end
  good && bad
end
puts "PASS: #{checks} A8 deterministic comparison checks; no live inference"
