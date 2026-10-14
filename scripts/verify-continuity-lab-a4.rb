#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qualification_scorer"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a4"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"

Lab = SoulCore::ContinuityLab
checks = 0
check = lambda do |name, condition|
  raise "FAIL: #{name}" unless condition
  checks += 1
  puts "PASS: #{name}"
end
raises = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
wait = Lab.encode("action" => "wait")
tool = ->(name, args) { Lab.encode("action" => "tool", "tool" => name, "arguments" => args) }
guard_config = Lab::Config.new("context_mode" => "explicit_v1", "failed_action_policy" => "consecutive_equivalent_failure_v1")
legacy = Lab::Config.new("context_mode" => "explicit_v1")
check.call("legacy config serialization has no new default key", !legacy.to_h.key?("failed_action_policy") && !legacy.repeated_failure_guard?)
check.call("unsupported failure policy rejected", raises.call(Lab::ValidationError) { Lab::Config.new("failed_action_policy" => "anything") })

# Only the opt-in configuration changes termination. Existing stores keep their
# prior behavior and configuration digest; effects still use the same reducer.
[legacy, guard_config].each do |config|
  Dir.mktmpdir("continuity-a4-guard-") do |root|
    store = Lab::Store.create(path: "#{root}/store", config: config)
    Lab::QualificationCasesA4.seed_note(store, "beacon", "original")
    bad = tool.call("note.write", { "note_id" => "wrong", "expected_revision" => 1, "content" => "replacement" })
    reordered = '{"arguments":{"content":"replacement","expected_revision":1,"note_id":"wrong"},"tool":"note.write","action":"tool"}'
    backend = Lab::FakeBackend.new(responses: [bad, reordered, wait])
    receipt = Lab::Runtime.new(store: store, backend: backend).submit(event_id: "repeat", content: "synthetic conflict")
    check.call("opt-in stop after two equivalent failures; legacy unaffected #{config.repeated_failure_guard?}",
               receipt["reason"] == (config.repeated_failure_guard? ? "repeated_failed_action" : "wait") && backend.calls == (config.repeated_failure_guard? ? 2 : 3))
    check.call("conflicts preserve original note #{config.repeated_failure_guard?}", store.snapshot["notes"].keys == ["beacon"] && store.snapshot.dig("notes", "beacon", "content") == "original")
    store.close
    store = Lab::Store.open(path: "#{root}/store", config: config)
    unused = Lab::FakeBackend.new(responses: [wait])
    check.call("terminal resume idempotent #{config.repeated_failure_guard?}", Lab::Runtime.new(store: store, backend: unused).resume(event_id: "repeat") == receipt && unused.calls.zero? && store.integrity["ok"])
    store.close
  end
end

%i[before_stage after_stage after_commit].each do |point|
  Dir.mktmpdir("continuity-a4-recovery-") do |root|
    armed = false
    crash = Class.new(StandardError)
    fault = lambda do |at, record|
      next unless armed && at == point && record["kind"] == "action_result" && record.dig("payload", "call_index") == 1
      armed = false
      raise crash
    end
    store = Lab::Store.create(path: "#{root}/store", config: guard_config, fault: fault)
    bad = tool.call("note.write", { "note_id" => "absent", "expected_revision" => 1, "content" => "new" })
    backend = Lab::FakeBackend.new(responses: [bad, bad, wait])
    armed = true
    check.call("inject interruption #{point}", raises.call(crash) { Lab::Runtime.new(store: store, backend: backend).submit(event_id: "repeat", content: "synthetic") })
    store.close
    store = Lab::Store.open(path: "#{root}/store", config: guard_config)
    if point == :after_commit
      store.synchronize do |state|
        %w[deadline_exceeded model_call_budget].each do |reason|
          check.call("repeat cannot be relabeled #{reason}", raises.call(Lab::IntegrityError) { store.append("terminal", { "event_id" => "repeat", "state" => "failed", "reason" => reason }) })
        end
        check.call("no additional intent after repeat", raises.call(Lab::IntegrityError) do
          store.append("model_intent", { "event_id" => "repeat", "call_index" => 2,
            "context" => Lab::ContextBuilder.build(state: state, event_id: "repeat", config: guard_config) })
        end)
      end
    end
    unused = Lab::FakeBackend.new(responses: [wait])
    receipt = Lab::Runtime.new(store: store, backend: unused).resume(event_id: "repeat")
    check.call("recovery terminates without regeneration #{point}", receipt["reason"] == "repeated_failed_action" && unused.calls.zero? && store.snapshot["operations"].length == 2 && store.integrity["ok"])
    store.close
  end
end

