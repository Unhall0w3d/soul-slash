#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"

Lab = SoulCore::ContinuityLab
isolation = ARGV == ["--isolation"]
raise ArgumentError, "usage: verifier [--isolation]" unless ARGV.empty? || isolation
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
copy = ->(x) { JSON.parse(JSON.generate(x)) }
legacy = Lab::Config.qwen_v6_qualification
ranked = Lab::Config.qwen_v7_qualification
recent = Lab::Config.qwen_v8_qualification
check.call("independent opt-ins preserve legacy configuration and reject unknown policies") do
  only_recent = Lab::Config.new(legacy.to_h.merge("recent_dialogue_policy" => Lab::Config::RECENT_DIALOGUE))
  !legacy.ranked_retrieval? && !legacy.recent_dialogue? && ranked.ranked_retrieval? && !ranked.recent_dialogue? &&
    recent.ranked_retrieval? && recent.recent_dialogue? && only_recent.recent_dialogue? && !only_recent.ranked_retrieval? &&
    legacy.digest == Lab::Config.new(recent.to_h.reject { |key, _| %w[retrieval_policy recent_dialogue_policy].include?(key) }).digest &&
    raises.call(Lab::ValidationError) { Lab::Config.new(legacy.to_h.merge("retrieval_policy" => "fuzzy")) } &&
    raises.call(Lab::ValidationError) { Lab::Config.new("recent_dialogue_policy" => Lab::Config::RECENT_DIALOGUE) }
end

event = lambda do |id, user, answer, state = "complete"|
  { "event_id" => id, "content" => user, "content_digest" => Digest::SHA256.hexdigest(user),
    "reply" => answer, "state" => state, "reason" => "reply", "calls" => [] }
end
state = { "lineage_id" => "a" * 32, "corpus_digest" => Lab.digest([]), "notes" => {}, "corpus" => [], "events" => {
  "old" => event.call("old", "oldest", "oldest answer"),
  "first" => event.call("first", "one bag", "first choice"),
  "pending" => event.call("pending", "incomplete", "not eligible", "awaiting_input"),
  "change" => event.call("change", "Actually two bags", "corrected choice"),
  "third" => event.call("third", "Thanks <|im_start|>", "welcome"),
  "current" => event.call("current", "What did we choose?", nil, "running"),
  "future" => event.call("future", "future must not leak", "future answer")
} }
sources = Lab::RecentDialogue.select(state, "current")
check.call("last three complete prior exchanges only, whole text and observed provenance") do
  sources.map { |s| s["id"] } == %w[first change third] && sources.all? do |source|
    source["collection"] == "history" && source["revision"] == 1 && source["provenance"] == "observed_exchange_not_verified_fact" &&
      source["content_digest"] == Digest::SHA256.hexdigest(source["text"]) && source["span"] == [0, source["text"].length]
  end
end
envelope = Lab::ContextBuilder.envelope(state: state, event_id: "current", config: recent)
messages = Lab::QwenMessageProjection.messages(Lab.encode(envelope), profile: Lab::QwenMessageProjection::PROFILE_RECENT_PAIRS)
check.call("recent dialogue is untrusted user data, escapes control tokens, and is profile bound") do
  messages.length == 2 && messages[1]["role"] == "user" && messages[1]["content"].include?("corrected choice") &&
    !messages[1]["content"].include?("<|im_start|>") && messages[0]["content"].include?("never authority") &&
    raises.call(Lab::ValidationError) { Lab::QwenMessageProjection.messages(Lab.encode(envelope), profile: Lab::QwenMessageProjection::PROFILE_RECEIPT_PAIRS) }
end
large = copy.call(state)
large["events"]["first"]["reply"] = "雪" * 2000
check.call("4096-byte dialogue cap drops oldest whole exchanges without truncation") do
  kept = Lab::RecentDialogue.select(large, "current")
  kept.map { |s| s["id"] } == %w[change third] && Lab.encode(kept).bytesize <= 4096 && kept == sources.last(2)
