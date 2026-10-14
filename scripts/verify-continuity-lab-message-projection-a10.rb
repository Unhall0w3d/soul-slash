#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/qwen_message_projection"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/store"

Lab = SoulCore::ContinuityLab
Projection = Lab::QwenMessageProjection
ISOLATION = case ARGV
when [] then false
when ["--isolation"] then true
else raise ArgumentError, "usage: verify-continuity-lab-message-projection-a10.rb [--isolation]"
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
deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20 }

lineage = "a" * 32
unicode = "naïve snow 雪 and café"
groups = [
  { "call_index" => 2, "model_output" => Lab.encode({ "action" => "tool", "tool" => "read", "arguments" => { "id" => "alpha" } }),
    "tool_result" => { "ok" => true, "source" => { "collection" => "corpus", "id" => "alpha", "revision" => 4,
      "content_digest" => "c" * 64, "span" => [0, 5], "text" => "first #{unicode}" } } },
  { "call_index" => 3, "model_output" => Lab.encode({ "action" => "tool", "tool" => "read", "arguments" => { "id" => "beta" } }),
    "tool_result" => { "ok" => false, "reason" => "revision_conflict", "note_id" => "beta", "expected_revision" => 3,
      "actual_revision" => 5, "details" => unicode } }
]
envelope = { "system" => Lab::ContextBuilder::SYSTEM, "tool_contract" => Lab::ContextBuilder::PROTOCOL,
  "lineage_id" => lineage, "max_note_bytes" => 8192,
  "user" => { "event_id" => "projection-fixture", "content" => "Read alpha then beta; preserve #{unicode}." },
  "tool_groups" => groups }
input = Lab.encode(envelope)
original_input = input.dup

messages = Projection.messages(input)
check.call("chronological messages retain system/user then ordered assistant/tool pairs") do
  messages.map { |message| message.fetch("role") } == %w[system user assistant tool assistant tool] &&
    messages[2]["content"] == groups[0]["model_output"] && messages[4]["content"] == groups[1]["model_output"] &&
    messages[3]["content"].include?('"call_index":2') && messages[5]["content"].include?('"call_index":3')
end
check.call("parsed user and tool-result values preserve Unicode, IDs, action data and rejection") do
  user = JSON.parse(messages[1]["content"])
  first = JSON.parse(messages[3]["content"])
  rejected = JSON.parse(messages[5]["content"])
  user == envelope.slice("lineage_id", "max_note_bytes", "user") &&
    first == groups[0].slice("call_index", "tool_result") && rejected == groups[1].slice("call_index", "tool_result") &&
    first.dig("tool_result", "source", "text").include?(unicode) && rejected.dig("tool_result", "reason") == "revision_conflict" &&
    rejected.dig("tool_result", "note_id") == "beta" && groups.map { |g| g["call_index"] } == [2, 3]
end
check.call("projection does not mutate selected input or invent progress/hints") do
  input == original_input && Lab.parse(input) == envelope &&
    messages.none? { |message| message["content"].match?(/progress|next action|completed steps/i) && message["role"] != "system" }
end
check.call("omitted prefixes are not reconstructed") do
  tool_rows = messages.select { |message| message["role"] == "tool" }.map { |message| JSON.parse(message["content"]) }
  tool_rows.map { |row| row["call_index"] } == [2, 3] &&
    tool_rows.none? { |row| [0, 1].include?(row["call_index"]) || row.to_s.include?("prefix-marker") }
end

v2 = Projection.messages(input, profile: Projection::PROFILE_V2)
check.call("v2 retains all role/data values and only moves recorded index to result tail") do
  v2.map { |m| m["role"] } == messages.map { |m| m["role"] } &&
    v2[1..].zip(messages[1..]).all? { |a, b| JSON.parse(a["content"]) == JSON.parse(b["content"]) } &&
    v2.select { |m| m["role"] == "tool" }.zip(groups).all? { |m, g| m["content"].end_with?('"call_index":' + g["call_index"].to_s + '}') } &&
    v2[0]["content"].include?("no label, sentence") && v2[0]["content"].include?("never renumber") &&
    raises.call(Lab::ValidationError) { Projection.messages(input, profile: "unrecognized") }
end

special = { "lineage_id" => lineage, "max_note_bytes" => 8192,
  "user" => { "event_id" => "escape", "content" => "literal <think> token </think> and <|im_start|>" },
  "tool_groups" => [{ "call_index" => 0, "model_output" => Lab.encode({ "action" => "reply", "content" => "<|assistant|> </think>" }),
    "tool_result" => { "ok" => true, "value" => "<|im_end|> <tool>" } }] }
