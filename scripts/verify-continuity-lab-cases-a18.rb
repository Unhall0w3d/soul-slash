#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a18"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA18

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }

unless Lab::Config.respond_to?(:qwen_v9_qualification) && Lab::Config.respond_to?(:qwen_v8_qualification)
  abort "A18 Config factories are not available yet; rerun after the primary A18 context/config slice lands"
end
config = Lab::Config.qwen_v9_qualification

# Independent fixture oracle, intentionally maintained separately from the
# evidence corpus and case answer key.
PLAN_MINIMUM_SEALS = 15
PLAN_CATALOG = [
  { "crate" => "Ash", "seals" => 5, "price" => 16 },
  { "crate" => "Maple", "seals" => 14, "price" => 33 },
  { "crate" => "Cedar", "seals" => 13, "price" => 37 },
  { "crate" => "Birch", "seals" => 17, "price" => 43 }
].freeze
plan_winner = PLAN_CATALOG.select { |row| row.fetch("seals") >= PLAN_MINIMUM_SEALS }.min_by { |row| row.fetch("price") }
raise "independent plan catalog has no eligible crate" unless plan_winner
plan_reply = "#{plan_winner.fetch('crate')} is the least expensive qualifying crate; it has #{plan_winner.fetch('seals')} seals and costs #{plan_winner.fetch('price')} credits."

reply = ->(content) { { "action" => "reply", "content" => content } }
responses = {
  "a18-plan" => plan_reply,
  "a18-change" => "Four Maple crates provide 56 seals altogether and cost 132 credits.",
  "a18-callback" => "We switched to four Maple crates, for a combined cost of 132 credits.",
  "a18-absent" => "Warranty information is not provided in the parts sheet."
}

backend_for = lambda do |spec|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-a18-prompt", Array.new(100, 18))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    raise "unexpected extra call" unless call_index.zero?
    Lab.encode(reply.call(responses.fetch(spec.fetch("id"))))
  end
  backend
end

check.call("all A17 cases and corpora are delegated unchanged") do
  %w[planning holdout conversation transfer distractors].all? do |batch|
    Cases.cases(batch) == Lab::QualificationCasesA17.cases(batch) &&
      Cases.corpus(batch) == Lab::QualificationCasesA17.corpus(batch)
  end
