#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a17"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA17

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }

unless Lab::Config.respond_to?(:qwen_v8_qualification) && Lab::Config.respond_to?(:qwen_v7_qualification)
  abort "A17 Config factories are not available yet; rerun after the primary A17 context/config slice lands"
end
config = Lab::Config.qwen_v8_qualification
legacy_config = Lab::Config.qwen_v7_qualification

tool = ->(name, arguments) { { "action" => "tool", "tool" => name, "arguments" => arguments } }
reply = ->(content) { { "action" => "reply", "content" => content } }
search = lambda do |query, lineage|
  tool.call("search", { "lineage_id" => lineage, "collection" => "corpus", "query" => query, "limit" => 4 })
end

scripts = lambda do |spec, lineage|
  case spec.fetch("id")
  when "a17-plan"
    [search.call("Eastmere Harbor battery hours price", lineage), reply.call("The Harbor kit is the least expensive qualifying option, at 38 credits.")]
  when "a17-change"
    [search.call("Eastmere Lark battery hours cost", lineage), reply.call("Three Lark kits provide 27 battery hours altogether and cost 123 credits.")]
  when "a17-callback"
    [reply.call("You changed the plan to three Lark kits, for a combined price of 123 credits.")]
  when "a17-absent"
    [search.call("Eastmere warranty duration", lineage), reply.call("The catalog does not specify a warranty duration.")]
  else
    raise "missing deterministic script for #{spec.fetch('id')}"
  end
end

backend_for = lambda do |spec|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-a17-prompt", Array.new(100, 17))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    envelope = Lab.parse(input)
    Lab.encode(scripts.call(spec, envelope.fetch("lineage_id")).fetch(call_index))
  end
  backend
end

check.call("A17 retains A16's prior transfer cases unchanged") do
  %w[planning holdout conversation transfer].all? do |batch|
    Cases.cases(batch) == Lab::QualificationCasesA16.cases(batch) &&
      Cases.corpus(batch) == Lab::QualificationCasesA16.corpus(batch)
  end
