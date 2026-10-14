#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/qwen_message_projection"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a15"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA15
Projection = Lab::QwenMessageProjection

ISOLATION = case ARGV
when [] then false
when ["--isolation"] then true
else raise ArgumentError, "usage: verify-continuity-lab-usability-a15.rb [--isolation]"
end

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
config = Lab::Config.qwen_v6_qualification

tool = lambda do |name, arguments|
  { "action" => "tool", "tool" => name, "arguments" => arguments }
end
read = lambda do |collection, id, lineage|
  tool.call("read", { "lineage_id" => lineage, "collection" => collection, "id" => id,
    "revision" => 1, "start" => 0, "length" => 1024 })
end
search = lambda do |collection, query, lineage|
  tool.call("search", { "lineage_id" => lineage, "collection" => collection,
    "query" => query, "limit" => 4 })
end
write = lambda do |id, content|
  tool.call("note.write", { "note_id" => id, "expected_revision" => 0, "content" => content })
end
reply = ->(content) { { "action" => "reply", "content" => content } }

# These expected answers exist only in deterministic fixture responses.
scripts = lambda do |spec, lineage|
  case spec.fetch("id")
  when "m-plan"
    [search.call("corpus", "Birch battery", lineage), reply.call("Birch is the least expensive option with HDMI and battery power: 42 credits for one day.")]
  when "m-change"
    [read.call("corpus", "rental-sheet", lineage), write.call("decision", "Marigold workshop: two Cedar projectors for one day, 110 credits total."),
     reply.call("Two Cedar projectors for one day would total 110 credits.")]
  when "m-recall"
    [read.call("notes", "decision", lineage), reply.call("We settled on two Cedar projectors for one day, totaling 110 credits.")]
  when "m-unknown"
    [search.call("corpus", "delivery workshop", lineage), reply.call("No delivery time is recorded in the available information.")]
  when "c-uppercase"
    [reply.call("BRING THE BLUE NOTEBOOK")]
  when "c-plan"
    [search.call("corpus", "Meadow compost", lineage), reply.call("Three Meadow bags cover 36 litres and cost 27 credits.")]
  when "c-change"
    [read.call("corpus", "garden-sheet", lineage), write.call("garden-choice", "Copperfield: four Birch bags, 32 litres total, 24 credits."),
     reply.call("Four Birch bags provide 32 litres and cost 24 credits.")]
  when "c-recall"
    [read.call("notes", "garden-choice", lineage), reply.call("We finished with four Birch bags, 32 litres, for 24 credits.")]
  when "chat-walk"
    [reply.call("That sounds like a nice way to wind down. I'm doing well, thanks for asking.")]
  when "chat-reason"
    [reply.call("A quiet break to clear your head can be welcome.")]
  when "chat-drink"
    [reply.call("Hot chocolate sounds like a much cozier choice.")]
  when "chat-recall"
    [read.call("history", "chat-reason", lineage), read.call("history", "chat-drink", lineage),
     reply.call("You're drinking hot chocolate now, and you went out to clear your head and take a break.")]
  else
    raise "missing deterministic script for #{spec.fetch('id')}"
  end
end

backend_for = lambda do |spec|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-a15-prompt", Array.new(100, 17))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    envelope = Lab.parse(input)
    action = scripts.call(spec, envelope.fetch("lineage_id")).fetch(call_index)
    Lab.encode(action)
  end
  backend
end

