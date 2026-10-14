#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "stringio"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"

Lab = SoulCore::ContinuityLab
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
deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20 }

class A5FixtureClient
  attr_reader :requests
  def initialize(count: ->(_envelope) { 100 }, response: ->(_envelope) { '{"action":"wait"}' })
    @count, @response, @requests = count, response, []
  end
  def request(method, route, payload = nil, deadline:)
    @requests << [method, route, payload]
    case route
    when "/apply-template"
      @envelope = JSON.parse(payload.fetch("messages").last.fetch("content"))
      { "prompt" => JSON.generate(payload) + "<think>\n\n</think>\n\n" }
    when "/tokenize" then { "tokens" => Array.new(@count.call(@envelope), 7) }
    when "/completion"
      { "content" => @response.call(@envelope), "tokens_evaluated" => payload.fetch("prompt").length,
        "tokens_predicted" => 10, "truncated" => false }
    else raise "unexpected fixture route"
    end
  end
end

broker_for = lambda do |client, receipts = [], budget = 3072|
  Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(r) { receipts << r },
    before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: budget)
end
backend_for = lambda do |broker|
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    broker.dispatch({ "operation" => "prepare_context", "call_index" => call_index, "input" => input }, deadline: deadline.call)["preparation"]
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    broker.dispatch({ "operation" => "generate", "call_index" => call_index, "input" => input,
      "preparation_digest" => preparation_digest }, deadline: deadline.call)["response"]
  end
  backend
end
config = Lab::Config.qwen_v4_qualification
state = { "lineage_id" => "a" * 32, "corpus_digest" => "b" * 64, "events" => {
  "test" => { "content" => "synthetic request", "content_digest" => Digest::SHA256.hexdigest("synthetic request"), "calls" => [] }
} }
initial = Lab::TokenContext.initial(state: state, event_id: "test", config: config)
prepare = ->(broker, input, index = 0) { broker.dispatch({ "operation" => "prepare_context", "input" => input, "call_index" => index }, deadline: deadline.call) }
generate = ->(broker, prep) { broker.dispatch({ "operation" => "generate", "input" => prep["formatted"], "call_index" => prep["call_index"], "preparation_digest" => Lab.digest(prep) }, deadline: deadline.call) }

check.call("legacy profiles do not gain preparation key") { !Lab::Config.qwen_v3_qualification.to_h.key?("context_preparation") }
check.call("new token profile is explicit and bounded") { config.tokenized_context? && Lab::TokenContext.budget(config) == 3072 && Lab::TokenContext.budget(Lab::Config.qwen_v4_qualification(rollover: true)) == 2048 }
check.call("preparation cannot enable fake or unknown backend modes") { raises.call(Lab::ValidationError) { Lab::Config.new("context_preparation" => "qwen_tokenized_v1") } }

client = A5FixtureClient.new
records = []
broker = broker_for.call(client, records)
prep = prepare.call(broker, initial)["preparation"]
context = Lab::TokenContext.finalize(state: state, event_id: "test", config: config, preparation: prep)
check.call("preparation records exact count and does not generate") { context.dig("manifest", "input_tokens") == 100 && client.requests.none? { |r| r[1] == "/completion" } }
check.call("duplicate preparation is denied") { raises.call(Lab::ValidationError) { prepare.call(broker, initial) } }
check.call("tampered selection cannot generate") { bad = copy.call(prep); bad["formatted"] += " "; raises.call(Lab::ValidationError) { generate.call(broker, bad) } }
check.call("tampered count cannot generate") { bad = copy.call(prep); bad["measurements"][0]["input_tokens"] = 99; raises.call(Lab::ValidationError) { generate.call(broker, bad) } }
check.call("exact cached tokens generated with unchanged sampler and grammar") do
  generate.call(broker, prep)["response"] == '{"action":"wait"}' &&
    client.requests.last[2] == Lab::QwenBrokerSession::V3_SETTINGS.merge("prompt" => Array.new(100, 7))
end
check.call("consumed preparation cannot generate twice") { raises.call(Lab::ValidationError) { generate.call(broker, prep) } }
check.call("generation without preparation is denied") { raises.call(Lab::ValidationError) { generate.call(broker_for.call(A5FixtureClient.new), prep) } }

