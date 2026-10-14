#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/qwen_host_observer"

CL = SoulCore::ContinuityLab

checks = 0
errors = []
check = lambda do |name, condition|
  checks += 1
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end
expect_error = lambda do |klass, &operation|
  operation.call
  false
rescue klass
  true
rescue StandardError
  false
end

class FixtureQwenClient
  attr_reader :requests

  def initialize(tokens: [11, 22], completion: nil, prompt: "fixture prompt<think>\n\n</think>\n\n", error: nil)
    @tokens, @completion, @prompt, @error = tokens, completion, prompt, error
    @requests = []
  end

  def request(method, route, payload = nil, deadline:)
    @requests << [method, route, payload, deadline]
    raise @error if @error && route == "/completion"

    case route
    when "/apply-template" then { "prompt" => @prompt }
    when "/tokenize" then { "tokens" => @tokens }
    when "/completion"
      @completion || { "content" => "{\"action\":\"wait\"}", "tokens_evaluated" => @tokens.length,
                       "tokens_predicted" => 8, "truncated" => false }
    else
      raise "unexpected fixture route #{route}"
    end
  end
end

class FixtureHttpResponse
  attr_reader :code

  def initialize(code: "200", chunks: nil)
    @code, @chunks = code, chunks || [JSON.generate("ok" => true)]
  end

  def read_body
    @chunks.each { |chunk| yield chunk }
  end
end

class FixtureHttpConnection
  attr_accessor :open_timeout, :read_timeout, :write_timeout, :max_retries

  def initialize(response)
    @response = response
  end

  def start
    yield self
  end

  def request(request)
    @request = request
    yield @response
  end

  def recorded_request = @request
end

puts "Continuity Lab A3 Qwen transport verification:"

config = CL::Config.qwen_qualification
check.call("qualification config selects explicit qwen_pipe with six calls and 60 seconds",
           config["backend"] == "qwen_pipe" && config["context_mode"] == "explicit_v1" &&
             config["max_model_calls"] == 6 && config["max_seconds"] == 60)
check.call("qualification config keeps fixed output and margin within 4K context",
           config["context_tokens"] == 4096 && config["output_tokens"] == 768 &&
             config["context_margin"] == 256 && config["output_tokens"] + config["context_margin"] < config["context_tokens"])

network_calls = 0
original_http_new = Net::HTTP.method(:new)
Net::HTTP.define_singleton_method(:new) do |*args|
  network_calls += 1
  raise "unexpected network call"