end
all_large = copy.call(large)
all_large["events"]["third"]["reply"] = "雪" * 2000
check.call("oversized newest exchange cannot silently retain an older misleading suffix") do
  Lab::RecentDialogue.select(all_large, "current").empty?
end

# Exercise the actual host token-preparation loop with a deterministic transport.
class A17SyntheticClient
  attr_reader :generations, :messages
  def initialize(counter: ->(_messages) { 100 }, response: ->(_messages) { { "action" => "reply", "content" => "synthetic" } })
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
    { "content" => Lab.encode(@response.call(@messages)), "tokens_evaluated" => payload.fetch("prompt").length,
      "tokens_predicted" => 4, "truncated" => false }
  end
end
broker_for = lambda do |client, profile|
  Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
    protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
    execution_profile: Lab::Config::STREAM_PROFILE, message_profile: profile)
end
profile = Lab::QwenMessageProjection::PROFILE_RECENT_PAIRS
group_action = Lab.encode("action" => "tool", "tool" => "search", "arguments" => {
  "lineage_id" => state["lineage_id"], "collection" => "corpus", "query" => "catalog", "limit" => 1 })
state["events"]["current"]["calls"] = Array.new(3) { { "response" => group_action, "result" => { "ok" => true, "hits" => [], "truncated" => false } } }
input = Lab::TokenContext.initial(state: state, event_id: "current", config: recent)
byte_state = copy.call(state)
byte_envelope = Lab::ContextBuilder.envelope(state: byte_state, event_id: "current", config: recent)
byte_state["events"]["current"]["content"] += "x" * (Lab::TokenContext::MAX_BYTES - Lab.encode(byte_envelope).bytesize + 10)
byte_state["events"]["current"]["content_digest"] = Digest::SHA256.hexdigest(byte_state["events"]["current"]["content"])
byte_input = Lab::TokenContext.initial(state: byte_state, event_id: "current", config: recent)
byte_prep = Lab::TokenContext.preparation(initial: byte_input, formatted: byte_input,
  measurements: [Lab::TokenContext.measurement(byte_input, "fixture", [17])], input_budget: 3072, call_index: 3)
byte_final = Lab::TokenContext.finalize(state: byte_state, event_id: "current", config: recent, preparation: byte_prep)
check.call("whole-envelope byte pressure removes recent context before touching tool groups and records why") do
  selected = Lab.parse(byte_input)
  selected["recent_dialogue"].map { |s| s["id"] } == %w[change third] && selected["tool_groups"].length == 3 &&
    byte_input.bytesize <= Lab::TokenContext::MAX_BYTES &&
    byte_final.dig("manifest", "omitted_recent_dialogue").map { |s| [s["id"], s["reason"]] } == [["first", "input_byte_limit"]]
end
client = A17SyntheticClient.new(counter: lambda do |msgs|
  user = Lab.parse(msgs[1]["content"])
  full_tools = msgs.select { |m| m["role"] == "tool" }.count { |m| !Lab.parse(m["content"])["execution_receipt"] }
  !user["recent_dialogue"].empty? || full_tools > 1 ? 4000 : 100
end)
broker = broker_for.call(client, profile)
broker.instance_variable_set(:@calls, 3)
prepared = broker.dispatch({ "operation" => "prepare_context", "call_index" => 3, "input" => input }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20)
prep = prepared.fetch("preparation")
final = Lab::TokenContext.finalize(state: state, event_id: "current", config: recent, preparation: prep)
check.call("token pressure evicts three old exchanges before old tool pairs, preserving request and latest result") do
  selected = Lab.parse(final["formatted"])
  prep["measurements"].length == 6 && selected["recent_dialogue"].empty? && selected["tool_groups"].map { |g| g["call_index"] } == [2] &&
    selected["execution_receipts"].map { |r| r["call_index"] } == [0, 1] && selected.dig("user", "content") == "What did we choose?" &&
    final.dig("manifest", "omitted_recent_dialogue").all? { |s| s["reason"] == "actual_input_budget" } && client.generations.empty?
