#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "socket"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/store"

Lab = SoulCore::ContinuityLab
checks = 0
check = lambda do |label, &block|
  raise "FAIL: #{label}" unless block.call
  checks += 1
  puts "PASS: #{label}"
end
raises = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
dead = ->(pid) { pid && raises.call(Errno::ESRCH) { Process.kill(0, pid) } }

class A7IsolatedFixtureClient
  attr_reader :generations, :deadlines
  def initialize(interrupt: false)
    @interrupt, @generations, @deadlines = interrupt, 0, []
  end
  def request(_method, route, _payload = nil, deadline:)
    case route
    when '/apply-template' then { 'prompt' => "fixture<think>\n\n</think>\n\n" }
    when '/tokenize' then { 'tokens' => [1, 2, 3] }
    else raise 'unexpected fixture route'
    end
  end
  def stream_completion(payload, deadline:, on_progress:)
    @generations += 1
    @deadlines << deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise 'wrong fixture settings' unless payload == Lab::QwenBrokerSession::V3_SETTINGS.merge('stream' => true, 'prompt' => [1,2,3])
    parser = Lab::QwenStreamResponse.new(on_progress: on_progress)
    prefix = @interrupt ? '{"action":"tool","tool":"note.write"' : '{"action":"wait"}'
    parser.feed("data: #{Lab.encode({ 'content' => prefix, 'stop' => false })}\n\n")
    if @interrupt
      on_progress.call(parser.diagnostic.merge('interrupted' => true, 'error_class' => 'SyntheticDisconnect'))
      raise Lab::BackendUnavailable, 'synthetic stream disconnect'
    end
    parser.feed("data: #{Lab.encode({ 'content' => '', 'stop' => true, 'tokens_evaluated' => 3, 'tokens_predicted' => 8, 'truncated' => false })}\n\n")
    parser.finish
  end
end