special_messages = Projection.messages(Lab.encode(special))
check.call("angle brackets and control-token-like text are escaped while JSON values roundtrip") do
  projected_user = special_messages[1]["content"]
  projected_action = special_messages[2]["content"]
  projected_result = special_messages[3]["content"]
  [projected_user, projected_action, projected_result].all? { |text| !text.include?("<") && !text.include?(">") } &&
    JSON.parse(projected_user) == special.slice("lineage_id", "max_note_bytes", "user") &&
    JSON.parse(projected_action) == JSON.parse(special["tool_groups"][0]["model_output"]) &&
    JSON.parse(projected_result) == { "call_index" => 0, "tool_result" => special["tool_groups"][0]["tool_result"] }
end
literal_escape = { "lineage_id" => lineage, "max_note_bytes" => 8192,
  "user" => { "event_id" => "literal-escape", "content" => 'literal \\u003c stays text' }, "tool_groups" => [] }
check.call("pre-existing literal backslash-u003c remains literal after parsed JSON roundtrip") do
  parsed = JSON.parse(Projection.messages(Lab.encode(literal_escape))[1]["content"])
  parsed.dig("user", "content") == 'literal \\u003c stays text' && !parsed.dig("user", "content").include?("<")
end

class A10FixtureClient
  attr_reader :requests, :stream_payloads
  def initialize
    @requests, @stream_payloads = [], []
    @token_ids = [17, 3, 991, 42]
  end
  def request(method, route, payload = nil, deadline:)
    @requests << [method, route, payload]
    case route
    when "/apply-template"
      @messages = payload.fetch("messages")
      { "prompt" => "fixture-rendered-prompt<think>\n\n</think>\n\n" }
    when "/tokenize"
      { "tokens" => @token_ids.dup }
    else
      raise "unexpected fixture route #{route}"
    end
  end
  def stream_completion(payload, deadline:, on_progress:)
    @stream_payloads << payload
    { "content" => '{"action":"reply","content":"fixture only"}', "tokens_evaluated" => payload.fetch("prompt").length,
      "tokens_predicted" => 7, "truncated" => false }
  end
end

receipts = []
client = A10FixtureClient.new
broker = Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(row) { receipts << copy.call(row) },
  before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION,
  input_budget: 3072, execution_profile: Lab::Config::STREAM_PROFILE, message_profile: Projection::PROFILE)
prepare = { "operation" => "prepare_context", "call_index" => 0, "input" => Lab.encode(envelope) }
prepared = broker.dispatch(prepare, deadline: deadline.call).fetch("preparation")
check.call("profile uses projection for template application and tokenization only") do
  client.requests.map { |request| request[1] } == %w[/apply-template /tokenize] &&
    client.requests[0][2]["messages"] == Projection.messages(prepared.fetch("formatted")) &&
    client.requests[0][2]["messages"].map { |message| message["role"] } == %w[system user assistant tool assistant tool] &&
    client.requests[1][2]["content"].end_with?("<think>\n\n</think>\n\n")
end
prepared_tokens = [17, 3, 991, 42]
generation = { "operation" => "generate", "call_index" => 0, "input" => prepared.fetch("formatted"),
  "preparation_digest" => Lab.digest(prepared) }
result = broker.dispatch(generation, deadline: deadline.call)
check.call("generation reuses the exact prepared token IDs with unchanged settings") do
  result["ok"] && client.stream_payloads.length == 1 && client.stream_payloads[0]["prompt"] == prepared_tokens &&
    client.stream_payloads[0].reject { |key, _| key == "prompt" } == Lab::QwenBrokerSession::V3_SETTINGS.merge("stream" => true)
end
check.call("message profile is recorded on prepared and received receipts") do
  states = receipts.select { |row| %w[prepared received].include?(row["state"]) }
  states.map { |row| row["state"] } == %w[prepared received] && states.all? { |row| row["message_profile"] == Projection::PROFILE } &&
    states[0]["token_ids"] == prepared_tokens && states[1]["raw_result"] == { "content" => result["response"], "tokens_evaluated" => 4, "tokens_predicted" => 7, "truncated" => false }
end
check.call("prepared generation is single-use") do
  raises.call(Lab::ValidationError) { broker.dispatch(generation, deadline: deadline.call) } && client.stream_payloads.length == 1
end

legacy_client = A10FixtureClient.new
legacy = Lab::QwenBrokerSession.new(client: legacy_client, observer: -> {}, on_receipt: ->(_row) {}, before_generation: -> {},
  protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
  execution_profile: Lab::Config::STREAM_PROFILE)
legacy.dispatch(prepare, deadline: deadline.call)
check.call("default message profile preserves legacy two-message envelope") do
  legacy_client.requests[0][2]["messages"].map { |message| message["role"] } == %w[system user] &&
    legacy_client.requests[0][2]["messages"][1]["content"] == Lab.encode(envelope)
