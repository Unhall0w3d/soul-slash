#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/retrieval_guidance_a16"

Lab = SoulCore::ContinuityLab
Guide = Lab::RetrievalGuidanceA16
Projection = Lab::QwenMessageProjection
isolation = case ARGV
when [] then false
when ["--isolation"] then true
else raise ArgumentError, "usage: verify-continuity-lab-guidance-a16.rb [--isolation]"
end
checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
rejects = lambda do |&block|
  block.call
  false
rescue Lab::ValidationError
  true
end
copy = ->(value) { Lab.parse(Lab.encode(value)) }
deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20 }

class A16FixtureClient
  attr_reader :requests, :generations
  def initialize(oversize: false)
    @requests, @generations, @oversize = [], [], oversize
  end
  def request(method, path, payload = nil, deadline:)
    @requests << [method, path, payload, deadline]
    case path
    when "/apply-template"
      { "prompt" => Lab.encode(payload) + "<think>\n\n</think>\n\n" }
    when "/tokenize"
      # A deterministic synthetic tokenizer, not a Qwen token-count claim.
      rendered = Lab.parse(payload.fetch("content").delete_suffix("<think>\n\n</think>\n\n"))
      added = rendered.fetch("messages").first.fetch("content").end_with?(Guide::GUIDE)
      { "tokens" => Array.new(added ? (@oversize ? 3073 : 256) : 128, 17) }
    when "/health"
      { "status" => "ok" }
    else
      raise "unexpected fixture route #{path}"
    end
  end
  def stream_completion(payload, deadline:, on_progress:)
    @generations << payload
    on_progress.call({ "fixture" => true })
    { "content" => '{"action":"reply","content":"BLUE"}', "tokens_evaluated" => payload.fetch("prompt").length,
      "tokens_predicted" => 1, "truncated" => false }
  end
end

config = Lab::Config.qwen_v6_qualification
state = { "lineage_id" => "a" * 32, "corpus_digest" => "b" * 64,
  "events" => { "fixture" => { "content" => "Uppercase blue.",
    "content_digest" => Digest::SHA256.hexdigest("Uppercase blue."), "calls" => [] } } }
input = Lab::TokenContext.initial(state: state, event_id: "fixture", config: config)
payload = { "messages" => Projection.messages(input, profile: Projection::PROFILE_RECEIPT_PAIRS),
  "add_generation_prompt" => true, "chat_template_kwargs" => { "enable_thinking" => false } }
original = copy.call(payload)
raw, guided = A16FixtureClient.new, A16FixtureClient.new
baseline = Guide::Transport.new(client: raw, condition: "baseline")
candidate = Guide::Transport.new(client: guided, condition: "guided")
baseline.request("POST", "/apply-template", payload, deadline: deadline.call)
candidate.request("POST", "/apply-template", payload, deadline: deadline.call)
check.call("baseline preserves exact payload and candidate changes only the copied system message") do
  actual = guided.requests.first[2]
  raw.requests.first[2].equal?(payload) && payload == original && actual != payload &&
    actual.reject { |key, _| key == "messages" } == payload.reject { |key, _| key == "messages" } &&
    actual["messages"].drop(1) == payload["messages"].drop(1) &&
    actual["messages"][0] == payload["messages"][0].merge("content" => payload["messages"][0]["content"] + "\n" + Guide::GUIDE)
end
check.call("guide metadata is exact and contains no per-case facts") do
  candidate.metadata["guidance_sha256"] == Digest::SHA256.hexdigest(Guide::GUIDE) &&
    baseline.metadata["guidance_text"] == "" && baseline.metadata["guidance_sha256"] == Digest::SHA256.hexdigest("") &&
    Guide::GUIDE !~ /Marigold|Copperfield|Northstar|Nova|Orbit|hot chocolate|42 credits|50 credits/i
end
check.call("wrong condition, wrong projection and duplicate guide application are rejected") do
  bad = copy.call(payload)
  bad["messages"][0]["content"] = "different system"
  rejects.call { Guide::Transport.new(client: raw, condition: "unknown") } &&
    rejects.call { candidate.request("POST", "/apply-template", bad, deadline: deadline.call) } &&
    rejects.call { candidate.request("POST", "/apply-template", guided.requests.first[2], deadline: deadline.call) }
end
check.call("read-only host routes and streaming payload/callback pass through unchanged") do
  time = deadline.call
  request = { "prompt" => [17] }
  progress = []
  health = candidate.request("GET", "/health", nil, deadline: time)
  result = candidate.stream_completion(request, deadline: time, on_progress: ->(row) { progress << row })
  health == { "status" => "ok" } && guided.requests.last == ["GET", "/health", nil, time] &&
    guided.generations.last.equal?(request) && progress == [{ "fixture" => true }] && result["tokens_evaluated"] == 1
end

make_broker = lambda do |client, receipts|
  Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(row) { receipts << row },
    before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION,
    input_budget: 3072, execution_profile: Lab::Config::STREAM_PROFILE, message_profile: Projection::PROFILE_RECEIPT_PAIRS)