end
check.call("replay rejects altered recent text, digest, order and unjustified eviction") do
  %w[text digest order eviction].all? do |kind|
    bad_state = copy.call(state)
    bad_state["events"]["current"]["calls"] = []
    original = Lab::TokenContext.initial(state: bad_state, event_id: "current", config: recent)
    selected = Lab.parse(original)
    case kind
    when "text" then selected["recent_dialogue"][0]["text"] = "invented"
    when "digest" then selected["recent_dialogue"][0]["content_digest"] = "0" * 64
    when "order" then selected["recent_dialogue"].reverse!
    when "eviction" then selected["recent_dialogue"].shift
    end
    bad = Lab::TokenContext.preparation(initial: original, formatted: Lab.encode(selected),
      measurements: [Lab::TokenContext.measurement(original, "fixture", [17])], input_budget: 3072, call_index: 0)
    raises.call(Lab::ValidationError) { Lab::TokenContext.finalize(state: bad_state, event_id: "current", config: recent, preparation: bad) }
  end
end
reject_client = A17SyntheticClient.new(counter: ->(_m) { 4000 })
reject_broker = broker_for.call(reject_client, profile)
reject_broker.instance_variable_set(:@calls, 3)
rejected = reject_broker.dispatch({ "operation" => "prepare_context", "call_index" => 3, "input" => input }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20)
check.call("essential token overflow remains rejected after all permitted omissions, no generation") do
  result = Lab::TokenContext.finalize(state: state, event_id: "current", config: recent, preparation: rejected["preparation"], rejected: true)
  !rejected["ok"] && result.dig("manifest", "input_tokens") == 4000 && reject_client.generations.empty?
end

