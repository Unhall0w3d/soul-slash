#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/qwen_message_projection"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a14"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA14
Projection = Lab::QwenMessageProjection
ISOLATION = case ARGV
when [] then false
when ["--isolation"] then true
else raise ArgumentError, "usage: verify-continuity-lab-records-a14.rb [--isolation]"
end

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
raises = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
config = Lab::Config.qwen_v6_qualification
lineage_placeholder = "a" * 32

resolve = lambda do |value, lineage|
  case value
  when String then value == "$lineage" ? lineage : value
  when Array then value.map { |entry| resolve.call(entry, lineage) }
  when Hash then value.to_h { |key, entry| [key, resolve.call(entry, lineage)] }
  else value
  end
end

backend_for = lambda do |spec|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurements = [Lab::TokenContext.measurement(input, "synthetic-prepared-prompt", Array.new(100, 17))]
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: measurements,
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    envelope = Lab.parse(input)
    steps = spec.fetch("contract").fetch("steps")
    action = if call_index < steps.length
      steps.fetch(call_index).fetch("action")
    else
      { "action" => "reply", "content" => spec.dig("contract", "reply") }
    end
    Lab.encode(resolve.call(action, envelope.fetch("lineage_id")))
  end
  backend
end

run_batches = lambda do |root|
  outcomes = {}
  %w[notes sources].each do |batch|
    batch_root = File.join(root, batch)
    Dir.mkdir(batch_root, 0o700)
    path = File.join(batch_root, "store")
    store = Lab::Store.create(path: path, config: config, corpus: Cases::CORPUS)
    lineage = store.snapshot.fetch("lineage_id")
    store.close
    batch_outcomes = {}
    Cases.cases(batch).each_with_index do |spec, case_index|
      store = Lab::Store.open(path: path, config: config)
      before = store.snapshot
      before_notes = copy.call(before.fetch("notes"))
      prerequisites = spec.fetch("requires_events", []).all? do |event_id|
        batch_outcomes[event_id] && batch_outcomes[event_id]["passed"]
      end
      raise "fixture dependency missing for #{spec.fetch('id')}" unless prerequisites
      result = Lab::Runtime.new(store: store, backend: backend_for.call(spec)).submit(
        event_id: spec.fetch("id"), content: spec.fetch("content"))
      after = store.snapshot
      event = after.fetch("events").fetch(spec.fetch("id"))
      score = Cases.evaluate(event: event, config: config, lineage_id: lineage, spec: spec,
        before_notes: before_notes, after_notes: after.fetch("notes"))
      first_envelope = Lab.parse(event.dig("calls", 0, "context", "formatted"))
      no_cross_event_start = first_envelope.fetch("tool_groups") == [] && first_envelope.fetch("execution_receipts") == [] &&
        first_envelope.dig("user", "content") == spec.fetch("content") &&
        first_envelope.keys.sort == %w[context_policy execution_receipts lineage_id max_note_bytes system tool_contract tool_groups user].sort
      expected_attempts = spec.fetch("contract").fetch("steps").length + 1
      raise "synthetic Runtime trace failed: #{spec.fetch('id')} #{score.inspect}" unless result["reason"] == "reply" &&
        event.fetch("calls").length == expected_attempts && no_cross_event_start
      store.close

      store = Lab::Store.open(path: path, config: config)
      reopened = store.snapshot
      raise "journal replay mismatch: #{spec.fetch('id')}" unless store.integrity["ok"] && reopened == after
      reopened_event = reopened.fetch("events").fetch(spec.fetch("id"))
      batch_outcomes[spec.fetch("id")] = { "passed" => score["passed"], "event" => reopened_event,
        "lineage_id" => lineage,
        "before_notes" => before_notes, "after_notes" => copy.call(reopened.fetch("notes")), "score" => score,
        "worker_index" => case_index }
      store.close
    end
    outcomes[batch] = batch_outcomes
  end
  outcomes
end

