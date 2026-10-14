#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "socket"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/store"

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
reply = Lab.encode("action" => "reply", "content" => "synthetic reply")
broker = ->(responses = [wait]) { Lab::BrokerSession.new(responses: responses) }
dead = ->(pid) { raises.call(Errno::ESRCH) { Process.kill(0, pid) } }
identity = lambda do |pid|
  value = File.read("/proc/#{pid}/stat")
  fields = value[(value.rindex(")") + 2)..].split
  [fields[19], fields[0]]
rescue Errno::ENOENT, Errno::ESRCH
  nil
end

Dir.mktmpdir("continuity-a2-isolation-") do |root|
  state = "#{root}/state"
  Dir.mkdir(state, 0o700)
  canary = "#{root}/host-canary.txt"
  File.write(canary, "synthetic external canary\n", mode: "wx", perm: 0o600)
  tcp = TCPServer.new("127.0.0.1", 0)
  socket = UNIXServer.new("#{root}/host-canary.sock")
  runner = Lab::SandboxRunner.new(state_directory: state)
  probe = runner.run(request: { "mode" => "probe", "canary_path" => canary, "canary_port" => tcp.addr[1] }, broker: broker.call)
  values = probe.fetch("result")
  puts "Worker environment keys: #{values.fetch('environment_keys').join(', ')}" unless values["environment_clean"]
  %w[state_writable code_readable code_readonly host_canary_hidden home_hidden service_sockets_hidden parent_unix_socket_denied gpu_hidden environment_clean parent_loopback_denied].each do |key|
    check.call("actual boundary #{key}", values[key] == true)
  end
  check.call("worker has a different actual network namespace", values["net_namespace"] != File.readlink("/proc/self/ns/net"))
  check.call("successful worker is reaped", dead.call(runner.pid))
  check.call("host canary unchanged", File.read(canary) == "synthetic external canary\n")
  tcp.close
  socket.close

  leases = SoulCore::ModelRuntimeLeaseStore.new(root: root)
  snapshot = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free",
                   "profile_id" => "nvidia-fallback", "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true,
                   "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
  gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: snapshot)
  note = Lab.encode("action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "beacon", "expected_revision" => 0, "content" => "amber beacon synthetic note" })
  request = { "mode" => "run", "create" => true, "event_id" => "seed", "content" => "Synthetic seed", "corpus" => [] }
  check.call("task runner refuses missing admission before spawning", raises.call(Lab::AdmissionDenied) { runner.run(request: request, broker: broker.call) } && !File.exist?("#{state}/store"))
  retained = leases.acquire(provider_id: "fixture", model_id: "fixture", request_id: "ordinary-chat")
  check.call("task runner itself enforces retained-lease denial", raises.call(Lab::AdmissionDenied) { runner.run(request: request, broker: broker.call, admission: gate) } && !File.exist?("#{state}/store"))
  leases.release(retained["lease_id"])
  first = runner.run(request: request, broker: broker.call([note, reply]), admission: gate)
  check.call("isolated runtime completes real fixture journal transaction", first.dig("result", "receipt", "reply") == "synthetic reply" && first.dig("result", "integrity", "note_count") == 1)
  config = Lab::Config.new("backend" => "fixture_pipe", "context_mode" => "explicit_v1")
  store = Lab::Store.open(path: "#{state}/store", config: config)
  lineage = store.integrity.fetch("lineage_id")
  store.close
  read = Lab.encode("action" => "tool", "tool" => "read", "arguments" => { "lineage_id" => lineage, "collection" => "notes", "id" => "beacon", "revision" => 1, "start" => 0, "length" => 100 })
  second = runner.run(request: { "mode" => "run", "create" => false, "event_id" => "recall", "content" => "Recall synthetic note", "corpus" => [] }, broker: broker.call([read, wait]), admission: gate)
  store = Lab::Store.open(path: "#{state}/store", config: config)
  check.call("new isolated process explicitly retrieves persisted source", second.dig("result", "receipt", "state") == "complete" && store.snapshot.dig("events", "recall", "calls", 0, "result", "source", "text") == "amber beacon synthetic note")
  store.close
  retry_broker = broker.call
  retried = runner.run(request: { "mode" => "resume", "event_id" => "seed" }, broker: retry_broker, admission: gate)
  check.call("isolated retry delivers committed receipt without another backend call", retried.dig("result", "receipt", "reply") == "synthetic reply" && retry_broker.calls.zero?)

  short = Lab::SandboxRunner.new(state_directory: state, timeout_seconds: 0.5)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  timed_out = raises.call(Lab::SandboxFailure) { short.run(request: { "mode" => "timeout_probe" }, broker: broker.call, admission: gate) }
  check.call("wall timeout stops and reaps the actual worker", timed_out && dead.call(short.pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 3)
  check.call("admission is available only after timed-out worker returns", gate.with_window { true })
  blocking_broker = broker.call
  blocking_broker.define_singleton_method(:dispatch) { |_request| sleep 3 }
  short_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  blocked_dispatch = raises.call(Lab::SandboxFailure) do
    short.run(request: { "mode" => "run", "create" => false, "event_id" => "broker-timeout", "content" => "Synthetic slow broker", "corpus" => [] }, broker: blocking_broker, admission: gate)
  end
  check.call("whole broker dispatch obeys worker deadline and reaps", blocked_dispatch && dead.call(short.pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) - short_started < 2)
  short.run(request: { "mode" => "resume", "event_id" => "broker-timeout" }, broker: broker.call, admission: gate)
  # The blocked lineage remains intact; use another fixture for subsequent runs.
  second_state = "#{root}/other-state"
  Dir.mkdir(second_state, 0o700)
  runner = Lab::SandboxRunner.new(state_directory: second_state)
  runner.run(request: request, broker: broker.call([note, reply]), admission: gate)
  check.call("live mode refuses fixture broker before starting task", raises.call(Lab::ValidationError) { runner.run(request: request.merge("mode" => "qwen_run"), broker: broker.call, admission: gate) })
  fixture_client = nil
  [false, true].each do |rollover|
    isolated_state = "#{root}/v3-#{rollover}"
    Dir.mkdir(isolated_state, 0o700)
    v3_runner = Lab::SandboxRunner.new(state_directory: isolated_state)
    fixture_client = Object.new
    fixture_client.define_singleton_method(:request) do |_method, route, _payload = nil, deadline:|
      case route
      when "/apply-template" then { "prompt" => "fixture<think>\n\n</think>\n\n" }
      when "/tokenize" then { "tokens" => [1, 2] }
      when "/completion" then { "content" => '{"action":"wait"}', "tokens_evaluated" => 2, "tokens_predicted" => 6, "truncated" => false }
      else raise "unexpected fixture route"
      end
    end
    version = Lab::QwenBrokerSession::V3_PROMPT_VERSION
    v3_broker = Lab::QwenBrokerSession.new(client: fixture_client, observer: -> {}, on_receipt: ->(_receipt) {}, before_generation: -> {}, protocol_version: version)
    mode = rollover ? "qwen_v3_rollover_run" : "qwen_v3_run"
    v3_request = { "mode" => mode, "create" => true, "event_id" => "v3", "content" => "synthetic wait", "corpus" => [] }
    legacy_broker = Lab::QwenBrokerSession.new(client: fixture_client, observer: -> {}, on_receipt: ->(_receipt) {}, before_generation: -> {})
    check.call("v3 mode denies legacy broker #{rollover}", raises.call(Lab::ValidationError) { v3_runner.run(request: v3_request, broker: legacy_broker, admission: gate) })
    v3_result = v3_runner.run(request: v3_request, broker: v3_broker, admission: gate)
    v3_store = Lab::Store.open(path: "#{isolated_state}/store", config: Lab::Config.qwen_v3_qualification(rollover: rollover))
    check.call("actual v3 worker profile and guard config #{rollover}", v3_result.dig("result", "receipt", "reason") == "wait" && v3_store.config.repeated_failure_guard? && v3_store.integrity["ok"])
    v3_store.close
    calls = v3_broker.calls
    v3_resume = v3_runner.run(request: { "mode" => mode.sub(/run\z/, "resume"), "event_id" => "v3" }, broker: v3_broker, admission: gate)
    check.call("actual v3 resume reuses terminal #{rollover}", v3_resume.dig("result", "receipt", "reason") == "wait" && v3_broker.calls == calls)
  end
  [false, true].each do |rollover|
    v4_state = "#{root}/v4-#{rollover}"
    Dir.mkdir(v4_state, 0o700)
    v4_runner = Lab::SandboxRunner.new(state_directory: v4_state)
    budget = rollover ? 2048 : 3072
    v4_broker = Lab::QwenBrokerSession.new(client: fixture_client, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
      protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: budget)
    mode = rollover ? "qwen_v4_rollover_run" : "qwen_v4_run"
    v4_request = { "mode" => mode, "create" => true, "event_id" => "v4", "content" => "synthetic wait", "corpus" => [] }
    wrong_broker = Lab::QwenBrokerSession.new(client: fixture_client, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
      protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: rollover ? 3072 : 2048)
    check.call("v4 denies wrong fixture budget #{rollover}", raises.call(Lab::ValidationError) { v4_runner.run(request: v4_request, broker: wrong_broker, admission: gate) })
    result = v4_runner.run(request: v4_request, broker: v4_broker, admission: gate)
    v4_store = Lab::Store.open(path: "#{v4_state}/store", config: Lab::Config.qwen_v4_qualification(rollover: rollover))
    check.call("actual v4 pipe prepares and journals exact context #{rollover}", result.dig("result", "receipt", "reason") == "wait" &&
      v4_store.snapshot.dig("events", "v4", "calls", 0, "context", "manifest", "counter") == Lab::TokenContext::COUNTER && v4_store.integrity["ok"])
    v4_store.close
    calls = v4_broker.calls
    retry_result = v4_runner.run(request: { "mode" => mode.sub(/run\z/, "resume"), "event_id" => "v4" }, broker: v4_broker, admission: gate)
    check.call("actual v4 resume returns terminal without generation #{rollover}", retry_result.dig("result", "receipt", "reason") == "wait" && v4_broker.calls == calls)
  end
  cancel_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
  descendants = {}
  cancellation = lambda do
    queue = [runner.pid]
    4.times do
      queue = queue.flat_map do |pid|
        children = File.read("/proc/#{pid}/task/#{pid}/children").split.map { |value| Integer(value) }
        children.each { |child| descendants[child] ||= identity.call(child) }
        children
      rescue Errno::ENOENT, Errno::ESRCH
        []
      end
      break if queue.empty?
    end
    Process.clock_gettime(Process::CLOCK_MONOTONIC) >= cancel_at
  end
  canceled = raises.call(Lab::SandboxFailure) { runner.run(request: { "mode" => "timeout_probe" }, broker: broker.call, admission: gate, cancel: cancellation) }
  check.call("foreground cancellation terminates and reaps worker", canceled && dead.call(runner.pid))
  quiet = lambda do
    descendants.all? do |pid, before|
      after = identity.call(pid)
      after.nil? || before.nil? || after[0] != before[0] || after[1] == "Z"
    end
  end
  50.times { break if quiet.call; sleep 0.01 }
  check.call("observed nested worker processes no longer run after cancellation", !descendants.empty? && quiet.call)
  disconnected = raises.call(Lab::SandboxFailure) { runner.run(request: { "mode" => "disconnect_probe" }, broker: broker.call) }
  check.call("worker disconnect without completion fails and reaps", disconnected && dead.call(runner.pid))
  denied = raises.call(Lab::SandboxFailure) { runner.run(request: { "mode" => "exec", "command" => "touch /state/forbidden" }, broker: broker.call, admission: gate) }
  check.call("fixed worker rejects arbitrary command mode", denied && !File.exist?("#{state}/forbidden"))

  # Exhausted broker after intent must not get hidden retry or a new generation.
  exhausted = raises.call(Lab::ValidationError) do
    runner.run(request: { "mode" => "run", "create" => false, "event_id" => "ambiguous", "content" => "Synthetic interruption", "corpus" => [] }, broker: broker.call([note]), admission: gate)
  end
  check.call("broker failure terminates worker", exhausted && dead.call(runner.pid))
  resumed_broker = broker.call
  recovered = runner.run(request: { "mode" => "resume", "event_id" => "ambiguous" }, broker: resumed_broker, admission: gate)
  check.call("lost broker reply blocks ambiguous intent without regeneration", recovered.dig("result", "receipt", "state") == "blocked_for_human_review" && resumed_broker.calls.zero?)
ensure
  tcp&.close unless tcp&.closed?
  socket&.close unless socket&.closed?
  store&.close
end

puts "PASS: #{checks} actual isolated-worker A2 checks; synthetic broker only, no inference"