Dir.mktmpdir("continuity-a15-usability-") do |root|
  outcomes = {}
  %w[planning holdout conversation].each do |batch|
    directory = File.join(root, batch)
    Dir.mkdir(directory, 0o700)
    path = File.join(directory, "store")
    store = Lab::Store.create(path: path, config: config, corpus: Cases.corpus(batch))
    lineage = store.snapshot.fetch("lineage_id")
    batch_outcomes = {}
    Cases.cases(batch).each do |spec|
      before = store.snapshot
      dependencies = spec.fetch("requires_events").all? do |event_id|
        batch_outcomes[event_id] && batch_outcomes[event_id].fetch("score").fetch("passed")
      end
      raise "synthetic dependency missing: #{spec.fetch('id')}" unless dependencies
      receipt = Lab::Runtime.new(store: store, backend: backend_for.call(spec)).submit(
        event_id: spec.fetch("id"), content: spec.fetch("content"))
      after = store.snapshot
      event = after.fetch("events").fetch(spec.fetch("id"))
      score = Cases.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      raise "synthetic trace failed: #{spec.fetch('id')} #{score.inspect}" unless receipt["reason"] == "reply" && score["passed"]
      store.close
      store = Lab::Store.open(path: path, config: config)
      reopened = store.snapshot
      raise "replay mismatch: #{spec.fetch('id')}" unless store.integrity["ok"] && reopened == after
      batch_outcomes[spec.fetch("id")] = { "event" => reopened.fetch("events").fetch(spec.fetch("id")),
        "score" => score, "before" => before, "after" => reopened }
    end
    outcomes[batch] = batch_outcomes
    store.close
  end

  check.call("three batches complete all 12 independent synthetic events with durable replay") do
    entries = outcomes.values.flat_map(&:values)
    outcomes.values.sum(&:length) == 12 && entries.all? { |entry|
      event = entry.fetch("event")
      event.fetch("state") == "complete" && event.fetch("reason") == "reply" &&
        entry.fetch("score").fetch("passed") && entry.fetch("score").fetch("semantic_review_required")
    }
  end
  check.call("grounded alternative search/read routes support facts and changed-decision recall") do
    plan = outcomes.fetch("planning")
    holdout = outcomes.fetch("holdout")
    plan.fetch("m-plan").fetch("score").fetch("sources").any? { |s| s["collection"] == "corpus" && s["text"].match?(/Birch.*42.*battery/i) } &&
      holdout.fetch("c-plan").fetch("score").fetch("sources").any? { |s| s["collection"] == "corpus" && s["text"].match?(/Meadow.*12.*9/i) } &&
      plan.fetch("m-recall").fetch("score").fetch("sources").any? { |s| s["collection"] == "notes" } &&
      holdout.fetch("c-recall").fetch("score").fetch("sources").any? { |s| s["collection"] == "notes" }
  end
  check.call("optional notes are real durable effects while no-note success is accepted") do
    note_event = outcomes.fetch("planning").fetch("m-change")
    no_note_event = outcomes.fetch("holdout").fetch("c-uppercase")
    note_event.fetch("score").fetch("notes_changed") && note_event.fetch("after").fetch("notes").key?("decision") &&
      no_note_event.fetch("score").fetch("passed") && !no_note_event.fetch("score").fetch("notes_changed") &&
      no_note_event.fetch("event").fetch("calls").length == 1
  end
  check.call("semantic-only conversation turns are explicitly marked for primary assessment") do
    %w[chat-walk chat-reason chat-drink].all? do |id|
      score = outcomes.fetch("conversation").fetch(id).fetch("score")
      score.fetch("semantic_only") && score.fetch("semantic_review_required") && score.fetch("status") == "eligible_for_primary_assessment"
    end
  end
  check.call("initial requests are clean and do not receive future fixture facts") do
    outcomes.values.flat_map(&:values).all? do |entry|
      event = entry.fetch("event")
      context = Lab.parse(event.dig("calls", 0, "context", "formatted"))
      context.fetch("tool_groups") == [] && context.fetch("execution_receipts") == [] &&
        context.fetch("user").fetch("content") == event.fetch("content")
    end &&
      !Cases.cases("planning").first.fetch("content").include?("Birch") &&
      !Cases.cases("holdout").fetch(1).fetch("content").include?("27") &&
      !Cases.cases("conversation").fetch(3).fetch("content").include?("hot chocolate")
  end
  check.call("unknown delivery answer is grounded in a relevant lookup, without invented detail") do
    unknown = outcomes.fetch("planning").fetch("m-unknown")
    unknown.fetch("score").fetch("passed") && unknown.fetch("score").fetch("sources").any? { |s| s["collection"] == "corpus" } &&
      unknown.fetch("event").fetch("reply").match?(/not recorded|no .*recorded/i)
  end

  plan_spec = Cases.cases("planning").first
  plan_entry = outcomes.fetch("planning").fetch("m-plan")
  fabricated = copy.call(plan_entry.fetch("event"))
  fabricated.dig("calls", 0, "result").merge!("ok" => true, "hits" => [], "truncated" => false)
  fabricated_rejected = !Cases.evaluate(event: fabricated, config: config, spec: plan_spec,
    before: plan_entry.fetch("before"), after: plan_entry.fetch("after")).fetch("passed")
  wrong_reply = copy.call(plan_entry.fetch("event"))
  wrong_reply["reply"] = "Cedar costs 42 credits and includes battery power."
  wrong_reply.fetch("calls").last["response"] = Lab.encode(reply.call(wrong_reply.fetch("reply")))
  wrong_reply_reasons = Cases.evaluate(event: wrong_reply, config: config, spec: plan_spec,
    before: plan_entry.fetch("before"), after: plan_entry.fetch("after")).fetch("reasons")
  wrong_reply_rejected = wrong_reply_reasons.include?("missing_expected_fact_tokens")
  missing_source = copy.call(plan_entry.fetch("event"))
  tail = Cases::RENTALS.index("Delivery arrangements")
  irrelevant_read = read.call("corpus", "rental-sheet", plan_entry.fetch("before").fetch("lineage_id"))
  irrelevant_read.fetch("arguments").merge!("start" => tail)
  missing_source.fetch("calls").first["response"] = Lab.encode(irrelevant_read)
  missing_source.fetch("calls").first["result"] = Lab::Actions.tool_result(plan_entry.fetch("before"), irrelevant_read,
    config, "m-plan").fetch("result")
  missing_source_reasons = Cases.evaluate(event: missing_source, config: config, spec: plan_spec,
    before: plan_entry.fetch("before"), after: plan_entry.fetch("after")).fetch("reasons")
  missing_source_rejected = missing_source_reasons.include?("missing_retrieved_support")
  extra_note = copy.call(outcomes.fetch("holdout").fetch("c-uppercase").fetch("after"))
  extra_note.fetch("notes")["fabricated"] = { "note_id" => "fabricated", "revision" => 1, "parent_revision" => 0,
    "content" => "unexpected", "content_digest" => Digest::SHA256.hexdigest("unexpected"), "provenance" => "unverified_model_note",
    "tombstone" => false, "ancestry" => [] }
  extra_note_rejected = !Cases.evaluate(event: outcomes.fetch("holdout").fetch("c-uppercase").fetch("event"), config: config,
    spec: Cases.cases("holdout").first, before: outcomes.fetch("holdout").fetch("c-uppercase").fetch("before"),
    after: extra_note).fetch("passed")
  invalid_terminal = copy.call(plan_entry.fetch("event"))
  invalid_terminal["reason"] = "wait"
  invalid_terminal.delete("reply")
  invalid_terminal_rejected = !Cases.evaluate(event: invalid_terminal, config: config, spec: plan_spec,
    before: plan_entry.fetch("before"), after: plan_entry.fetch("after")).fetch("passed")
  stale_fact = copy.call(outcomes.fetch("planning").fetch("m-recall").fetch("event"))
  stale_fact["reply"] = "We settled on one Alder projector, totaling 28 credits."
  stale_fact.fetch("calls").last["response"] = Lab.encode(reply.call(stale_fact.fetch("reply")))
  stale_fact_reasons = Cases.evaluate(event: stale_fact, config: config, spec: Cases.cases("planning").fetch(2),
    before: outcomes.fetch("planning").fetch("m-recall").fetch("before"), after: outcomes.fetch("planning").fetch("m-recall").fetch("after")).fetch("reasons")
  stale_fact_rejected = stale_fact_reasons.include?("missing_expected_fact_tokens")
  check.call("mechanical screening rejects fabricated retrieval, wrong/stale facts, missing support, extra note effects and invalid terminal") do
    fabricated_rejected && wrong_reply_rejected && missing_source_rejected && extra_note_rejected && invalid_terminal_rejected && stale_fact_rejected
  end