end
observed = {}
Guide::CONDITIONS.each do |condition|
  fixture = A16FixtureClient.new
  receipts = []
  broker = make_broker.call(Guide::Transport.new(client: fixture, condition: condition), receipts)
  prep = broker.dispatch({ "operation" => "prepare_context", "call_index" => 0, "input" => input }, deadline: deadline.call).fetch("preparation")
  request = { "operation" => "generate", "call_index" => 0, "input" => prep.fetch("formatted"), "preparation_digest" => Lab.digest(prep) }
  result = broker.dispatch(request, deadline: deadline.call)
  measured = receipts.find { |row| row["state"] == "context_measured" }
  generated = receipts.find { |row| row["state"] == "prepared" }
  observed[condition] = generated
  check.call("#{condition}: exact rendered prompt is tokenized, recorded and generated with frozen settings") do
    result["ok"] && prep["formatted"] == input && measured["prompt"] == fixture.requests[1][2]["content"] &&
      generated["prompt"] == measured["prompt"] && generated["prompt_sha256"] == Digest::SHA256.hexdigest(measured["prompt"]) &&
      generated["token_ids"] == fixture.generations.first["prompt"] && generated["input_tokens"] == (condition == "guided" ? 256 : 128) &&
      fixture.generations.first.reject { |key, _| key == "prompt" } == Lab::QwenBrokerSession::V3_SETTINGS.merge("stream" => true) &&
      rejects.call { broker.dispatch(request, deadline: deadline.call) }
  end
end
check.call("conditions retain identical source envelope but distinct measured prompts") do
  observed["baseline"]["envelope"] == observed["guided"]["envelope"] &&
    observed["baseline"]["prompt_sha256"] != observed["guided"]["prompt_sha256"]
end
large = A16FixtureClient.new(oversize: true)
broker = make_broker.call(Guide::Transport.new(client: large, condition: "guided"), [])
rejected = broker.dispatch({ "operation" => "prepare_context", "call_index" => 0, "input" => input }, deadline: deadline.call)
check.call("added guide counts toward existing input limit and cannot trigger generation when over budget") do
  rejected["ok"] == false && large.generations.empty? && broker.calls.zero? &&
    rejects.call { broker.dispatch({ "operation" => "generate", "call_index" => 0, "input" => input, "preparation_digest" => "x" }, deadline: deadline.call) }
end

if isolation
  pids = []
  Dir.mktmpdir("continuity-a16-isolation-") do |root|
    Guide::CONDITIONS.each do |condition|
      directory = File.join(root, condition)
      Dir.mkdir(directory, 0o700)
      path = File.join(directory, "store")
      store = Lab::Store.create(path: path, config: config, corpus: [])
      store.close
      fixture, receipts = A16FixtureClient.new, []
      broker = make_broker.call(Guide::Transport.new(client: fixture, condition: condition), receipts)
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: File.join(root, "leases"))
      snapshot = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free",
        "profile_id" => "nvidia-fallback", "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true,
        "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
      gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: snapshot)
      runner = Lab::SandboxRunner.new(state_directory: directory, timeout_seconds: 30, execution_profile: Lab::Config::STREAM_PROFILE)
      result = runner.run(request: { "mode" => "qwen_v6_run", "create" => false, "event_id" => "fixture", "content" => "Uppercase blue.", "corpus" => [] }, broker: broker, admission: gate)
      store = Lab::Store.open(path: path, config: config)
      event = store.snapshot.fetch("events").fetch("fixture")
      pid = result.fetch("worker_pid")
      check.call("#{condition}: actual isolated worker exits, journal replays, and broker evidence matches") do
        event["state"] == "complete" && event["reason"] == "reply" && event["reply"] == "BLUE" &&
          result.dig("result", "receipt") == event.slice("event_id", "state", "reason", "reply") &&
          store.integrity["ok"] && !File.exist?("/proc/#{pid}") && !pids.include?(pid) && fixture.generations.length == 1 &&
          receipts.find { |row| row["state"] == "prepared" }["input_tokens"] == (condition == "guided" ? 256 : 128)
      end
      pids << pid
      store.close
    end
  end
end
require_relative "qualify-continuity-lab-qwen-a16"
check.call("runner stops on execution failures and ambiguous states but retains behavioral failures as results") do
  %w[deadline_exceeded context_budget_exceeded fake_backend_exhausted unknown_reason].all? { |reason|
    a16_stop_receipt?({ "state" => "failed", "reason" => reason })
  } && a16_stop_receipt?({ "state" => "blocked_for_human_review", "reason" => "unresolved_model_intent" }) &&
    %w[repeated_failed_action invalid_action_budget model_call_budget tool_call_budget].none? { |reason|
      a16_stop_receipt?({ "state" => "failed", "reason" => reason })
    } && !a16_stop_receipt?({ "state" => "complete", "reason" => "reply" }) && a16_stop_receipt?({})
end
puts "PASS: #{checks} A16 guidance checks; synthetic inference only"