Dir.mktmpdir('continuity-a7-isolation-') do |root|
  leases = SoulCore::ModelRuntimeLeaseStore.new(root: root)
  snapshot = -> { { 'captured_at' => Process.clock_gettime(Process::CLOCK_MONOTONIC), 'core' => 'amd-free',
    'profile_id' => 'nvidia-fallback', 'model_file' => 'Qwen3-8B-Q4_K_M.gguf', 'service_active' => true,
    'active_slots' => 0, 'pending_transition' => false, 'dedicated_window' => true } }
  gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: snapshot)
  make_broker = ->(client, receipts) { Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(r) { receipts << r },
    before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION,
    execution_profile: Lab::Config::STREAM_PROFILE) }
  [false, true].each do |rollover|
    path = "#{root}/state-#{rollover}"
    Dir.mkdir(path, 0o700)
    config = Lab::Config.qwen_v5_qualification(rollover: rollover)
    mode = rollover ? 'qwen_v5_rollover_run' : 'qwen_v5_run'
    request = { 'mode' => mode, 'create' => true, 'event_id' => 'fixture', 'content' => 'synthetic wait', 'corpus' => [] }
    client, records = A7IsolatedFixtureClient.new, []
    broker = Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(r) { records << r }, before_generation: -> {},
      protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: rollover ? 2048 : 3072, execution_profile: Lab::Config::STREAM_PROFILE)
    runner = Lab::SandboxRunner.new(state_directory: path, timeout_seconds: 430, execution_profile: Lab::Config::STREAM_PROFILE)
    legacy = Lab::SandboxRunner.new(state_directory: path)
    check.call("legacy runner cannot use new profile #{rollover}") { raises.call(Lab::ValidationError) { legacy.run(request: request, broker: broker, admission: gate) } && !File.exist?("#{path}/store") }
    wrong = request.merge('mode' => rollover ? 'qwen_v4_rollover_run' : 'qwen_v4_run')
    check.call("extended runner cannot relax legacy mode #{rollover}") { raises.call(Lab::ValidationError) { runner.run(request: wrong, broker: broker, admission: gate) } }
    outcome = runner.run(request: request, broker: broker, admission: gate)
    store = Lab::Store.open(path: "#{path}/store", config: config)
    check.call("actual v5 worker returns validated full response and reaps #{rollover}") do
      outcome.dig('result','receipt','reason') == 'wait' && dead.call(runner.pid) && store.integrity['ok'] &&
        store.snapshot.dig('events','fixture','calls',0,'response') == '{"action":"wait"}'
    end
    check.call("new broker receives coherent ~420s absolute event deadline #{rollover}") { client.deadlines.first.between?(415, 420) }
    check.call("partial receipts remain outside action journal #{rollover}") { records.count { |r| r['state'] == 'stream_fragment' } == 2 && store.snapshot.dig('events','fixture','calls').length == 1 }
    store.close
    count = client.generations
    resumed = runner.run(request: { 'mode' => mode.sub(/run\z/,'resume'), 'event_id' => 'fixture' }, broker: broker, admission: gate)
    check.call("terminal resume produces no generation #{rollover}") { resumed.dig('result','receipt','reason') == 'wait' && client.generations == count }
  end
  path = "#{root}/interrupted"
  Dir.mkdir(path, 0o700)
  records = []
  client = A7IsolatedFixtureClient.new(interrupt: true)
  broker = make_broker.call(client, records)
  runner = Lab::SandboxRunner.new(state_directory: path, timeout_seconds: 430, execution_profile: Lab::Config::STREAM_PROFILE)
  check.call('stream disconnect reaps actual worker and retains diagnostic prefix') do
    raises.call(Lab::BackendUnavailable) { runner.run(request: { 'mode' => 'qwen_v5_run', 'create' => true, 'event_id' => 'partial', 'content' => 'synthetic', 'corpus' => [] }, broker: broker, admission: gate) } &&
      dead.call(runner.pid) && records.any? { |r| r['state'] == 'stream_interrupted' && r['partial_content'].include?('note.write') }
  end
  store = Lab::Store.open(path: "#{path}/store", config: Lab::Config.qwen_v5_qualification)
  check.call('partial tool JSON never executes or becomes model response') do
    store.snapshot['notes'].empty? && store.snapshot.dig('events','partial','calls',0,'response').nil?
  end
  store.close
  retry_client = A7IsolatedFixtureClient.new
  recovered = runner.run(request: { 'mode' => 'qwen_v5_resume', 'event_id' => 'partial' }, broker: make_broker.call(retry_client, []), admission: gate)
  check.call('unresolved streamed intent blocks recovery without regeneration') { recovered.dig('result','receipt','reason') == 'unresolved_model_intent' && retry_client.generations.zero? }
  check.call('admission released after worker reaping') { gate.with_window { true } }
end

# Real socket cancellation against a bounded synthetic local server. The production
# transport destination is asserted before mapping to this ephemeral test listener.
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
closed_by_client = false
socket = nil
thread = Thread.new do
  Timeout.timeout(3) do
    socket = server.accept
    headers = +''
    headers << socket.read(1) until headers.end_with?("\r\n\r\n") || headers.bytesize > 8192
    length = Integer(headers[/Content-Length:\s*(\d+)/i,1])
    socket.read(length)
    frame = "data: {\"stop\":false,\"content\":\"socket-prefix\"}\n\n"
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
    socket.write("#{frame.bytesize.to_s(16)}\r\n#{frame}\r\n")
    closed_by_client = socket.read(1).nil?
  end
ensure
  socket&.close
end
original = Net::HTTP.method(:new)
Net::HTTP.define_singleton_method(:new) do |*args|
  raise 'unexpected destination' unless args == ['127.0.0.1', 8082, nil]
  original.call('127.0.0.1', port, nil)
end
begin
  receipts = []
  error = raises.call(Lab::BackendUnavailable) do
    Lab::QwenTransport.new.stream_completion({ 'stream' => true, 'n_predict' => 768, 'prompt' => [1,2,3] },
      deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25, on_progress: ->(r) { receipts << r })
  end
  thread.join(2)
  check.call('actual HTTP timeout closes socket and retains prefix, no response execution') { error && !thread.alive? && closed_by_client && receipts.last['interrupted'] && receipts.last['partial_content'] == 'socket-prefix' }
ensure
  Net::HTTP.define_singleton_method(:new, original)
  server.close
  socket&.close unless socket&.closed?
  thread.kill if thread.alive?
  thread.join
end
puts "PASS: #{checks} A7 actual isolation/socket checks; synthetic backend only"