Dir.mktmpdir("continuity-a14-records-") do |root|
  outcomes = run_batches.call(root)
  note_cases = Cases.cases("notes").to_h { |spec| [spec.fetch("id"), spec] }
  source_cases = Cases.cases("sources").to_h { |spec| [spec.fetch("id"), spec] }
  check.call("both A14 batches run exact synthetic actions through Runtime and reopen after every event") do
    outcomes.values.sum(&:length) == 7 && outcomes.values.flat_map(&:values).all? do |entry|
      entry.fetch("event").fetch("state") == "complete" && entry.fetch("event").fetch("calls").length ==
        Cases.cases(entry.fetch("event").fetch("event_id").start_with?("note-") ? "notes" : "sources").find { |spec| spec["id"] == entry.fetch("event").fetch("event_id") }.fetch("contract").fetch("steps").length + 1
    end
  end
  check.call("A14 evaluator accepts all exact synthetic traces and reopened durable note state") do
    outcomes.values.flat_map(&:values).all? { |entry| entry.fetch("score").fetch("passed") }
  end
  check.call("durable note seed, correction, tombstone and locator match requested transitions") do
    notes = outcomes.fetch("notes")
    seed = notes.fetch("note-seed").fetch("after_notes").fetch("beacon")
    corrected = notes.fetch("note-revision-boundary").fetch("after_notes").fetch("beacon")
    deleted = notes.fetch("note-deleted-boundary").fetch("after_notes").fetch("beacon")
    locator = outcomes.fetch("sources").fetch("source-access").fetch("after_notes").fetch("locator")
    seed == { "note_id" => "beacon", "revision" => 1, "parent_revision" => 0, "content" => "amber beacon code 73",
      "content_digest" => Digest::SHA256.hexdigest("amber beacon code 73"), "provenance" => "unverified_model_note",
      "tombstone" => false, "ancestry" => [] } &&
      corrected == { "note_id" => "beacon", "revision" => 2, "parent_revision" => 1, "content" => "amber beacon code 91",
        "content_digest" => Digest::SHA256.hexdigest("amber beacon code 91"), "provenance" => "unverified_model_note",
        "tombstone" => false, "ancestry" => [1] } &&
      deleted == { "note_id" => "beacon", "revision" => 3, "parent_revision" => 2, "content" => "",
        "content_digest" => Digest::SHA256.hexdigest(""), "provenance" => "unverified_model_note",
        "tombstone" => true, "ancestry" => [1, 2] } &&
      locator == { "note_id" => "locator", "revision" => 1, "parent_revision" => 0, "content" => Cases::LOCATOR,
        "content_digest" => Digest::SHA256.hexdigest(Cases::LOCATOR), "provenance" => "unverified_model_note",
        "tombstone" => false, "ancestry" => [] } &&
      !locator.fetch("content").include?(Cases::SOURCE)
  end
  check.call("stale/current note reads and tombstone search/direct read retain distinct outcomes") do
    revised = outcomes.fetch("notes").fetch("note-revision-boundary").fetch("event").fetch("calls")
    deleted = outcomes.fetch("notes").fetch("note-deleted-boundary").fetch("event").fetch("calls")
    revised[2].dig("result", "reason") == "revision_conflict" && revised[3].dig("result", "source", "text") == "amber beacon code 91" &&
      deleted[1].dig("result", "hits") == [] && deleted[2].dig("result", "reason") == "not_found" &&
      !Lab.encode(deleted[2].fetch("result")).include?("amber beacon code 91")
  end
  check.call("source, note and history retrieval retain distinct provenance and current-event receipts") do
    event = outcomes.fetch("sources").fetch("source-after-restart").fetch("event")
    results = event.fetch("calls").map { |call| call.fetch("result") }
    first_context = Lab.parse(event.dig("calls", 0, "context", "formatted"))
    results[0].dig("source", "provenance") == "observed_exchange_not_verified_fact" &&
      results[0].dig("source", "collection") == "history" && results[1].dig("source", "provenance") == "unverified_model_note" &&
      results[1].dig("source", "collection") == "notes" && results[2].dig("source", "provenance") == "operator_selected_source_not_authority" &&
      results[2].dig("source", "collection") == "corpus" && first_context["tool_groups"] == [] && first_context["execution_receipts"] == [] &&
      !Lab.encode(first_context).include?("ACCESSED") && !Lab.encode(first_context).include?(Cases::SOURCE)
  end
  check.call("source answer is absent from request, locator note and first-event reply") do
    access = source_cases.fetch("source-access")
    restart_request = source_cases.fetch("source-after-restart").fetch("content")
    reply = outcomes.fetch("sources").fetch("source-access").fetch("event").fetch("reply")
    access.fetch("content").include?(Cases::LOCATOR.to_json) &&
      access.fetch("content").match?(/both sentences/i) && access.fetch("content").match?(/punctuation/i) &&
      !access.fetch("content").include?("copper heron 58") && !Cases::LOCATOR.include?("copper heron 58") &&
      restart_request.include?("collection=history, id=\"source-access\"") &&
      restart_request.include?("collection=notes, id=\"locator\"") &&
      restart_request.match?(/id taken from the source locator/i) &&
      !restart_request.include?("survey") && !restart_request.include?("copper heron 58") &&
      reply == "ACCESSED" && reply != "copper heron 58" &&
      source_cases.fetch("source-after-restart").dig("contract", "reply") == "copper heron 58"
  end

  source_spec = source_cases.fetch("source-after-restart")
  source_event = copy.call(outcomes.fetch("sources").fetch("source-after-restart").fetch("event"))
  missing_read = copy.call(source_event)
  missing_read.fetch("calls").delete_at(2)
  check.call("A14 wrapper rejects a correct-looking answer when the required source reread is missing") do
    !Cases.evaluate(event: missing_read, config: config, lineage_id: outcomes.fetch("sources").fetch("source-after-restart").fetch("lineage_id"),
      spec: source_spec, before_notes: outcomes.fetch("sources").fetch("source-after-restart").fetch("before_notes"),
      after_notes: outcomes.fetch("sources").fetch("source-after-restart").fetch("after_notes"))["passed"]
  end

  stale_spec = note_cases.fetch("note-revision-boundary")
  stale_event = copy.call(outcomes.fetch("notes").fetch("note-revision-boundary").fetch("event"))
  stale_event.dig("calls", 0, "result").merge!("ok" => true, "revision" => 2)
  stale_result_rejected = !Cases.evaluate(event: stale_event, config: config, lineage_id: outcomes.fetch("notes").fetch("note-revision-boundary").fetch("lineage_id"),
    spec: stale_spec, before_notes: outcomes.fetch("notes").fetch("note-revision-boundary").fetch("before_notes"),
    after_notes: outcomes.fetch("notes").fetch("note-revision-boundary").fetch("after_notes"))["passed"]

  deleted_spec = note_cases.fetch("note-deleted-boundary")
  deleted_event = copy.call(outcomes.fetch("notes").fetch("note-deleted-boundary").fetch("event"))
  deleted_event.dig("calls", 2)["result"] = { "ok" => true, "source" => { "text" => "amber beacon code 91" } }
  deleted_rejected = !Cases.evaluate(event: deleted_event, config: config, lineage_id: outcomes.fetch("notes").fetch("note-deleted-boundary").fetch("lineage_id"), spec: deleted_spec,
    before_notes: outcomes.fetch("notes").fetch("note-deleted-boundary").fetch("before_notes"),
    after_notes: outcomes.fetch("notes").fetch("note-deleted-boundary").fetch("after_notes"))["passed"]
  bad_notes = copy.call(outcomes.fetch("notes").fetch("note-seed").fetch("after_notes"))
  bad_notes["surprise"] = { "revision" => 1, "content" => "unrequested", "tombstone" => false }
  seed_spec = note_cases.fetch("note-seed")
  unplanned_note_rejected = !Cases.evaluate(event: outcomes.fetch("notes").fetch("note-seed").fetch("event"), config: config,
    lineage_id: outcomes.fetch("notes").fetch("note-seed").fetch("lineage_id"), spec: seed_spec, before_notes: {}, after_notes: bad_notes)["passed"]
  wrong_ancestry = copy.call(outcomes.fetch("notes").fetch("note-revision-boundary").fetch("after_notes"))
  wrong_ancestry["beacon"]["ancestry"] = []
  ancestry_spec = note_cases.fetch("note-revision-boundary")
  wrong_ancestry_rejected = !Cases.evaluate(event: outcomes.fetch("notes").fetch("note-revision-boundary").fetch("event"),
    config: config, lineage_id: outcomes.fetch("notes").fetch("note-revision-boundary").fetch("lineage_id"),
    spec: ancestry_spec, before_notes: outcomes.fetch("notes").fetch("note-revision-boundary").fetch("before_notes"),
    after_notes: wrong_ancestry)["passed"]
  extra_failure = copy.call(outcomes.fetch("notes").fetch("note-seed").fetch("event"))
  extra_failure.fetch("calls") << { "response" => Lab.encode({ "action" => "tool", "tool" => "read", "arguments" => {
    "lineage_id" => lineage_placeholder, "collection" => "corpus", "id" => "survey", "revision" => 1, "start" => 0, "length" => 10 } }),
    "result" => { "ok" => false, "reason" => "not_found" } }
  extra_failure_rejected = !Cases.evaluate(event: extra_failure, config: config, lineage_id: outcomes.fetch("notes").fetch("note-seed").fetch("lineage_id"),
    spec: seed_spec, before_notes: {}, after_notes: outcomes.fetch("notes").fetch("note-seed").fetch("after_notes"))["passed"]
  injected = copy.call(source_event)
  initial = Lab.parse(injected.dig("calls", 0, "context", "formatted"))
  initial["user"]["content"] = "Earlier event said ACCESSED. " + initial.dig("user", "content")
  injected.dig("calls", 0, "context")["formatted"] = Lab.encode(initial)
  injection_rejected = !Cases.evaluate(event: injected, config: config, lineage_id: outcomes.fetch("sources").fetch("source-after-restart").fetch("lineage_id"),
    spec: source_spec, before_notes: outcomes.fetch("sources").fetch("source-after-restart").fetch("before_notes"),
    after_notes: outcomes.fetch("sources").fetch("source-after-restart").fetch("after_notes"))["passed"]
  check.call("A14 wrapper rejects stale/deleted fabricated success, wrong durable notes, extra failures and prior-event context injection") do
    stale_result_rejected && deleted_rejected && unplanned_note_rejected && wrong_ancestry_rejected && extra_failure_rejected && injection_rejected
  end