# Four complete result groups; the fake host tokenizer charges per retained group.
populated = copy.call(state)
4.times do |index|
  populated["events"]["test"]["calls"] << { "response" => '{"action":"tool","tool":"read","arguments":{}}',
    "result" => { "ok" => true, "source" => { "collection" => "corpus", "id" => "long", "revision" => 1,
      "content_digest" => "c" * 64, "span" => [index, index + 1], "text" => "x" } } }
end
candidate = Lab::TokenContext.initial(state: populated, event_id: "test", config: config)
packing = broker_for.call(A5FixtureClient.new(count: ->(e) { 1000 + 800 * e["tool_groups"].length }))
# Only the exact fixed index is permitted; emulate prior completed dispatches.
packing.instance_variable_set(:@calls, 4)
packed = prepare.call(packing, candidate, 4)["preparation"]
packed_context = Lab::TokenContext.finalize(state: populated, event_id: "test", config: config, preparation: packed)
check.call("oldest whole groups removed until actual budget fits") do
  packed_context.dig("manifest", "input_tokens") == 2600 && packed_context.dig("manifest", "included_groups") == [2, 3] &&
    packed_context.dig("manifest", "omitted_groups").map { |g| g["call_index"] } == [0, 1] && packed["measurements"].length == 3
end
check.call("request and newest result preserved unchanged") do
  chosen = JSON.parse(packed["formatted"])
  chosen["user"] == JSON.parse(candidate)["user"] && chosen["tool_groups"].last == JSON.parse(candidate)["tool_groups"].last
end
%w[initial_sha256 template_sha256 protocol_version call_index input_budget].each do |key|
  check.call("reject stale or mismatched #{key}") do
    bad = copy.call(packed); bad[key] = key == "call_index" ? 3 : "wrong"
    raises.call(Lab::ValidationError) { Lab::TokenContext.finalize(state: populated, event_id: "test", config: config, preparation: bad) }
  end
end
check.call("reject unjustified omission below measured budget") do
  bad = copy.call(packed); bad["measurements"][0]["input_tokens"] = 200
  raises.call(Lab::ValidationError) { Lab::TokenContext.finalize(state: populated, event_id: "test", config: config, preparation: bad) }
end
check.call("reject altered or reordered selected groups") do
  bad = copy.call(packed); selected = JSON.parse(bad["formatted"]); selected["tool_groups"].reverse!; bad["formatted"] = Lab.encode(selected)
  raises.call(Lab::ValidationError) { Lab::TokenContext.finalize(state: populated, event_id: "test", config: config, preparation: bad) }
end
check.call("newest result survives essential rejection with no inference") do
  client = A5FixtureClient.new(count: ->(_e) { 3073 })
  too_large = broker_for.call(client)
  too_large.instance_variable_set(:@calls, 4)
  rejected = prepare.call(too_large, candidate, 4)
  ctx = Lab::TokenContext.finalize(state: populated, event_id: "test", config: config, preparation: rejected["preparation"], rejected: true)
  rejected["ok"] == false && ctx.dig("manifest", "included_groups") == [3] && client.requests.none? { |r| r[1] == "/completion" }
end
check.call("initial byte cap is explicit conservative trimming, not fake token count") do
  large = copy.call(populated); large["events"]["test"]["calls"].each { |c| c["result"]["source"]["text"] = "x" * 4000 }
  json = Lab::TokenContext.initial(state: large, event_id: "test", config: config)
  json.bytesize <= 12_288 && JSON.parse(json)["tool_groups"].map { |g| g["call_index"] } == [2, 3]
end

with_store = lambda do |fault = nil, &block|
  Dir.mktmpdir("continuity-a5-") do |directory|
    store = Lab::Store.create(path: "#{directory}/store", config: config, fault: fault)
    begin
      block.call(store, "#{directory}/store")
    ensure
      store.close
    end
  end
end
with_store.call do |store, path|
  client = A5FixtureClient.new
  runtime = Lab::Runtime.new(store: store, backend: backend_for.call(broker_for.call(client)))
  result = runtime.submit(event_id: "test", content: "synthetic request")
  snap = store.snapshot
  check.call("prepared context committed before response and replayed exactly") do
    reopened = Lab::Store.open(path: path, config: config)
    begin
      result["reason"] == "wait" && reopened.snapshot == snap && snap.dig("events", "test", "calls", 0, "context", "manifest", "counter") == Lab::TokenContext::COUNTER
    ensure
      reopened.close
    end
  end
  check.call("terminal resume does not prepare or generate") { prior = client.requests.length; runtime.resume(event_id: "test"); client.requests.length == prior }
