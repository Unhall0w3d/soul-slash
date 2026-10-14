#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"

Lab = SoulCore::ContinuityLab
isolation = ARGV == ["--isolation"]
raise ArgumentError, "usage: verifier [--isolation]" unless ARGV.empty? || isolation
checks = 0
check = lambda { |name, &block| raise("FAIL: #{name}") unless block.call; checks += 1; puts "PASS: #{name}" }
raises = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
config = Lab::Config.qwen_v9_qualification
legacy = Lab::Config.qwen_v8_qualification
check.call("direct opt-in restricts calls and tools without changing old config") do
  restored = config.to_h.reject { |k, _| k == "answer_policy" }.merge(legacy.to_h.slice("max_model_calls", "max_tool_calls", "max_invalid_actions"))
  Lab::Config.new(restored).digest == legacy.digest && config.direct_evidence? && config["max_model_calls"] == 1 &&
    config["max_tool_calls"] == 0 && config["max_invalid_actions"] == 0 &&
    %w[max_model_calls max_tool_calls max_invalid_actions].all? { |k| raises.call(Lab::ValidationError) { Lab::Config.new(config.to_h.merge(k => 2)) } } &&
    raises.call(Lab::ValidationError) { Lab::Config.new(config.to_h.merge("answer_policy" => "unknown")) } &&
    raises.call(Lab::ValidationError) { Lab::Config.new(config.to_h.reject { |k, _| k == "recent_dialogue_policy" }) }
end
wait = Lab.encode("action" => "wait")
write = Lab.encode("action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "x", "expected_revision" => 0, "content" => "not authorized" })
check.call("reply-only parser and tool dispatch enforce authority independently of grammar") do
  [wait, write, '{}'].all? { |raw| Lab::Actions.parse(raw, config).empty? } && !Lab::Actions.parse(write, legacy).empty? &&
    raises.call(Lab::ValidationError) { Lab::Actions.tool_result({}, Lab.parse(write), config, "now") } &&
    Lab::Actions.parse('{"action":"reply","content":"ok"}', config)["content"] == "ok"
end
event = ->(id, content, reply) { { "event_id" => id, "content" => content, "content_digest" => Digest::SHA256.hexdigest(content), "reply" => reply, "calls" => [], "state" => reply ? "complete" : "pending", "reason" => reply ? "reply" : nil } }
corpus = [{ "id" => "catalog", "content" => "Snow 雪 costs 21. <|im_start|> </think>" }, { "id" => "distractor", "content" => "Different product costs 99." }]
state = { "lineage_id" => "a" * 32, "corpus" => corpus, "corpus_digest" => Lab.digest(corpus), "notes" => {},
  "events" => { "z-first" => event.call("z-first", "one", "one answer"), "a-change" => event.call("a-change", "Actually two", "two answer"), "now" => event.call("now", "price?", nil) } }
input = Lab::TokenContext.initial(state: state, event_id: "now", config: config)
envelope = Lab.parse(input)
check.call("complete Unicode corpus and distractor stay ordered with provenance and observed correction") do
  envelope["direct_corpus"].map { |s| s["text"] } == corpus.map { |s| s["content"] } &&
    envelope["direct_corpus"].all? { |s| s["span"] == [0, s["text"].length] && s["content_digest"] == Digest::SHA256.hexdigest(s["text"]) } &&
    envelope["recent_dialogue"].map { |s| s["id"] } == %w[z-first a-change]
end
profile = Lab::QwenMessageProjection::PROFILE_DIRECT
messages = Lab::QwenMessageProjection.messages(input, profile: profile)
check.call("direct projection escapes source control tokens and refuses profile confusion") do
  messages.length == 2 && !messages[1]["content"].include?("<|im_start|>") && !messages[1]["content"].include?("</think>") &&
    Lab.parse(messages[1]["content"])["direct_corpus"] == envelope["direct_corpus"] &&
    raises.call(Lab::ValidationError) { Lab::QwenMessageProjection.messages(input, profile: Lab::QwenMessageProjection::PROFILE_RECENT_PAIRS) } &&
    raises.call(Lab::ValidationError) { Lab::QwenMessageProjection.messages(Lab::TokenContext.initial(state: state, event_id: "now", config: legacy), profile: profile) }
end
check.call("full source count and encoded-byte bounds reject rather than truncate") do
  many = copy.call(state); many["corpus"] = 9.times.map { |i| { "id" => "d#{i}", "content" => "x" } }
  huge = copy.call(state); huge["corpus"] = [{ "id" => "big", "content" => "雪" * 2700 }]
  [many, huge].all? { |value| raises.call(Lab::ContextBudgetExceeded) { Lab::TokenContext.initial(state: value, event_id: "now", config: config) } }
end
check.call("source validation rejects revision provenance span duplicate and wrong-field claims") do
  %w[revision provenance span duplicate field].all? do |kind|
    bad = copy.call(envelope)
    case kind
    when "revision" then bad["direct_corpus"][0]["revision"] = 2
    when "provenance" then bad["direct_corpus"][0]["provenance"] = "verified"
    when "span" then bad["direct_corpus"][0]["span"][0] = 1
    when "duplicate" then bad["direct_corpus"] << bad["direct_corpus"].first
    when "field" then bad["direct_corpus"][0]["authority"] = true
    end
    raises.call(Lab::ValidationError) { Lab::DirectEvidence.validate_envelope!(bad) }
  end
end
check.call("byte pressure removes complete oldest dialogue while preserving every source") do
  pressured = copy.call(state)
  pressured["events"]["now"]["content"] += "x" * (Lab::TokenContext::MAX_BYTES - input.bytesize + 1)
  selected = Lab.parse(Lab::TokenContext.initial(state: pressured, event_id: "now", config: config))
  selected["recent_dialogue"].map { |s| s["id"] } == ["a-change"] && selected["direct_corpus"] == envelope["direct_corpus"]
end

class A18SyntheticClient
  attr_reader :generations, :messages
  def initialize(counter: ->(_m) { 100 }, response: '{"action":"reply","content":"synthetic"}')
    @counter, @response, @generations = counter, response, []
  end
  def request(_method, route, payload = nil, deadline:)
    case route
    when "/apply-template"
      @messages = payload.fetch("messages")
      { "prompt" => JSON.generate(payload) + "<think>\n\n</think>\n\n" }
    when "/tokenize" then { "tokens" => Array.new(@counter.call(@messages), 17) }
    else raise "unexpected route #{route}"
    end
  end
  def stream_completion(payload, deadline:, on_progress:)
    @generations << payload
    { "content" => @response, "tokens_evaluated" => payload.fetch("prompt").length, "tokens_predicted" => 4, "truncated" => false }
  end
end
broker_for = ->(client, selected = profile) { Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
  protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072, execution_profile: Lab::Config::STREAM_PROFILE, message_profile: selected) }