Dir.mktmpdir("continuity-a4-change-") do |root|
  store = Lab::Store.create(path: "#{root}/store", config: guard_config)
  bad = tool.call("note.write", { "note_id" => "note", "expected_revision" => 1, "content" => "good" })
  good = tool.call("note.write", { "note_id" => "note", "expected_revision" => 0, "content" => "good" })
  runtime = Lab::Runtime.new(store: store, backend: Lab::FakeBackend.new(responses: [bad, good, wait]))
  check.call("changed arguments may recover", runtime.submit(event_id: "repair", content: "synthetic")["state"] == "complete" && store.snapshot.dig("notes", "note", "revision") == 1)
  lineage = store.integrity["lineage_id"]
  read = tool.call("read", { "lineage_id" => lineage, "collection" => "notes", "id" => "note", "revision" => 1, "start" => 0, "length" => 100 })
  runtime = Lab::Runtime.new(store: store, backend: Lab::FakeBackend.new(responses: [read, read, wait]))
  check.call("successful rereads never trigger failure stop", runtime.submit(event_id: "reread", content: "synthetic")["state"] == "complete")
  # A forged terminal lacking two failures must not become replay-valid.
  text = "synthetic pending"
  store.synchronize do |_state|
    store.append("accepted", { "event_id" => "forged", "content" => text, "content_digest" => Digest::SHA256.hexdigest(text) })
    check.call("terminal requires grounded repeated-failure evidence", raises.call(Lab::IntegrityError) { store.append("terminal", { "event_id" => "forged", "state" => "failed", "reason" => "repeated_failed_action" }) })
  end
  store.close
end

# Exercise every proposed contract with actual runtime snapshots and outcomes.
# These scripted actions are fixtures, not model capability measurements.
Dir.mktmpdir("continuity-a4-catalog-") do |root|
  stores = {}
  begin
    %w[chain independent rollover].each do |group|
      config = Lab::Config.new(Lab::Config.qwen_v3_qualification(rollover: group == "rollover").to_h.merge("backend" => "fake"))
      stores[group] = Lab::Store.create(path: "#{root}/#{group}", config: config, corpus: Lab::QualificationCasesA4::CORPUS)
    end
    Lab::QualificationCasesA4.seed_note(stores["independent"], "correction", "initial code 41")
    Lab::QualificationCasesA4.seed_note(stores["independent"], "deletion", "disposable code 66")
    Lab::QualificationCasesA4.cases.each_with_index do |spec, index|
      store = stores.fetch(spec["group"])
      lineage = store.integrity["lineage_id"]
      before = store.snapshot
      actions = spec["contract"].fetch("steps", []).map { |step| Lab.encode(step["action"]).gsub('$lineage', lineage) }
      actions << Lab.encode("action" => "reply", "content" => spec["contract"]["reply"])
      backend = Lab::FakeBackend.new(responses: actions)
      id = "case-#{index}"
      Lab::Runtime.new(store: store, backend: backend).submit(event_id: id, content: spec["content"])
      after = store.snapshot
      outcome = Lab::QualificationScorer.evaluate(event: after["events"][id], config: store.config, lineage_id: lineage,
        contract: spec["contract"], before_notes: before["notes"], after_notes: after["notes"])
      check.call("actual journal contract #{spec['id']}: #{outcome['reasons']}", outcome["passed"])
    end
  ensure
    stores.each_value(&:close)
  end
end

class A4FixtureClient
  attr_reader :requests
  def initialize
    @requests = []
  end
  def request(method, route, payload = nil, deadline:)
    @requests << [method, route, payload]
    case route
    when "/apply-template" then { "prompt" => "fixture<think>\n\n</think>\n\n" }
    when "/tokenize" then { "tokens" => [1, 2] }
    when "/completion" then { "content" => '{"action":"wait"}', "tokens_evaluated" => 2, "tokens_predicted" => 6, "truncated" => false }
    else raise "Unexpected route"
    end
  end
end
client = A4FixtureClient.new
receipts = []
broker = Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(receipt) { receipts << receipt }, before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V3_PROMPT_VERSION)
response = broker.dispatch({ "operation" => "generate", "call_index" => 0, "input" => "synthetic" }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
payload = client.requests.find { |row| row[1] == "/completion" }[2]
check.call("v3.1 forwards raw response with ordered grammar", response["response"] == '{"action":"wait"}' && payload["grammar"] == Lab::QwenBrokerSession::V3_GRAMMAR && !payload.key?("json_schema") && receipts.last["prompt_version"] == Lab::QwenBrokerSession::V3_PROMPT_VERSION)
check.call("v3.1 changes structural constraint not sampler", Lab::QwenBrokerSession::SETTINGS.reject { |k, _| k == "json_schema" } == Lab::QwenBrokerSession::V3_SETTINGS.reject { |k, _| k == "grammar" })
system_text = client.requests.find { |row| row[1] == "/apply-template" }.dig(2, "messages", 0, "content")
check.call("v3.1 wrapper does not duplicate envelope protocol", system_text == Lab::QwenBrokerSession::V3_GUIDE && !system_text.include?(Lab::ContextBuilder::PROTOCOL))
grammar = payload["grammar"]
ordered_tool_branches = grammar.lines.grep(/\Aalternative-[2345] ::=/)
check.call("wire grammar retains tool discriminator before arguments", ordered_tool_branches.length == 4 && ordered_tool_branches.all? { |line| line.index("-tool-kv") < line.index("-arguments-kv") } && Lab.parse(Lab.encode(payload))["grammar"] == grammar)
examples = Lab::QwenBrokerSession::V3_GUIDE.lines.grep(/\A\{/).map(&:strip)
check.call("all six v3 examples parse under current action validation", examples.length == 6 && examples.all? { |s| !Lab::Actions.parse(s, Lab::Config.qwen_v3_qualification).empty? })

puts "PASS: #{checks} A4 deterministic checks; no live inference"
