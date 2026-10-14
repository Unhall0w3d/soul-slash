#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a19"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA19

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }

unless Lab::Config.respond_to?(:qwen_v9_qualification)
  abort "A19 requires the existing A18 Qwen v9 qualification config"
end
config = Lab::Config.qwen_v9_qualification

# This small oracle table is intentionally separate from the frozen corpus and
# case keys. Expected eligibility and arithmetic are derived from these rows.
MINIMUM_SENSORS = 32
ORACLE_CATALOG = [
  { "product" => "Tavren", "sensors" => 26, "unit_price" => 71 },
  { "product" => "Uldara", "sensors" => 34, "unit_price" => 89 },
  { "product" => "Merith", "sensors" => 32, "unit_price" => 101 },
  { "product" => "Qorven", "sensors" => 39, "unit_price" => 103 }
].freeze
first_quantity = 15
second_quantity = 20
winner = ORACLE_CATALOG.select { |row| row.fetch("sensors") >= MINIMUM_SENSORS }
  .min_by { |row| row.fetch("unit_price") }
raise "independent catalog has no qualifying product" unless winner
first_product = ORACLE_CATALOG.find { |row| row.fetch("product") == "Merith" }
second_product = ORACLE_CATALOG.find { |row| row.fetch("product") == "Tavren" }
first_total = { "sensors" => first_product.fetch("sensors") * first_quantity,
                "price" => first_product.fetch("unit_price") * first_quantity }
second_total = { "sensors" => second_product.fetch("sensors") * second_quantity,
                 "price" => second_product.fetch("unit_price") * second_quantity }

expected_replies = {
  "a19-plan" => "#{winner.fetch('product')} pack is the least expensive qualifying option: #{winner.fetch('sensors')} sensors for #{winner.fetch('unit_price')} crowns.",
  "a19-first-correction" => "#{first_quantity} #{first_product.fetch('product')} packs contain #{first_total.fetch('sensors')} sensors in total and cost #{first_total.fetch('price')} crowns.",
  "a19-second-correction" => "#{second_quantity} #{second_product.fetch('product')} packs contain #{second_total.fetch('sensors')} sensors in total and cost #{second_total.fetch('price')} crowns.",
  "a19-callback" => "The final choice is #{second_quantity} #{second_product.fetch('product')} packs, costing #{second_total.fetch('price')} crowns."
}
reply = ->(content) { { "action" => "reply", "content" => content } }

backend_for = lambda do |spec|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-a19-prompt", Array.new(100, 19))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    raise "unexpected extra call" unless call_index.zero?
    Lab.encode(reply.call(expected_replies.fetch(spec.fetch("id"))))
  end
  backend
end

delegated_batches = %w[planning holdout conversation transfer distractors heldout]
check.call("all six A18 batches retain exact cases and corpora") do
  delegated_batches.all? do |batch|
    Cases.cases(batch) == Lab::QualificationCasesA18.cases(batch) &&
      Cases.corpus(batch) == Lab::QualificationCasesA18.corpus(batch)
  end && delegated_batches.sum { |batch| Cases.cases(batch).length } == 24
end

specs = Cases.cases("chronology")
corpus = Cases.corpus("chronology")
old_numbers = delegated_batches.flat_map do |batch|
  Lab::QualificationCasesA18.corpus(batch).flat_map { |doc| doc.fetch("content").scan(/\b\d+\b/) }
end.uniq
new_numbers = corpus.flat_map { |doc| doc.fetch("content").scan(/\b\d+\b/) }.uniq
check.call("chronology has four unique ordered cases and a bounded fresh three-source corpus") do
  specs.map { |spec| spec.fetch("id") } == %w[a19-plan a19-first-correction a19-second-correction a19-callback] &&
    specs.all? { |spec| spec.fetch("group") == "chronology" && spec.fetch("requires_events").is_a?(Array) } &&
    specs.map { |spec| spec.fetch("id") }.uniq.length == 4 &&
    corpus.length == 3 && corpus.map { |doc| doc.fetch("id") }.uniq.length == 3 &&
    (old_numbers & new_numbers).empty? &&
    corpus.any? { |doc| doc.fetch("id") == "duskfen-instruments" && doc.fetch("content").include?("Orvail") } &&
    corpus.any? { |doc| doc.fetch("id") == "pellwick-depot" }
end

oracle_plan_text = "#{winner.fetch('product')} #{winner.fetch('sensors')} #{winner.fetch('unit_price')}"
oracle_first_text = "Merith #{first_quantity} #{first_total.fetch('sensors')} #{first_total.fetch('price')}"
oracle_second_text = "Tavren #{second_quantity} #{second_total.fetch('sensors')} #{second_total.fetch('price')}"
catalog_text = corpus.find { |doc| doc.fetch("id") == "tarnvale-sensors" }.fetch("content")
observed_catalog = catalog_text.scan(/\b([A-Za-z]+) pack: (\d+) sensors, (\d+) crowns\b/).map do |product, sensors, price|
  { "product" => product, "sensors" => Integer(sensors), "unit_price" => Integer(price) }