end

with_store.call do |store, path|
  client = A5FixtureClient.new(count: ->(_e) { 3073 })
  runtime = Lab::Runtime.new(store: store, backend: backend_for.call(broker_for.call(client)))
  result = runtime.submit(event_id: "overflow", content: "mandatory text")
  check.call("essential token overflow commits grounded failure without intent or generation") do
    result["reason"] == "context_budget_exceeded" && store.snapshot.dig("events", "overflow", "context_rejection", "preparation", "status") == "rejected" &&
      store.snapshot.dig("events", "overflow", "calls").empty? && client.requests.none? { |r| r[1] == "/completion" }
  end
  reopened = Lab::Store.open(path: path, config: config)
  check.call("token overflow terminal reopens and resumes without host calls") do
    prior = client.requests.length
    Lab::Runtime.new(store: reopened, backend: backend_for.call(broker_for.call(client))).resume(event_id: "overflow")["state"] == "failed" && client.requests.length == prior
  end
  reopened.close
end
with_store.call do |store, _path|
  client = A5FixtureClient.new
  result = Lab::Runtime.new(store: store, backend: backend_for.call(broker_for.call(client))).submit(event_id: "bytes", content: "x" * 13_000)
  check.call("essential byte overflow commits failure without formatter call") { result["reason"] == "context_budget_exceeded" && client.requests.empty? }
end
with_store.call do |store, _path|
  backend = Lab::PipeBackend.new(input: StringIO.new(""), output: StringIO.new)
  check.call("preparation disconnect leaves no model intent") do
    raises.call(Lab::BrokerDisconnected) { Lab::Runtime.new(store: store, backend: backend).submit(event_id: "disconnect", content: "synthetic") } &&
      store.snapshot.dig("events", "disconnect", "calls").empty?
  end
end

%i[before_stage after_stage after_commit].each do |fault_point|
  %w[model_intent context_rejected].each do |kind|
    fired = false
    fault = lambda do |point, record|
      if !fired && point == fault_point && record["kind"] == kind
        fired = true
        raise IOError, "synthetic interruption"
      end
    end
    with_store.call(fault) do |store, path|
      client = A5FixtureClient.new(count: ->(_e) { kind == "context_rejected" ? 3073 : 100 })
      runtime = Lab::Runtime.new(store: store, backend: backend_for.call(broker_for.call(client)))
      check.call("interrupt #{kind} #{fault_point} before generation") do
        raises.call(Lab::IntegrityError) { runtime.submit(event_id: "interrupted", content: "synthetic") } && fired && client.requests.none? { |r| r[1] == "/completion" }
      end
      reopened = Lab::Store.open(path: path, config: config)
      snapshot = reopened.snapshot
      if fault_point == :after_commit
        if kind == "context_rejected"
          check.call("rejected context cannot be relabeled or followed by intent") do
            raises.call(Lab::IntegrityError) { reopened.synchronize { reopened.append("terminal", { "event_id" => "interrupted", "state" => "failed", "reason" => "deadline_exceeded" }) } } &&
              raises.call(Lab::IntegrityError) { reopened.synchronize { reopened.append("model_intent", { "event_id" => "interrupted", "call_index" => 0, "context" => {} }) } }
          end
        end
        prior = client.requests.length
        receipt = Lab::Runtime.new(store: reopened, backend: backend_for.call(broker_for.call(client))).resume(event_id: "interrupted")
        expected = kind == "model_intent" ? "unresolved_model_intent" : "context_budget_exceeded"
        check.call("committed #{kind} recovers without inference") { receipt["reason"] == expected && client.requests.length == prior }
      else
        check.call("uncommitted #{kind} leaves no uncertain model intent") { snapshot.dig("events", "interrupted", "calls").empty? && !snapshot.dig("events", "interrupted", "context_rejection") }
      end
      reopened.close
    end
  end
end

check.call("pipe preparation validates response status") do
  input = StringIO.new(Lab.encode({ "ok" => true, "preparation" => prep }) + "\n")
  output = StringIO.new
  Lab::PipeBackend.new(input: input, output: output).prepare(call_index: 0, input: initial) == prep && JSON.parse(output.string).dig("request", "operation") == "prepare_context"
end
puts "PASS: #{checks} A5 deterministic checks; no live inference"