end
check.call("distractor batch has four natural requests and three distinct project documents") do
  cases = Cases.cases("distractors")
  docs = Cases.corpus("distractors")
  cases.length == 4 && docs.length >= 3 && docs.map { |doc| doc.fetch("id") }.uniq.length == docs.length &&
    cases.map { |spec| spec.fetch("id") } == %w[a17-plan a17-change a17-callback a17-absent] &&
    cases.none? { |spec| spec.fetch("content").match?(/\b(?:38|27|123)\b|search\(|read\(|note\.write/) } &&
    !cases.first.fetch("content").match?(/\bHarbor\b/i)
end

Dir.mktmpdir("continuity-a17-cases-") do |root|
  path = File.join(root, "store")
  store = Lab::Store.create(path: path, config: config, corpus: Cases.corpus("distractors"))
  outcomes = {}
  Cases.cases("distractors").each do |spec|
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

  check.call("correct selection, changed quantity/product, absent fact and recent dialogue callback pass") do
    outcomes.keys.sort == %w[a17-absent a17-callback a17-change a17-plan] &&
      outcomes.values.all? { |entry| entry.fetch("score").fetch("passed") && entry.fetch("score").fetch("semantic_review_required") } &&
      outcomes.fetch("a17-callback").fetch("score").fetch("sources").any? { |source| source["collection"] == "history" && source["provenance"] == "observed_exchange_not_verified_fact" }
  end

  plan = outcomes.fetch("a17-plan")
  distractor = copy.call(plan.fetch("event"))
  distractor["reply"] = "The Harbor kit is the least expensive qualifying option, at 29 credits, according to Westmere."
  distractor.fetch("calls").last["response"] = Lab.encode(reply.call(distractor.fetch("reply")))
  distractor_score = Cases.evaluate(event: distractor, config: config, spec: Cases.cases("distractors").first,
    before: plan.fetch("before"), after: plan.fetch("after"))
  check.call("near-project distractor answer is rejected") do
    distractor_score.fetch("reasons").include?("missing_expected_fact_tokens") || distractor_score.fetch("reasons").include?("missing_retrieved_support")
  end

  changed = outcomes.fetch("a17-change")
  forged = copy.call(changed.fetch("event"))
  search_call = forged.fetch("calls").find { |call| Lab.parse(call.fetch("response"))["action"] == "tool" }
  search_call.fetch("result")["hits"].first["text"] = "Eastmere Lark kit provides 9 hours and costs 999 credits."
  forged_score = Cases.evaluate(event: forged, config: config, spec: Cases.cases("distractors").fetch(1),
    before: changed.fetch("before"), after: changed.fetch("after"))
  check.call("forged tool source/result is rejected by deterministic replay") do
    forged_score.fetch("reasons").include?("tool_result_replay_mismatch")
  end

  callback = outcomes.fetch("a17-callback")
  stale = copy.call(callback.fetch("event"))
  stale["reply"] = "You selected Harbor for 38 credits."
  stale.fetch("calls").last["response"] = Lab.encode(reply.call(stale.fetch("reply")))
  stale_score = Cases.evaluate(event: stale, config: config, spec: Cases.cases("distractors").fetch(2),
    before: callback.fetch("before"), after: callback.fetch("after"))
  check.call("stale or incorrect recent callback is rejected") do
    stale_score.fetch("reasons").include?("missing_expected_fact_tokens")
  end

  fake_context = copy.call(callback.fetch("event"))
  formatted = Lab.parse(fake_context.fetch("calls").first.dig("context", "formatted"))
  formatted["recent_dialogue"] = [{ "collection" => "history", "id" => "a17-change", "revision" => 1,
    "lineage_id" => callback.fetch("before").fetch("lineage_id"), "content_digest" => "0" * 64,
    "provenance" => "observed_exchange_not_verified_fact", "span" => [0, 20], "text" => "Lark 3 123" }]
  fake_context.fetch("calls").first.fetch("context")["formatted"] = Lab.encode(formatted)
  fake_score = Cases.evaluate(event: fake_context, config: config, spec: Cases.cases("distractors").fetch(2),
    before: callback.fetch("before"), after: callback.fetch("after"))
  check.call("fake dialogue text absent from the journal is rejected") do
    fake_score.fetch("reasons").include?("context_replay_mismatch")
  end

  reordered = copy.call(callback.fetch("event"))
  reordered_envelope = Lab.parse(reordered.fetch("calls").first.dig("context", "formatted"))
  reordered_envelope["recent_dialogue"] = reordered_envelope.fetch("recent_dialogue").reverse
  reordered.fetch("calls").first.fetch("context")["formatted"] = Lab.encode(reordered_envelope)
  reordered_score = Cases.evaluate(event: reordered, config: config, spec: Cases.cases("distractors").fetch(2),
    before: callback.fetch("before"), after: callback.fetch("after"))

  omitted = copy.call(callback.fetch("event"))
  omitted_envelope = Lab.parse(omitted.fetch("calls").first.dig("context", "formatted"))
  omitted_envelope["recent_dialogue"] = []
  omitted.fetch("calls").first.fetch("context")["formatted"] = Lab.encode(omitted_envelope)
  omitted_score = Cases.evaluate(event: omitted, config: config, spec: Cases.cases("distractors").fetch(2),
    before: callback.fetch("before"), after: callback.fetch("after"))
  check.call("reordered journal-valid dialogue and omitted under-budget dialogue are rejected") do
    original_context = callback.fetch("event").fetch("calls").first.fetch("context")
    original_context.fetch("manifest").fetch("input_tokens") <= Lab::TokenContext.budget(config) &&
      reordered_score.fetch("reasons").include?("context_replay_mismatch") &&
      omitted_score.fetch("reasons").include?("context_replay_mismatch")
  end

  no_tools = copy.call(plan.fetch("event"))
  no_tool_spec = Cases.cases("distractors").first.merge("no_tools" => true)
  no_tool_score = Cases.evaluate(event: no_tools, config: config, spec: no_tool_spec,
    before: plan.fetch("before"), after: plan.fetch("after"))
  check.call("no-tools constraint rejects a tool-using trace") do
    no_tool_score.fetch("reasons").include?("unnecessary_tools")
  end

  absent = outcomes.fetch("a17-absent")
  fabricated = copy.call(absent.fetch("event"))
  fabricated["reply"] = "The catalog specifies a five-year warranty."
  fabricated.fetch("calls").last["response"] = Lab.encode(reply.call(fabricated.fetch("reply")))
  absent_score = Cases.evaluate(event: fabricated, config: config, spec: Cases.cases("distractors").last,
    before: absent.fetch("before"), after: absent.fetch("after"))
  check.call("fabricated absent fact is rejected by the frozen unknown-answer rule") do
    absent_score.fetch("reasons").include?("missing_expected_fact_tokens")
  end

  eviction_spec = Cases.cases("distractors").fetch(2).merge("id" => "a17-eviction")
  eviction_backend = Lab::PipeBackend.new
  eviction_backend.define_singleton_method(:prepare) do |call_index:, input:|
    working = Lab.parse(input)
    measurements = []
    loop do
      tokens = call_index == 1 && !working.fetch("recent_dialogue", []).empty? ? 4000 : 100
      measurements << Lab::TokenContext.measurement(Lab.encode(working), "synthetic-a17-eviction", Array.new(tokens, 17))
      break unless tokens > Lab::TokenContext.budget(config)

      Lab::ContextBuilder.omit_oldest!(working)
    end
    Lab::TokenContext.preparation(initial: input, formatted: Lab.encode(working), measurements: measurements,
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  eviction_backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    envelope = Lab.parse(input)
    action = if call_index.zero?
               search.call("Eastmere Lark battery hours", envelope.fetch("lineage_id"))
             else
               reply.call("You changed the plan to three Lark kits, for a combined price of 123 credits.")
             end
    Lab.encode(action)
  end
  eviction_before = store.snapshot
  Lab::Runtime.new(store: store, backend: eviction_backend).submit(event_id: eviction_spec.fetch("id"), content: eviction_spec.fetch("content"))
  eviction_after = store.snapshot
  eviction_event = eviction_after.fetch("events").fetch(eviction_spec.fetch("id"))
  eviction_score = Cases.evaluate(event: eviction_event, config: config, spec: eviction_spec,
    before: eviction_before, after: eviction_after)
  first_envelope = Lab.parse(eviction_event.fetch("calls").first.dig("context", "formatted"))
  terminal_envelope = Lab.parse(eviction_event.fetch("calls").last.dig("context", "formatted"))
  terminal_hits = terminal_envelope.fetch("tool_groups").flat_map { |group| group.fetch("tool_result").fetch("hits", []) }
  check.call("dialogue visible only before the terminal reply cannot support its callback") do
    first_envelope.fetch("recent_dialogue").any? { |source| source.fetch("id") == "a17-change" } &&
      terminal_envelope.fetch("recent_dialogue").empty? &&
      !terminal_hits.empty? && terminal_hits.all? { |source| source.fetch("collection") == "corpus" } &&
      eviction_score.fetch("reasons").include?("missing_retrieved_support")
  end

  store.close

  baseline_config = Lab::Config.qwen_v6_qualification
  [["baseline", baseline_config], ["ranked-only", legacy_config]].each do |profile, profile_config|
    store = Lab::Store.create(path: File.join(root, profile), config: profile_config, corpus: Cases.corpus("distractors"))
    plan_spec = Cases.cases("distractors").first
    before_plan = store.snapshot
    Lab::Runtime.new(store: store, backend: backend_for.call(plan_spec)).submit(
      event_id: plan_spec.fetch("id"), content: plan_spec.fetch("content"))
    after_plan = store.snapshot
    plan_event = after_plan.fetch("events").fetch(plan_spec.fetch("id"))
    if profile == "ranked-only"
      plan_score = Cases.evaluate(event: plan_event, config: profile_config, spec: plan_spec,
        before: before_plan, after: after_plan)
      check.call("ranked-only profile keeps its distinct envelope without recent dialogue") do
        parsed = Lab.parse(plan_event.fetch("calls").first.dig("context", "formatted"))
        plan_score.fetch("passed") && !parsed.key?("recent_dialogue") && !parsed.key?("recent_dialogue_policy")
      end
    end

    change_spec = Cases.cases("distractors").fetch(1)
    Lab::Runtime.new(store: store, backend: backend_for.call(change_spec)).submit(
      event_id: change_spec.fetch("id"), content: change_spec.fetch("content"))
    callback_spec = Cases.cases("distractors").fetch(2)
    explicit_history = Lab::PipeBackend.new
    explicit_history.define_singleton_method(:prepare) do |call_index:, input:|
      measurement = Lab::TokenContext.measurement(input, "synthetic-a17-history-read", Array.new(100, 19))
      Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
        input_budget: Lab::TokenContext.budget(profile_config), call_index: call_index)
    end
    explicit_history.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
      envelope = Lab.parse(input)
      action = if call_index.zero?
                 tool.call("read", { "lineage_id" => envelope.fetch("lineage_id"), "collection" => "history",
                   "id" => "a17-change", "revision" => 1, "start" => 0, "length" => 1024 })
               else
                 reply.call("You changed the plan to three Lark kits, for a combined price of 123 credits.")
               end
      Lab.encode(action)
    end
    before_callback = store.snapshot
    Lab::Runtime.new(store: store, backend: explicit_history).submit(
      event_id: callback_spec.fetch("id"), content: callback_spec.fetch("content"))
    after_callback = store.snapshot
    callback_event = after_callback.fetch("events").fetch(callback_spec.fetch("id"))
    callback_score = Cases.evaluate(event: callback_event, config: profile_config, spec: callback_spec,
      before: before_callback, after: after_callback)
    check.call("#{profile} callback succeeds with an explicit history read in terminal context") do
      callback_score.fetch("passed") && callback_score.fetch("sources").any? { |source| source["collection"] == "history" && source["id"] == "a17-change" }
    end
    store.close
  end
end

puts "PASS: #{checks} A17 deterministic fixture checks; synthetic traces only, no live inference"