end
check.call("independent eligibility and arithmetic oracle matches the actual catalog, prompts, facts, and support") do
  eligible = ORACLE_CATALOG.select { |row| row.fetch("sensors") >= MINIMUM_SENSORS }
  observed_catalog == ORACLE_CATALOG &&
    specs.fetch(0).fetch("content").match?(/least expensive.*at least (?:#{MINIMUM_SENSORS}|thirty-two) sensors/i) &&
    winner.fetch("product") == "Uldara" && eligible.map { |row| row.fetch("unit_price") }.min == winner.fetch("unit_price") &&
    specs.fetch(0).fetch("facts").all? { |pattern| Cases.matches?(pattern, oracle_plan_text) } &&
    specs.fetch(0).fetch("support").flatten.drop(1).all? { |pattern| Cases.matches?(pattern, catalog_text) } &&
    specs.fetch(1).fetch("content").match?(/fifteen Merith packs/i) &&
    specs.fetch(1).fetch("facts").all? { |pattern| Cases.matches?(pattern, oracle_first_text) } &&
    specs.fetch(1).fetch("support").flatten.drop(1).all? { |pattern| Cases.matches?(pattern, catalog_text) } &&
    specs.fetch(2).fetch("content").match?(/twenty Tavren packs/i) &&
    specs.fetch(2).fetch("facts").all? { |pattern| Cases.matches?(pattern, oracle_second_text) } &&
    specs.fetch(2).fetch("support").flatten.drop(1).all? { |pattern| Cases.matches?(pattern, catalog_text) } &&
    specs.fetch(3).fetch("content").match?(/how many packs.*total price/i) &&
    specs.fetch(1).fetch("requires_events") == ["a19-plan"] &&
    specs.fetch(2).fetch("requires_events") == ["a19-first-correction"] &&
    specs.fetch(3).fetch("requires_events") == ["a19-second-correction"] &&
    specs.fetch(3).fetch("support").first.first == "recent_dialogue" &&
    specs.fetch(3).fetch("support").flatten.drop(1).all? { |pattern| Cases.matches?(pattern, expected_replies.fetch("a19-second-correction")) }
end

Dir.mktmpdir("continuity-a19-cases-") do |root|
  store = Lab::Store.create(path: File.join(root, "store"), config: config, corpus: corpus)
  direct_sources = Lab::DirectEvidence.sources(store.snapshot, "a19-plan")
  check.call("actual direct-evidence sources remain within count and encoded-byte bounds") do
    direct_sources.length == corpus.length && direct_sources.length <= Lab::DirectEvidence::MAX_DOCUMENTS &&
      Lab.encode(direct_sources).bytesize <= Lab::DirectEvidence::MAX_BYTES &&
      direct_sources.map { |source| source.fetch("id") }.sort == corpus.map { |doc| doc.fetch("id") }.sort
  end
  outcomes = {}
  specs.each do |spec|
    dependencies = spec.fetch("requires_events").all? { |event_id| outcomes[event_id]&.fetch("score")&.fetch("passed") }
    raise "synthetic chronology dependency missing: #{spec.fetch('id')}" unless dependencies
    before = store.snapshot
    receipt = Lab::Runtime.new(store: store, backend: backend_for.call(spec)).submit(
      event_id: spec.fetch("id"), content: spec.fetch("content"))
    after = store.snapshot
    event = after.fetch("events").fetch(spec.fetch("id"))
    score = Cases.evaluate(event: event, config: config, spec: spec, before: before, after: after)
    raise "synthetic trace failed: #{spec.fetch('id')} #{score.inspect}" unless receipt["reason"] == "reply" && score.fetch("passed")
    outcomes[spec.fetch("id")] = { "event" => event, "score" => score, "before" => before, "after" => after }
  end

  check.call("all four chronological synthetic examples pass with recent evidence for each prior exchange") do
    outcomes.keys == specs.map { |spec| spec.fetch("id") } &&
      outcomes.values.all? { |entry| entry.fetch("score").fetch("semantic_review_required") } &&
      begin
        final_context = Lab.parse(outcomes.fetch("a19-callback").fetch("event").fetch("calls").last.dig("context", "formatted"))
        final_context.fetch("recent_dialogue").map { |source| source.fetch("id") } ==
          %w[a19-plan a19-first-correction a19-second-correction] &&
          outcomes.fetch("a19-callback").fetch("score").fetch("sources").any? do |source|
            source["collection"] == "history" && source["id"] == "a19-second-correction"
          end
      end
  end

  callback = outcomes.fetch("a19-callback")
  [
    ["original selection", "The order is one Uldara pack for 89 crowns."],
    ["middle correction", "The order is fifteen Merith packs for 1515 crowns."]
  ].each do |label, wrong_reply|
    wrong = copy.call(callback.fetch("event"))
    wrong["reply"] = wrong_reply
    wrong.fetch("calls").last["response"] = Lab.encode(reply.call(wrong_reply))
    score = Cases.evaluate(event: wrong, config: config, spec: specs.fetch(3),
      before: callback.fetch("before"), after: callback.fetch("after"))
    check.call("callback rejects the stale #{label}") do
      score.fetch("reasons").include?("missing_expected_fact_tokens") || score.fetch("reasons").include?("missing_retrieved_support")
    end
  end

  store.close
end

puts "PASS: #{checks} A19 deterministic fixture checks; synthetic traces only, no live inference"