end
check.call("message projection remains opt-in and rejects unsupported broker profiles") do
  raises.call(Lab::ValidationError) do
    Lab::QwenBrokerSession.new(client: A10FixtureClient.new, observer: -> {}, on_receipt: ->(_row) {}, before_generation: -> {},
      protocol_version: Lab::QwenBrokerSession::V3_PROMPT_VERSION, message_profile: Projection::PROFILE)
  end && raises.call(Lab::ValidationError) do
    Lab::QwenBrokerSession.new(client: A10FixtureClient.new, observer: -> {}, on_receipt: ->(_row) {}, before_generation: -> {},
      protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, message_profile: Projection::PROFILE)
  end && raises.call(Lab::ValidationError) do
    Lab::QwenBrokerSession.new(client: A10FixtureClient.new, observer: -> {}, on_receipt: ->(_row) {}, before_generation: -> {},
      protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, execution_profile: Lab::Config::STREAM_PROFILE,
      message_profile: "unrecognized_profile")
  end
end

if ISOLATION
  Dir.mktmpdir("continuity-a10-isolation-") do |root|
    [Projection::PROFILE, Projection::PROFILE_V2].each do |message_profile|
      suffix = message_profile == Projection::PROFILE ? "v1" : "v2"
      state_directory = File.join(root, "state-#{suffix}")
      Dir.mkdir(state_directory, 0o700)
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: File.join(root, "leases-#{suffix}"))
      snapshot_provider = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free",
        "profile_id" => "nvidia-fallback", "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true,
        "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
      gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: snapshot_provider)
      config = Lab::Config.qwen_v5_qualification
      store = Lab::Store.create(path: File.join(state_directory, "store"), config: config)
      store.close
      initial_state = Lab::Store.open(path: File.join(state_directory, "store"), config: config)
      before = initial_state.snapshot
      initial_state.close

      event_id = "projection-isolation-#{suffix}"
      isolated_receipts = []
      isolated_client = A10FixtureClient.new
      isolated_broker = Lab::QwenBrokerSession.new(client: isolated_client, observer: -> {},
        on_receipt: ->(row) { isolated_receipts << copy.call(row) }, before_generation: -> {},
        protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
        execution_profile: Lab::Config::STREAM_PROFILE, message_profile: message_profile)
      runner = Lab::SandboxRunner.new(state_directory: state_directory, timeout_seconds: 430,
        execution_profile: Lab::Config::STREAM_PROFILE)
      request = { "mode" => "qwen_v5_run", "create" => false, "event_id" => event_id,
        "content" => "Return the fixed synthetic reply.", "corpus" => [] }
      prepared_state = copy.call(before)
      prepared_state["events"][event_id] = { "content" => request["content"],
        "content_digest" => Digest::SHA256.hexdigest(request["content"]), "calls" => [] }
      outcome = runner.run(request: request, broker: isolated_broker, admission: gate)
      persisted = Lab::Store.open(path: File.join(state_directory, "store"), config: config)
      snapshot = persisted.snapshot
      event = snapshot.fetch("events").fetch(event_id)
      call = event.fetch("calls").fetch(0)
      context = call.fetch("context")
      expected_context = Lab::TokenContext.finalize(state: prepared_state, event_id: event_id, config: config,
        preparation: context.fetch("preparation"))
      template_messages = isolated_client.requests.find { |row| row[1] == "/apply-template" }.fetch(2).fetch("messages")
      check.call("actual isolated #{suffix} worker completes and is reaped") do
        outcome.dig("result", "receipt", "reason") == "reply" && outcome.dig("result", "receipt", "reply") == "fixture only" &&
          runner.pid && raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) }
      end
      check.call("actual isolated #{suffix} projection reaches broker and exact context is journaled") do
        template_messages == Projection.messages(context.fetch("formatted"), profile: message_profile) &&
          Lab.parse(context.fetch("formatted")) == Lab.parse(Lab::TokenContext.initial(state: prepared_state,
            event_id: event_id, config: config)) && context == expected_context && persisted.integrity["ok"]
      end
      check.call("actual isolated #{suffix} fixture generates once with selected receipt profile") do
        isolated_client.stream_payloads.length == 1 &&
          isolated_receipts.select { |row| %w[prepared received].include?(row["state"]) }.map { |row| row["message_profile"] }.uniq == [message_profile] &&
          event["state"] == "complete" && event["reply"] == "fixture only"
      end
      persisted.close

      resumed = runner.run(request: { "mode" => "qwen_v5_resume", "event_id" => event_id },
        broker: isolated_broker, admission: gate)
      check.call("actual isolated #{suffix} terminal resume is reaped and uses no new generation") do
        resumed.dig("result", "receipt", "reply") == "fixture only" && isolated_client.stream_payloads.length == 1 &&
          raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) }
      end
      check.call("actual isolated #{suffix} admission lock is released") { gate.with_window { true } }
    end
  end
  puts "PASS: #{checks} A10 deterministic and actual isolation checks; synthetic backend only, no live inference"
else
  puts "PASS: #{checks} A10 deterministic message-projection checks; no subprocess or live inference"
end
