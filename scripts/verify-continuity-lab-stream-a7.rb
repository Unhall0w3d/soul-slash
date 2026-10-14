#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"

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
event = ->(row) { "data: #{JSON.generate(row)}\n\n" }
part = ->(text) { event.call({ "content" => text, "stop" => false }) }
terminal = { "content" => "", "stop" => true, "tokens_evaluated" => 3, "tokens_predicted" => 7, "truncated" => false }
wire = part.call('{"action":') + part.call('"reply","content":"café"}') + event.call(terminal)
parse = lambda do |chunks|
  records = []
  parser = Lab::QwenStreamResponse.new(on_progress: ->(row) { records << row })
  chunks.each { |chunk| parser.feed(chunk) }
  [parser.finish, records]
end
check.call("arbitrary byte fragmentation preserves exact Unicode content and final metadata") do
  result, records = parse.call(wire.b.bytes.map { |byte| byte.chr })
  result["content"] == '{"action":"reply","content":"café"}' && result["tokens_evaluated"] == 3 && records.length == 3
end
check.call("CRLF framing and comment keepalive supported") { parse.call([":keepalive\r\n\r\n" + wire.gsub("\n", "\r\n")])[0]["stop"] }
check.call("trailing blank/comment keepalive allowed but never contributes content") { parse.call([wire + ":keepalive\n\n\n"])[0] == parse.call([wire])[0] }
check.call("final metadata content is not duplicated") { parse.call([part.call('hi') + event.call(terminal)])[0]["content"] == 'hi' }
bad_wires = {
  "missing terminal" => part.call('partial'),
  "incomplete final frame" => part.call('partial') + event.call(terminal).delete_suffix("\n"),
  "duplicate final" => wire + event.call(terminal),
  "extra data after terminal" => wire + part.call('extra'),
  "wrong event framing" => "event: delta\n\n",
  "duplicate JSON keys" => "data: {\"content\":\"x\",\"stop\":true,\"stop\":false}\n\n",
  "invalid JSON" => "data: nope\n\n",
  "unexpected done sentinel" => "data: [DONE]\n\n",
  "invalid UTF8" => "data: \xff\n\n".b,
  "server error" => event.call({ "error" => { "message" => "bad" } }),
  "nonboolean stop" => event.call({ "content" => "", "stop" => 1 }),
  "nonempty final content" => event.call(terminal.merge("content" => "duplicated")),
  "missing terminal token count" => event.call(terminal.reject { |k,_| k == "tokens_predicted" }),
  "excess terminal token count" => event.call(terminal.merge("tokens_predicted" => 769)),
  "truncated result" => event.call(terminal.merge("truncated" => true)),
  "oversized content" => part.call('x' * 65_537),
  "oversized wire" => 'x' * 524_289,
  "too many empty events" => part.call('') * 2049
}
bad_wires.each do |name, value|
  check.call("reject #{name}") { raises.call(StandardError) { parse.call([value]) } }
end
parser = Lab::QwenStreamResponse.new(on_progress: ->(_row) {})
parser.feed(part.call('retained'))
parser.feed("data: {\"cont")
check.call("incomplete-frame evidence retained without a completed response") do
  raises.call(Lab::ValidationError) { parser.finish } && parser.diagnostic["partial_content"] == "retained" &&
    Base64.strict_decode64(parser.diagnostic["pending_frame_base64"]) == "data: {\"cont" && !parser.diagnostic["terminal_seen"]
end

class A7HttpResponse
  attr_reader :code
  def initialize(chunks, error: nil, pause: nil, code: '200', content_type: 'text/event-stream')
    @chunks, @error, @pause, @code, @content_type = chunks, error, pause, code, content_type
  end
  def [](name) = name == 'content-type' ? @content_type : nil
  def read_body
    @chunks.each { |c| yield c }
    sleep @pause if @pause
    raise @error if @error
  end
end
class A7HttpConnection
  attr_accessor :open_timeout, :read_timeout, :write_timeout, :max_retries
  attr_reader :request_value, :closed
  def initialize(response) = @response = response
  def start
    yield self
  ensure
    @closed = true
  end
  def request(value)
    @request_value = value
    yield @response
  end
end
original = Net::HTTP.method(:new)
state = {}
Net::HTTP.define_singleton_method(:new) do |*args|
  state[:args] = args
  state[:connections] = state.fetch(:connections, 0) + 1
  state[:http] = A7HttpConnection.new(state.fetch(:response))