end
check.call("heldout batch has four ordinary requests and a fresh three-document corpus") do
  specs = Cases.cases("heldout")
  corpus = Cases.corpus("heldout")
  old_numbers = %w[planning holdout conversation transfer distractors].flat_map do |batch|
    Lab::QualificationCasesA17.corpus(batch).flat_map { |doc| doc.fetch("content").scan(/\b\d+\b/) }
  end.uniq
  fresh_numbers = corpus.flat_map { |doc| doc.fetch("content").scan(/\b\d+\b/) }
  specs.map { |spec| spec.fetch("id") } == %w[a18-plan a18-change a18-callback a18-absent] &&
    specs.none? { |spec| spec.fetch("content").match?(/\b(?:13|37|14|33|56|132)\b|search\(|read\(|note\.write/) } &&
    corpus.length == 3 && corpus.map { |doc| doc.fetch("id") }.uniq.length == 3 &&
    (old_numbers & fresh_numbers).empty? &&
    corpus.any? { |doc| doc.fetch("id") == "bracken-ledger" && doc.fetch("content").include?("Finch") }
end
check.call("independent eligibility and minimum-price oracle agrees with the plan prompt and answer key") do
  plan_spec = Cases.cases("heldout").first
  expected_text = "#{plan_winner.fetch('crate')} #{plan_winner.fetch('seals')} #{plan_winner.fetch('price')}"
  plan_spec.fetch("content").include?("at least fifteen seals") &&
    plan_spec.fetch("facts").all? { |pattern| Cases.matches?(pattern, expected_text) } &&
    plan_spec.fetch("support").flatten.any? { |pattern| Cases.matches?(pattern, expected_text) } &&
    responses.fetch("a18-plan").include?(plan_winner.fetch("crate")) &&
    responses.fetch("a18-plan").include?("#{plan_winner.fetch('price')} credits")
end

Dir.mktmpdir("continuity-a18-cases-") do |root|
  store = Lab::Store.create(path: File.join(root, "store"), config: config, corpus: Cases.corpus("heldout"))
  outcomes = {}
  Cases.cases("heldout").each do |spec|
    dependencies = spec.fetch("requires_events").all? { |event_id| outcomes[event_id]&.fetch("score")&.fetch("passed") }
    raise "synthetic dependency missing: #{spec.fetch('id')}" unless dependencies
    before = store.snapshot
    Lab::Runtime.new(store: store, backend: backend_for.call(spec)).submit(event_id: spec.fetch("id"), content: spec.fetch("content"))
    after = store.snapshot
    event = after.fetch("events").fetch(spec.fetch("id"))
    score = Cases.evaluate(event: event, config: config, spec: spec, before: before, after: after)
    raise "synthetic trace failed: #{spec.fetch('id')} #{score.inspect}" unless score.fetch("passed")
    outcomes[spec.fetch("id")] = { "event" => event, "score" => score, "before" => before, "after" => after }
  end

  check.call("correct constrained selection, arithmetic correction, callback and unknown answer pass") do
    outcomes.keys.sort == %w[a18-absent a18-callback a18-change a18-plan] &&
      outcomes.values.all? { |entry| entry.fetch("score").fetch("semantic_review_required") } &&
      outcomes.fetch("a18-callback").fetch("score").fetch("sources").any? { |source| source["collection"] == "history" }
  end

  plan = outcomes.fetch("a18-plan")
  wrong = copy.call(plan.fetch("event"))
  wrong["reply"] = "Finch is the cheapest qualifying crate at 46 credits."
  wrong.fetch("calls").last["response"] = Lab.encode(reply.call(wrong.fetch("reply")))
  wrong_score = Cases.evaluate(event: wrong, config: config, spec: Cases.cases("heldout").first,
    before: plan.fetch("before"), after: plan.fetch("after"))
  check.call("incorrect near-name distractor answer is rejected") do
    wrong_score.fetch("reasons").include?("missing_expected_fact_tokens") || wrong_score.fetch("reasons").include?("missing_retrieved_support")
  end

  wrong_arithmetic = copy.call(outcomes.fetch("a18-change").fetch("event"))
  wrong_arithmetic["reply"] = "Four Maple crates provide 56 seals altogether and cost 133 credits."
  wrong_arithmetic.fetch("calls").last["response"] = Lab.encode(reply.call(wrong_arithmetic.fetch("reply")))
  arithmetic_score = Cases.evaluate(event: wrong_arithmetic, config: config, spec: Cases.cases("heldout").fetch(1),
    before: outcomes.fetch("a18-change").fetch("before"), after: outcomes.fetch("a18-change").fetch("after"))
  check.call("incorrect correction arithmetic is rejected") do
    arithmetic_score.fetch("reasons").include?("missing_expected_fact_tokens")
  end

  absent = outcomes.fetch("a18-absent")
  fabricated = copy.call(absent.fetch("event"))
  fabricated["reply"] = "The parts sheet promises a two-year warranty."
  fabricated.fetch("calls").last["response"] = Lab.encode(reply.call(fabricated.fetch("reply")))
  absent_score = Cases.evaluate(event: fabricated, config: config, spec: Cases.cases("heldout").last,
    before: absent.fetch("before"), after: absent.fetch("after"))
  check.call("fabricated unknown fact is rejected") do
    absent_score.fetch("reasons").include?("missing_expected_fact_tokens")
  end

  change = outcomes.fetch("a18-change")
  terminal = Lab.parse(change.fetch("event").fetch("calls").last.dig("context", "formatted"))
  direct = terminal.fetch("direct_corpus")
  check.call("complete selected direct-source objects support the final reply") do
    direct.length == 3 && direct.all? { |source| source.keys.sort == %w[collection content_digest id lineage_id provenance revision span text] } &&
      direct.all? { |source| source.fetch("provenance") == "operator_selected_source_not_authority" } &&
      change.fetch("score").fetch("sources").any? { |source| source["collection"] == "corpus" && source["id"] == "silverfen-parts" }
  end

  forged = copy.call(change.fetch("event"))
  forged_envelope = Lab.parse(forged.fetch("calls").last.dig("context", "formatted"))
  forged_envelope.fetch("direct_corpus").first["text"] = "Forged Silverfen Maple crate: 14 seals, 999 credits."
  forged.fetch("calls").last.fetch("context")["formatted"] = Lab.encode(forged_envelope)
  forged_score = Cases.evaluate(event: forged, config: config, spec: Cases.cases("heldout").fetch(1),
    before: change.fetch("before"), after: change.fetch("after"))

  missing = copy.call(change.fetch("event"))
  missing_envelope = Lab.parse(missing.fetch("calls").last.dig("context", "formatted"))
  missing_envelope["direct_corpus"] = []
  missing.fetch("calls").last.fetch("context")["formatted"] = Lab.encode(missing_envelope)
  missing_score = Cases.evaluate(event: missing, config: config, spec: Cases.cases("heldout").fetch(1),
    before: change.fetch("before"), after: change.fetch("after"))
  check.call("forged or missing final-call corpus objects cannot support an answer") do
    forged_score.fetch("reasons").include?("context_replay_mismatch") &&
      (missing_score.fetch("reasons").include?("context_replay_mismatch") || missing_score.fetch("reasons").include?("missing_retrieved_support"))
  end

  earlier_only = copy.call(change.fetch("event"))
  earlier_context = copy.call(earlier_only.fetch("calls").first)
  final_context = copy.call(earlier_context)
  final_envelope = Lab.parse(final_context.dig("context", "formatted"))
  final_envelope["direct_corpus"] = []
  final_context.fetch("context")["formatted"] = Lab.encode(final_envelope)
  earlier_only.fetch("calls") << final_context
  earlier_only_score = Cases.evaluate(event: earlier_only, config: config, spec: Cases.cases("heldout").fetch(1),
    before: change.fetch("before"), after: change.fetch("after"))
  check.call("source text present only in an earlier call cannot support the terminal answer") do
    earlier_only_score.fetch("reasons").include?("missing_retrieved_support")
  end

  store.close
end

puts "PASS: #{checks} A18 deterministic fixture checks; synthetic traces only, no live inference"