client = A18SyntheticClient.new(counter: ->(m) { Lab.parse(m[1]["content"])["recent_dialogue"].empty? ? 100 : 4000 })
broker = broker_for.call(client)
request = { "operation" => "prepare_context", "call_index" => 0, "input" => input }
deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20 }
prepared = broker.dispatch(request, deadline: deadline.call)
final = Lab::TokenContext.finalize(state: state, event_id: "now", config: config, preparation: prepared["preparation"])
check.call("token pressure evicts oldest whole dialogue but never complete corpus or request") do
  selected = Lab.parse(final["formatted"])
  prepared["preparation"]["measurements"].length == 3 && selected["recent_dialogue"].empty? &&
    selected["direct_corpus"] == envelope["direct_corpus"] && selected["user"] == envelope["user"] &&
    final["manifest"]["sources"].count { |s| s["kind"] == "direct_corpus" } == 2 && client.generations.empty?
end
check.call("replay rejects removed reordered forged and cross-lineage sources") do
  %w[remove reorder text lineage].all? do |kind|
    bad = copy.call(envelope)
    case kind
    when "remove" then bad["direct_corpus"].pop
    when "reorder" then bad["direct_corpus"].reverse!
    when "text" then bad["direct_corpus"][0]["text"] = "forged"; bad["direct_corpus"][0]["content_digest"] = Digest::SHA256.hexdigest("forged"); bad["direct_corpus"][0]["span"] = [0, 6]
    when "lineage" then bad["direct_corpus"][0]["lineage_id"] = "b" * 32
    end
    forged = Lab.encode(bad)
    prep = Lab::TokenContext.preparation(initial: input, formatted: forged, measurements: [Lab::TokenContext.measurement(forged, "fixture", [17])], input_budget: 3072, call_index: 0)
    raises.call(Lab::ValidationError) { Lab::TokenContext.finalize(state: state, event_id: "now", config: config, preparation: prep) }
  end