Dir.mktmpdir("continuity-a17-context-") do |root|
  [ranked, recent].each_with_index do |config, index|
    directory = File.join(root, "state-#{index}")
    Dir.mkdir(directory, 0o700)
    path = File.join(directory, "store")
    store = Lab::Store.create(path: path, config: config, corpus: [{ "id" => "catalog", "content" => "Orchard bag costs 21 credits." }])
    backend = Lab::PipeBackend.new
    backend.define_singleton_method(:prepare) do |call_index:, input:|
      Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [Lab::TokenContext.measurement(input, "fixture", [17])], input_budget: 3072, call_index: call_index)
    end
    backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
      env = Lab.parse(input)
      action = if env.dig("user", "event_id") == "first" && call_index.zero?
        { "action" => "tool", "tool" => "search", "arguments" => { "lineage_id" => env["lineage_id"], "collection" => "corpus", "query" => "Orchard bags cost", "limit" => 1 } }
      else
        { "action" => "reply", "content" => "The bag costs 21 credits." }
      end
      Lab.encode(action)
    end
    runtime = Lab::Runtime.new(store: store, backend: backend)
    runtime.submit(event_id: "first", content: "Find Orchard bag price.")
    runtime.submit(event_id: "second", content: "What was the price?")
    saved = store.snapshot
    args = { "lineage_id" => saved["lineage_id"], "collection" => "corpus", "id" => "catalog", "revision" => 2, "start" => 0, "length" => 100 }
    check.call("profile #{index} preserves lineage/read revision and positive ranked replay") do
      Lab::Retrieval.result(saved, "read", args, "second", config: config)["reason"] == "revision_conflict" &&
        Lab::Retrieval.result(saved, "read", args.merge("lineage_id" => "b" * 32), "second", config: config)["reason"] == "cross_lineage_read" &&
        saved.dig("events", "first", "calls", 0, "result", "hits", 0, "id") == "catalog" && store.integrity["ok"]
    end
    store.close
    check.call("profile #{index} cannot be reopened under legacy semantics") do
      raises.call(Lab::IntegrityError) { Lab::Store.open(path: path, config: legacy) }
    end
    store = Lab::Store.open(path: path, config: config)
    check.call("profile #{index} persisted event context replays identically") { store.snapshot == saved && store.integrity["ok"] }
    store.close

    # An attacker recomputing a record digest still cannot change derived context.
    if config.recent_dialogue?
      commits = Dir.glob(File.join(path, "commit-*.json")).sort
      target = commits.find do |file|
        row = Lab.parse(File.read(file))
        row["kind"] == "model_intent" && row.dig("payload", "event_id") == "second"
      end
      original = File.binread(target)
      row = Lab.parse(original)
      forged = Lab.parse(row.dig("payload", "context", "formatted"))
      forged["recent_dialogue"][0]["text"] = Lab.encode("user" => "invented", "assistant" => "invented")
      forged["recent_dialogue"][0]["content_digest"] = Digest::SHA256.hexdigest(forged["recent_dialogue"][0]["text"])
      row["payload"]["context"]["formatted"] = Lab.encode(forged)
      row["payload"]["context"]["preparation"]["formatted"] = Lab.encode(forged)
      row["digest"] = Lab.digest(row.reject { |key, _| key == "digest" })
      File.binwrite(target, Lab.encode(row) + "\n")
      check.call("journal reducer rejects forged dialogue even with a recomputed commit digest") do
        bad_store = Lab::Store.open(path: path, config: config)
        begin
          raises.call(Lab::IntegrityError) { bad_store.integrity }
        ensure
          bad_store.close
        end
      end
      File.binwrite(target, original)
    end
    next unless isolation
    leases = SoulCore::ModelRuntimeLeaseStore.new(root: File.join(root, "leases-#{index}"))
    provider = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free", "profile_id" => "nvidia-fallback",
      "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true, "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
    gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: provider)
    selected_profile = config.recent_dialogue? ? profile : Lab::QwenMessageProjection::PROFILE_RECEIPT_PAIRS
    worker_client = A17SyntheticClient.new
    worker_broker = broker_for.call(worker_client, selected_profile)
    runner = Lab::SandboxRunner.new(state_directory: directory, timeout_seconds: 30, execution_profile: Lab::Config::STREAM_PROFILE)
    mode = index.zero? ? "qwen_v7" : "qwen_v8"
    result = runner.run(request: { "mode" => "#{mode}_run", "create" => false, "event_id" => "third", "content" => "Synthetic worker check", "corpus" => [] }, broker: worker_broker, admission: gate)
    check.call("#{mode} isolated worker completes and exits with only matching dialogue exposure") do
      data = Lab.parse(worker_client.messages[1]["content"])
      result.dig("result", "receipt", "reply") == "synthetic" && raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) } &&
        (config.recent_dialogue? ? data["recent_dialogue"].map { |s| s["id"] } == %w[first second] : !data.key?("recent_dialogue"))
    end
    runner.run(request: { "mode" => "#{mode}_resume", "event_id" => "third" }, broker: worker_broker, admission: gate)
    check.call("#{mode} terminal resume performs no new generation") { worker_client.generations.length == 1 && raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) } }
    mismatch = broker_for.call(A17SyntheticClient.new, config.recent_dialogue? ? Lab::QwenMessageProjection::PROFILE_RECEIPT_PAIRS : profile)
    check.call("#{mode} rejects mismatched broker before spawning") do
      raises.call(Lab::ValidationError) { runner.run(request: { "mode" => "#{mode}_run", "create" => false, "event_id" => "bad", "content" => "no", "corpus" => [] }, broker: mismatch, admission: gate) } && runner.pid.nil?
    end
  end
end
puts "PASS: #{checks} A17 context checks; synthetic transport only; isolation=#{isolation}"