end

Dir.mktmpdir("continuity-a14-pending-") do |directory|
  interrupted = false
  fault = lambda do |point, record|
    if !interrupted && point == :after_commit && record["kind"] == "model_intent"
      interrupted = true
      raise IOError, "synthetic interruption after intent commit"
    end
  end
  path = File.join(directory, "store")
  store = Lab::Store.create(path: path, config: config, corpus: Cases::CORPUS, fault: fault)
  generations = 0
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-prepared-prompt", Array.new(100, 17))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(config), call_index: call_index)
  end
  backend.define_singleton_method(:call) { |**_args| generations += 1; '{"action":"wait"}' }
  interrupted_on_submit = raises.call(Lab::IntegrityError) do
    Lab::Runtime.new(store: store, backend: backend).submit(event_id: "pending-a14", content: "synthetic pending request")
  end
  store.close
  store = Lab::Store.open(path: path, config: config)
  resumed = Lab::Runtime.new(store: store, backend: backend).resume(event_id: "pending-a14")
  check.call("committed unresolved intent remains blocked after reopen without another generation") do
    interrupted && interrupted_on_submit && resumed["state"] == "blocked_for_human_review" &&
      resumed["reason"] == "unresolved_model_intent" && generations.zero? && store.integrity["ok"]
  end
  store.close