end
transport = CL::QwenTransport.new
denied_routes = [
  ["GET", "/admin", nil], ["GET", "/health", {}], ["POST", "/health", {}],
  ["POST", "/v1/chat/completions", {}], ["POST", "http://127.0.0.1:8082/completion", {}],
  ["POST", "/completion?url=http://example.invalid", {}], ["POST", "/completion", nil]
]
route_denials = denied_routes.all? do |method, route, payload|
  expect_error.call(CL::ValidationError) do
    transport.request(method, route, payload, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
  end
end
oversized_request_denied = expect_error.call(CL::ValidationError) do
  transport.request("POST", "/completion", { "content" => "x" * (CL::QwenTransport::MAX_BYTES + 1) }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
end
check.call("route allowlist and outbound payload cap reject before HTTP", route_denials && oversized_request_denied && network_calls.zero?)
Net::HTTP.define_singleton_method(:new, original_http_new)

http_state = {}
Net::HTTP.define_singleton_method(:new) do |*args|
  http_state[:args] = args
  http_state[:connection] = FixtureHttpConnection.new(http_state.fetch(:response))
end
http_state[:response] = FixtureHttpResponse.new
valid_transport_result = transport.request("POST", "/completion", { "prompt" => [1, 2] }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
request_obj = http_state[:connection].recorded_request
check.call("transport pins loopback without environment proxy and sends a single non-streaming POST",
           valid_transport_result == { "ok" => true } && http_state[:args] == ["127.0.0.1", 8082, nil] &&
             request_obj.is_a?(Net::HTTP::Post) && request_obj.path == "/completion" && request_obj["Content-Type"] == "application/json")

http_state[:response] = FixtureHttpResponse.new(code: "307")
redirect_denied = expect_error.call(CL::BackendUnavailable) do
  transport.request("POST", "/completion", { "prompt" => [1] }, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
end
http_state[:response] = FixtureHttpResponse.new(chunks: ["x" * (CL::QwenTransport::MAX_BYTES + 1)])
response_limit_denied = expect_error.call(CL::BackendUnavailable) do
  transport.request("GET", "/health", nil, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
end
check.call("transport rejects redirects without following and enforces response byte ceiling", redirect_denied && response_limit_denied)
Net::HTTP.define_singleton_method(:new, original_http_new)

deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30 }
observer_calls = 0
observer = -> { observer_calls += 1; true }
receipts = []
fixture_session = lambda do |client, receipt_sink = receipts, before = -> {}|
  CL::QwenBrokerSession.new(client: client, observer: observer, on_receipt: ->(entry) { receipt_sink << entry }, before_generation: before)
end
request_for = ->(index = 0, input = "fixture envelope") { { "operation" => "generate", "call_index" => index, "input" => input } }

raw = " {\"action\": \"wait\"}\n"
raw_client = FixtureQwenClient.new(completion: { "content" => raw, "tokens_evaluated" => 2, "tokens_predicted" => 8, "truncated" => false })
raw_result = fixture_session.call(raw_client).dispatch(request_for.call, deadline: deadline.call)
raw_payload = raw_client.requests.find { |entry| entry[1] == "/completion" }&.at(2)
check.call("broker forwards raw model content unchanged using submitted token IDs and pinned non-streaming JSON settings",
           raw_result == { "ok" => true, "response" => raw } && raw_payload["prompt"] == [11, 22] &&
             raw_payload["stream"] == false && raw_payload["json_schema"] == { "type" => "object" })
system_prompt = raw_client.requests.find { |entry| entry[1] == "/apply-template" }.dig(2, "messages", 0, "content")
examples = CL::QwenBrokerSession::ENVELOPE_GUIDE.lines.grep(/\A\{/).map(&:strip)
check.call("v2 prompt identifies the real request and uses parser-valid nested examples without output repair",
           system_prompt.include?("user.content") && examples.length == 3 &&
             examples.all? { |example| !CL::Actions.parse(example, config).empty? } &&
             receipts.last["prompt_version"] == "qwen_envelope_v2_explicit_examples" && raw_result["response"] == raw)

oversized_client = FixtureQwenClient.new(tokens: Array.new(3073, 7))
overflow_receipts = []
overflow_session = fixture_session.call(oversized_client, overflow_receipts)
overflow_denied = expect_error.call(CL::ContextBudgetExceeded) { overflow_session.dispatch(request_for.call, deadline: deadline.call) }
check.call("3072 is accepted by the source ceiling and 3073 is rejected before completion with receipt retained",
           begin
             within = fixture_session.call(FixtureQwenClient.new(tokens: Array.new(3072, 7)))
             within.dispatch(request_for.call, deadline: deadline.call)
             overflow_denied && overflow_receipts.any? { |entry| entry["state"] == "input_budget_rejected" } &&
               oversized_client.requests.none? { |entry| entry[1] == "/completion" }
           rescue StandardError
             false
           end)

bad_prompts = ["missing suffix", "<think>\n\n</think>\n\n trailing"]
template_rejections = bad_prompts.all? do |prompt|
  candidate = fixture_session.call(FixtureQwenClient.new(prompt: prompt))
  expect_error.call(CL::BackendUnavailable) { candidate.dispatch(request_for.call, deadline: deadline.call) } &&
    candidate.instance_variable_get(:@client).requests.none? { |entry| entry[1] == "/tokenize" }
end
check.call("template must end with the exact non-thinking suffix before tokenization", template_rejections)

invalid_requests = [
  { "operation" => "generate", "call_index" => 0, "input" => "x", "url" => "http://127.0.0.1:8082" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "path" => "/tmp/model" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "model" => "other" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "extra" => true },
  { "operation" => "generate", "call_index" => 0, "input" => "x" * (CL::BrokerSession::MAX_INPUT_BYTES + 1) },
  { "operation" => "generate", "call_index" => 6, "input" => "x" },
  { "operation" => "generate", "call_index" => "0", "input" => "x" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "operation2" => "admin" }
]
invalid_utf8 = "\xFF".dup.force_encoding(Encoding::UTF_8)
invalid_requests << { "operation" => "generate", "call_index" => 0, "input" => invalid_utf8 }
validation_client = FixtureQwenClient.new
validation_session = fixture_session.call(validation_client)
validation_results = invalid_requests.map.with_index do |request, index|
  denied = expect_error.call(CL::ValidationError) { validation_session.dispatch(request, deadline: deadline.call) }
  puts "  invalid request fixture #{index} unexpectedly passed" unless denied
  denied
end
validation_denials = validation_results.all?
repeated_session = fixture_session.call(FixtureQwenClient.new)
repeated_session.dispatch(request_for.call(0), deadline: deadline.call)
repeated_denied = expect_error.call(CL::ValidationError) do
  repeated_session.dispatch(request_for.call(0), deadline: deadline.call)
end
check.call("broker rejects URL/path/model overrides, malformed fields, invalid UTF-8, oversized input, and invalid sequence bounds", validation_denials && repeated_denied && validation_client.requests.empty?)

six_client = FixtureQwenClient.new
six_session = fixture_session.call(six_client)
six_ok = 6.times.all? { |index| six_session.dispatch(request_for.call(index), deadline: deadline.call)["ok"] }
seventh_denied = expect_error.call(CL::ValidationError) { six_session.dispatch(request_for.call(6), deadline: deadline.call) }
check.call("broker allows at most six increasing generation calls", six_ok && seventh_denied && six_session.calls == 6)

mismatch_cases = [
  { "content" => "answer", "tokens_evaluated" => 1, "tokens_predicted" => 1, "truncated" => false },
  { "content" => "answer", "tokens_evaluated" => 2, "tokens_predicted" => 1, "truncated" => true },
  { "content" => "x" * 65_537, "tokens_evaluated" => 2, "tokens_predicted" => 1, "truncated" => false }
]
mismatch_rejected = mismatch_cases.all? do |completion|
  expect_error.call(CL::BackendUnavailable) do
    fixture_session.call(FixtureQwenClient.new(completion: completion)).dispatch(request_for.call, deadline: deadline.call)
  end
end
check.call("broker fails closed on evaluated-token mismatch, truncation, and oversized output", mismatch_rejected)

backend_error = RuntimeError.new("fixture backend exception")
raised_error = begin
  fixture_session.call(FixtureQwenClient.new(error: backend_error)).dispatch(request_for.call, deadline: deadline.call)
  nil
rescue StandardError => error
  error
end
check.call("backend exception is preserved without fallback", raised_error.equal?(backend_error))

wrong_slots = [nil, {}, [], [{ "is_processing" => true, "n_ctx" => 4096 }], [{ "is_processing" => false, "n_ctx" => 0 }], [{ "is_processing" => false, "n_ctx" => 4096 }, { "is_processing" => false, "n_ctx" => 4096 }]]
slot_denials = wrong_slots.all? { |value| expect_error.call(CL::AdmissionDenied) { CL::QwenHostObserver.validate_slots!(value) } }
check.call("host observer denies busy, unknown, wrong-context, and non-singleton slot states", slot_denials)

drifting_props = [nil, {}, { "model_path" => CL::QwenHostObserver::MODEL },
                  { "model_path" => "/wrong/model.gguf", "model_alias" => "soul-local-chat", "build_info" => "b9851-0eca4d490",
                    "total_slots" => 1, "default_generation_settings" => { "n_ctx" => 4096 }, "is_sleeping" => false,
                    "chat_template" => "wrong template" }]
props_denials = drifting_props.all? { |value| expect_error.call(CL::AdmissionDenied) { CL::QwenHostObserver.validate_props!(value) } }
check.call("host observer denies missing or drifting model and template identity", props_denials && CL::QwenHostObserver::TEMPLATE_SHA256.match?(/\A[0-9a-f]{64}\z/))

puts "Checks: #{checks}; failures: #{errors.length}"
abort("FAILED: #{errors.join('; ')}") unless errors.empty?