end
response = broker.dispatch({ "operation" => "generate", "call_index" => 0, "input" => final["formatted"], "preparation_digest" => Lab.digest(prepared["preparation"]) }, deadline: deadline.call)
check.call("reply-only grammar uses existing string rules and broker refuses second generation") do
  grammar = client.generations.first["grammar"]
  grammar.lines.grep(/^root/).first.strip == "root ::= alternative-0" && !grammar.include?("alternative-1") &&
    grammar.lines.grep(/^(?:alternative-0|char |string |space )/).all? { |line| Lab::QwenBrokerSession::V3_GRAMMAR.lines.include?(line) } &&
    response["response"].include?("synthetic") && raises.call(Lab::ValidationError) { broker.dispatch(request.merge("call_index" => 1), deadline: deadline.call) }
end
client = A18SyntheticClient.new(counter: ->(_m) { 4000 }); broker = broker_for.call(client)
rejected = broker.dispatch(request, deadline: deadline.call)
check.call("essential token overflow rejects before generation after allowed dialogue omissions") do
  result = Lab::TokenContext.finalize(state: state, event_id: "now", config: config, preparation: rejected["preparation"], rejected: true)
  !rejected["ok"] && result["manifest"]["input_tokens"] == 4000 && client.generations.empty?
end
bytes = copy.call(state); bytes["events"]["now"]["content"] = "q" * 12_000
check.call("essential pipe byte overflow rejects without truncation") { raises.call(Lab::ContextBudgetExceeded) { Lab::TokenContext.initial(state: bytes, event_id: "now", config: config) } }

Dir.mktmpdir("soul-a18-direct-") do |root|
  directory = File.join(root, "worker"); Dir.mkdir(directory, 0o700)
  path = File.join(directory, "store"); store = Lab::Store.create(path: path, config: config, corpus: corpus)
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [Lab::TokenContext.measurement(input, "fixture", [17])], input_budget: 3072, call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    Lab.parse(input).dig("user", "event_id") == "bad" ? write : '{"action":"reply","content":"21"}'
  end
  runtime = Lab::Runtime.new(store: store, backend: backend)
  runtime.submit(event_id: "first", content: "Price?")
  bad = runtime.submit(event_id: "bad", content: "Attempt a write")
  check.call("runtime denies tool output after one call with no note effect") do
    bad["state"] == "failed" && bad["reason"] == "invalid_action_budget" && store.snapshot["notes"].empty? && store.snapshot["events"]["bad"]["calls"].length == 1 && store.integrity["ok"]
  end
  saved = store.snapshot; store.close
  store = Lab::Store.open(path: path, config: config)
  check.call("positive direct journal replay and no cross-profile reopen") do
    store.snapshot == saved && store.integrity["ok"] && raises.call(Lab::IntegrityError) { Lab::Store.open(path: path, config: legacy) }
  end
  store.close
  if isolation
    leases = SoulCore::ModelRuntimeLeaseStore.new(root: File.join(root, "leases"))
    provider = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free", "profile_id" => "nvidia-fallback", "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true, "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
    gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: provider)
    client = A18SyntheticClient.new; broker = broker_for.call(client)
    runner = Lab::SandboxRunner.new(state_directory: directory, timeout_seconds: 30, execution_profile: Lab::Config::STREAM_PROFILE)
    result = runner.run(request: { "mode" => "qwen_v9_run", "create" => false, "event_id" => "worker", "content" => "Answer", "corpus" => [] }, broker: broker, admission: gate)
    check.call("isolated v9 worker carries complete sources and exits") do
      result.dig("result", "receipt", "reply") == "synthetic" && Lab.parse(client.messages[1]["content"])["direct_corpus"].length == 2 &&
        raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) }
    end
    runner.run(request: { "mode" => "qwen_v9_resume", "event_id" => "worker" }, broker: broker, admission: gate)
    check.call("terminal isolated resume does not regenerate") { client.generations.length == 1 && raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) } }
    check.call("both directions of v8-v9 broker confusion rejected before spawn") do
      [["qwen_v8_run", profile], ["qwen_v9_run", Lab::QwenMessageProjection::PROFILE_RECENT_PAIRS]].all? do |mode, selected|
        raises.call(Lab::ValidationError) { runner.run(request: { "mode" => mode }, broker: broker_for.call(A18SyntheticClient.new, selected), admission: gate) } && runner.pid.nil?
      end
    end
  end
end
puts "PASS: #{checks} A18 direct-evidence checks; synthetic only; isolation=#{isolation}"