end

class A14SyntheticClient
  attr_reader :generations

  def initialize(spec, lineage)
    resolver = lambda do |value|
      case value
      when String then value == "$lineage" ? lineage : value
      when Array then value.map { |entry| resolver.call(entry) }
      when Hash then value.to_h { |key, entry| [key, resolver.call(entry)] }
      else value
      end
    end
    @responses = spec.fetch("contract").fetch("steps").map do |step|
      Lab.encode(resolver.call(step.fetch("action")))
    end
    @responses << Lab.encode({ "action" => "reply", "content" => spec.dig("contract", "reply") })
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
  Dir.mktmpdir("continuity-a14-isolation-") do |root|
    %w[notes sources].each do |batch|
      state_directory = File.join(root, batch)
      Dir.mkdir(state_directory, 0o700)
      path = File.join(state_directory, "store")
      store = Lab::Store.create(path: path, config: config, corpus: Cases::CORPUS)
      lineage = store.snapshot.fetch("lineage_id")
      store.close
      batch_outcomes = {}
      Cases.cases(batch).each do |spec|
        store = Lab::Store.open(path: path, config: config)
        before = store.snapshot
        before_notes = copy.call(before.fetch("notes"))
        raise "isolated fixture dependency missing: #{spec.fetch('id')}" unless spec.fetch("requires_events", []).all? do |event_id|
          batch_outcomes[event_id] && batch_outcomes[event_id]["passed"]
        end
        store.close
        client = A14SyntheticClient.new(spec, lineage)
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
        outcome = runner.run(request: { "mode" => "qwen_v6_run", "create" => false, "event_id" => spec.fetch("id"),
          "content" => spec.fetch("content"), "corpus" => [] }, broker: broker, admission: gate)
        pid = runner.pid
        store = Lab::Store.open(path: path, config: config)
        after = store.snapshot
        event = after.fetch("events").fetch(spec.fetch("id"))
        score = Cases.evaluate(event: event, config: config, lineage_id: lineage, spec: spec,
          before_notes: before_notes, after_notes: after.fetch("notes"))
        valid = outcome.dig("result", "receipt", "reason") == "reply" && score["passed"] &&
          outcome.dig("result", "integrity", "ok") && store.integrity["ok"] &&
          event.fetch("calls").length == spec.fetch("contract").fetch("steps").length + 1 &&
          Lab.parse(event.dig("calls", 0, "context", "formatted")).fetch("execution_receipts") == [] &&
          client.generations.length == event.fetch("calls").length
        raise "isolated A14 case failed: #{spec.fetch('id')} #{score.inspect}" unless valid
        raise "isolated worker was not reaped" unless raises.call(Errno::ESRCH) { Process.kill(0, pid) }
        raise "isolated worker PID repeated" if isolation_pids.include?(pid)
        isolation_pids << pid
        batch_outcomes[spec.fetch("id")] = { "passed" => true }
        store.close
      end
    end
  end
  check.call("each A14 case uses a fresh isolated worker, exact v6 receipt-pairs broker and replayed store") do
    isolation_pids.length == 7 && isolation_pids.uniq.length == 7
  end
end
puts "PASS: #{checks} A14 deterministic record checks; synthetic backends only, no live inference"