end
begin
  transport = Lab::QwenTransport.new
  payload = Lab::QwenBrokerSession::V3_SETTINGS.merge("stream" => true, "prompt" => [1,2,3])
  call = lambda do |seconds = 70, &progress|
    transport.stream_completion(payload, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds,
      on_progress: progress || ->(_row) {})
  end
  state[:response] = A7HttpResponse.new([wire])
  check.call("stream delivery pins host, route, no proxy/retry and unchanged sampler") do
    call.call["content"].include?('café') && state[:args] == ['127.0.0.1', 8082, nil] &&
      state[:http].request_value.path == '/completion' && JSON.parse(state[:http].request_value.body) == payload && state[:http].max_retries.zero?
  end
  check.call("stream request cap60 and open cap2 are explicit") { state[:http].read_timeout == 60 && state[:http].write_timeout == 60 && state[:http].open_timeout == 2 && state[:http].closed }
  call.call(0.5)
  check.call("caller remaining budget clamps stream cap") { state[:http].read_timeout.between?(0.4, 0.5) }
  [IOError.new('synthetic'), EOFError.new('synthetic'), Timeout::Error.new('synthetic')].each do |error|
    records = []
    state[:response] = A7HttpResponse.new([part.call('partial')], error: error)
    start = state[:connections]
    check.call("#{error.class} closes connection, records partial, never returns it or retries") do
      raises.call(Lab::BackendUnavailable) { call.call { |r| records << r } } && state[:http].closed &&
        state[:connections] == start + 1 && records.last["interrupted"] && records.last["partial_content"] == 'partial'
    end
  end
  state[:response] = A7HttpResponse.new([part.call('stalled')], pause: 0.3)
  records = []
  began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  check.call("actual short absolute timeout preserves prefix and closes connection") do
    raises.call(Lab::BackendUnavailable) { call.call(0.04) { |r| records << r } } &&
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - began < 0.25 && state[:http].closed && records.last["partial_content"] == 'stalled'
  end
  state[:response] = A7HttpResponse.new([wire])
  check.call("receipt write failure fails closed") { raises.call(Lab::BackendUnavailable) { call.call { |_r| raise IOError, 'receipt fault' } } && state[:http].closed }
  state[:response] = A7HttpResponse.new([wire], code: '307')
  start = state[:connections]
  check.call("stream redirect rejected with no follow or retry") { raises.call(Lab::BackendUnavailable) { call.call } && state[:connections] == start + 1 }
  state[:response] = A7HttpResponse.new([wire], content_type: 'application/json')
  check.call("nonstream content type rejected") { raises.call(Lab::BackendUnavailable) { call.call } }
  state[:response] = A7HttpResponse.new([JSON.generate({ 'ok' => true })], content_type: 'application/json')
  transport.request('GET', '/health', deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 70)
  check.call("legacy HTTP ceiling unchanged") { state[:http].read_timeout == 30 && state[:http].write_timeout == 30 }
ensure
  Net::HTTP.define_singleton_method(:new, original)
end

check.call("legacy profile digests contain no new execution key and max60 stays enforced") do
  !Lab::Config.qwen_v4_qualification.to_h.key?('execution_profile') &&
    raises.call(Lab::ValidationError) { Lab::Config.new('max_seconds' => 420) }
end
[false, true].each do |rollover|
  config = Lab::Config.qwen_v5_qualification(rollover: rollover)
  check.call("new profile explicit420s retains exact context/output/call settings #{rollover}") do
    config.stream_diagnostics? && config['max_seconds'] == 420 &&
      config.to_h.reject { |k,_| %w[max_seconds execution_profile].include?(k) } ==
      Lab::Config.qwen_v4_qualification(rollover: rollover).to_h.reject { |k,_| k == 'max_seconds' }
  end
end
check.call("stream profile cannot enlarge fake capabilities or select arbitrary timeout") do
  raises.call(Lab::ValidationError) { Lab::Config.new('execution_profile' => Lab::Config::STREAM_PROFILE, 'max_seconds' => 420) } &&
    raises.call(Lab::ValidationError) { Lab::Config.new(Lab::Config.qwen_v5_qualification.to_h.merge('max_seconds' => 421)) }
end
Dir.mktmpdir('continuity-a7-bounds-') do |directory|
  check.call("legacy worker still rejects extended deadline") { raises.call(Lab::ValidationError) { Lab::SandboxRunner.new(state_directory: directory, timeout_seconds: 61) } }
  check.call("new worker profile caps at430 and rejects arbitrary profile") do
    Lab::SandboxRunner.new(state_directory: directory, timeout_seconds: 430, execution_profile: Lab::Config::STREAM_PROFILE) &&
      raises.call(Lab::ValidationError) { Lab::SandboxRunner.new(state_directory: directory, timeout_seconds: 431, execution_profile: Lab::Config::STREAM_PROFILE) } &&
      raises.call(Lab::ValidationError) { Lab::SandboxRunner.new(state_directory: directory, execution_profile: 'arbitrary') }
  end
end
puts "PASS: #{checks} A7 deterministic stream checks; no live inference"