end

puts "PASS: #{checks} A15 deterministic usability checks; synthetic fixture replies only, no live inference"

class A15SyntheticClient
  attr_reader :generations

  def initialize(spec, lineage, scripts)
    @responses = scripts.call(spec, lineage).map { |action| Lab.encode(action) }
    @generations = []
  end

  def request(_method, route, payload = nil, deadline:)
    case route
    when "/apply-template"
      { "prompt" => Lab.encode(payload) + "<think>\n\n</think>\n\n" }
    when "/tokenize"
      { "tokens" => Array.new(128, 17) }
    else
      raise "unexpected synthetic host route #{route}"
    end
  end

  def stream_completion(payload, deadline:, on_progress:)
    @generations << payload
    response = @responses.shift || raise("synthetic response script exhausted")
    { "content" => response, "tokens_evaluated" => payload.fetch("prompt").length,
      "tokens_predicted" => 1, "truncated" => false }
  end
end

if ISOLATION
  isolation_pids = []
  Dir.mktmpdir("continuity-a15-isolation-") do |root|
    [["planning", "m-plan"], ["holdout", "c-change"]].each do |batch, event_id|
      state_directory = File.join(root, "#{batch}-#{event_id}")
      Dir.mkdir(state_directory, 0o700)
      path = File.join(state_directory, "store")
      corpus = Cases.corpus(batch)
      store = Lab::Store.create(path: path, config: config, corpus: corpus)
      before = store.snapshot
      lineage = before.fetch("lineage_id")
      spec = Cases.cases(batch).find { |candidate| candidate.fetch("id") == event_id }
      store.close

      client = A15SyntheticClient.new(spec, lineage, scripts)
      broker = Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(_row) {}, before_generation: -> {},
        protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
        execution_profile: Lab::Config::STREAM_PROFILE, message_profile: Projection::PROFILE_RECEIPT_PAIRS)
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: File.join(root, "leases"))
      snapshot_provider = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free",
        "profile_id" => "nvidia-fallback", "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true,
        "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
      gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: snapshot_provider)
      runner = Lab::SandboxRunner.new(state_directory: state_directory, timeout_seconds: 430,
        execution_profile: Lab::Config::STREAM_PROFILE)
      outcome = runner.run(request: { "mode" => "qwen_v6_run", "create" => false, "event_id" => event_id,
        "content" => spec.fetch("content"), "corpus" => [] }, broker: broker, admission: gate)
      pid = outcome.fetch("worker_pid")

      store = Lab::Store.open(path: path, config: config)
      after = store.snapshot
      event = after.fetch("events").fetch(event_id)
      score = Cases.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      valid = outcome.dig("result", "receipt", "reason") == "reply" && score.fetch("passed") &&
        outcome.dig("result", "integrity", "ok") && store.integrity.fetch("ok") &&
        event.fetch("calls").length == scripts.call(spec, lineage).length &&
        Lab.parse(event.dig("calls", 0, "context", "formatted")).fetch("execution_receipts") == [] &&
        client.generations.length == event.fetch("calls").length
      raise "isolated A15 case failed: #{event_id} #{score.inspect}" unless valid
      raise "isolated worker was not reaped" if File.exist?("/proc/#{pid}")
      raise "isolated worker PID repeated" if isolation_pids.include?(pid)
      isolation_pids << pid
      store.close
    end
  end
  check.call("representative A15 cases use fresh synthetic isolated workers and replayed stores") do
    isolation_pids.length == 2 && isolation_pids.uniq.length == 2
  end
end
