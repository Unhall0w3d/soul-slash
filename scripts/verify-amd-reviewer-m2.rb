#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "qualify-amd-reviewer-m2"

Pilot = AmdReviewerPilotM2
checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  puts "- #{label}: #{condition ? 'ok' : 'FAIL'}"
  failures << label unless condition
end
raises = lambda do |klass, message = nil, &operation|
  begin
    operation.call
  rescue klass => error
    message.nil? || error.message.include?(message)
  rescue StandardError
    false
  else
    false
  end
end

puts "AMD reviewer M2 deterministic protocol and lifecycle verification:"

argv = Pilot.argv("amd-reviewer-m2-test")
environment = Pilot.environment
check.call("launch fixes the loopback endpoint, one slot, Vulkan0, full offload, and no agent/tools",
           argv.include?("127.0.0.1") && argv.include?(Pilot::PORT.to_s) && argv.include?("--parallel") &&
             argv[argv.index("--parallel") + 1] == "1" && argv.include?("Vulkan0") &&
             argv[argv.index("--gpu-layers") + 1] == "all" && argv.include?("--no-agent") && argv.include?("--no-webui") &&
             argv.include?("--offline") && argv[argv.index("--cors-origins") + 1] == "http://127.0.0.1:8096")
check.call("launch environment hides CUDA and admits no inherited model/provider overrides",
           environment["CUDA_VISIBLE_DEVICES"] == "" && environment["GGML_BACKEND_PATH"] == Pilot::PLUGIN &&
             (environment.keys & %w[LLAMA_ARG_MODEL LLAMA_ARG_HOST LLAMA_ARG_PORT HF_TOKEN OPENAI_API_KEY]).empty?)
check.call("argv rejects an unsafe runtime alias", raises.call(ArgumentError, "invalid alias") { Pilot.argv("../agent") })
check.call("offload evidence tolerates raw vocabulary bytes but requires full Vulkan offload",
           Pilot.offload_evidence("\xFFVulkan0 offloaded 41/41 layers to GPU".b) == %w[41 41] &&
             raises.call(Pilot::Stop, "offload unconfirmed") { Pilot.offload_evidence("Vulkan0 offloaded 40/41 layers to GPU") } &&
             raises.call(Pilot::Stop, "offload unconfirmed") { Pilot.offload_evidence("CUDA0 offloaded 41/41 layers to GPU") })

cases = Pilot.cases
check.call("three fixed synthetic packets bind source and evidence revisions",
           cases.map { |packet| packet.fetch("review_id") } == %w[supported contradicted absent] &&
             cases.all? { |packet| Pilot::Contract.request!(packet) == packet &&
               packet["source_revision"] == Pilot::Contract.text_digest(packet["source_answer"]) &&
               packet["evidence_revision"] == Pilot::Contract.digest(packet["evidence"]) })
check.call("packet and response contracts reject revision drift and open response fields",
           raises.call(SoulCore::ContinuityLab::ValidationError, "revision mismatch") do
             Pilot::Contract.request!(cases.first.merge("source_revision" => Pilot::Contract.text_digest("other")))
           end && raises.call(SoulCore::ContinuityLab::ValidationError, "unexpected fields") do
             Pilot::Contract.response!({ "review_id" => "supported", "verdict" => "supported", "findings" => [],
               "omissions" => [], "extra" => true }, request: cases.first)
           end)
check.call("schema closes response fields and bounds findings and omissions",
           Pilot.response_schema["additionalProperties"] == false &&
             Pilot.response_schema.dig("properties", "findings", "maxItems") == 16 &&
             Pilot.response_schema.dig("properties", "omissions", "maxItems") == 16)

base = { "temperatures" => { "edge" => 79.9, "junction" => 94.9 },
         "vram_total" => 16 * Pilot::GIB, "vram_used" => 8 * Pilot::GIB,
         "memory" => { "MemAvailable" => 16 * Pilot::GIB }, "paging_pages" => { "pswpout" => 100 } }
check.call("resource check accepts values below all conservative thresholds",
           !raises.call(Pilot::Stop) { Pilot.check_resources!(base, base) })
resource_failures = [
  ["AMD thermal bound", base.merge("temperatures" => { "edge" => 80, "junction" => 50 })],
  ["AMD thermal bound", base.merge("temperatures" => { "edge" => 50, "junction" => 95 })],
  ["AMD headroom bound", base.merge("vram_used" => 14 * Pilot::GIB + 1)],
  ["RAM headroom bound", base.merge("memory" => { "MemAvailable" => 8 * Pilot::GIB - 1 })],
  ["swap-out bound", base.merge("paging_pages" => { "pswpout" => 65_637 })]
]
check.call("resource check rejects each threshold with a meaningful cause",
           resource_failures.all? do |message, sample|
             raises.call(Pilot::Stop, message) { Pilot.check_resources!(sample, base) }
           end)

lease_store = Class.new do
  attr_reader :released
  def acquire_exclusive(**args) = { "acquired" => args }
  def release(id) = (@released = id)
end.new
lease_pilot = Pilot.new
guarded_leases = Pilot::GuardedLeases.new(store: lease_store, pilot: lease_pilot)
lease_pilot.instance_variable_set(:@child, 424_242)
check.call("lease release remains blocked while the owned child is unreaped",
           raises.call(Pilot::Stop, "owned child unreaped") { guarded_leases.release("lease-1") } && lease_store.released.nil?)
lease_pilot.instance_variable_set(:@child, nil)
check.call("lease release proceeds after owned child teardown", guarded_leases.release("lease-1") == "lease-1" && lease_store.released == "lease-1")

# Redirect only the exact synthetic child fdinfo path. This tests parsing and
# minimum allocation evidence without reading any real process or GPU state.
drm_probe = Pilot.new
drm_probe.instance_variable_set(:@child, 424_242)
drm_path = "/proc/424242/fdinfo/7"
drm_text = "drm-pdev: #{SoulCore::AmdWhisperDevice::PCI}\ndrm-client-id: 9\ndrm-resident-vram: 4096 MiB\ndrm-engine-gfx: 12 ns\n"
original_dir_glob = Dir.method(:glob)
original_file_read = File.method(:read)
begin
  Dir.define_singleton_method(:glob) { |pattern, *args, **kwargs| pattern == "/proc/424242/fdinfo/*" ? [drm_path] : original_dir_glob.call(pattern, *args, **kwargs) }
  File.define_singleton_method(:read) { |path, *args, **kwargs| path == drm_path ? drm_text : original_file_read.call(path, *args, **kwargs) }
  drm_evidence = drm_probe.owned_drm
  check.call("owned DRM parser accepts only synthetic child fdinfo with sufficient AMD allocation",
             drm_evidence["pid"] == 424_242 && drm_evidence["clients"]["9"]["vram_bytes"] == 4 * Pilot::GIB &&
               drm_evidence["clients"]["9"]["engines_ns"] == { "gfx" => 12 })
ensure
  Dir.define_singleton_method(:glob, original_dir_glob)
  File.define_singleton_method(:read, original_file_read)
end
no_drm = Pilot.new
no_drm.instance_variable_set(:@child, 424_243)
original_dir_glob = Dir.method(:glob)
begin
  Dir.define_singleton_method(:glob) { |pattern, *args, **kwargs| pattern == "/proc/424243/fdinfo/*" ? [] : original_dir_glob.call(pattern, *args, **kwargs) }
  check.call("owned DRM parser rejects a synthetic child with no AMD fdinfo", raises.call(Pilot::Stop, "owned AMD model allocation unconfirmed") do
    no_drm.owned_drm
  end)
ensure
  Dir.define_singleton_method(:glob, original_dir_glob)
end

Dir.mktmpdir("amd-reviewer-m2-verify-") do |directory|
  occupied = Pilot.new
  occupied.instance_variable_set(:@output, directory)
  def occupied.port_closed? = false
  check.call("occupied pilot endpoint is refused before child launch", raises.call(Pilot::Stop, "pilot endpoint occupied") do
    occupied.start_server("occupied")
  end && occupied.instance_variable_get(:@child).nil?)
  check.call("receipt writer refuses path-like names", raises.call(Pilot::Stop, "unsafe receipt name") do
    occupied.save("../escape.json", {})
  end && !File.exist?(File.join(directory, "escape.json")))

  # A local fake HTTP transport exercises route allowlisting and byte accounting
  # without opening a socket or contacting a service.
  fake_response = Class.new do
    attr_reader :code
    def initialize(body) = (@body = body; @code = "200")
    def read_body = yield(@body)
  end
  fake_client = Class.new do
    attr_accessor :open_timeout, :read_timeout, :write_timeout, :max_retries
    attr_reader :last_request
    def initialize(response) = (@response = response)
    def start = yield(self)
    def request(request)
      @last_request = request
      yield(@response)
    end
  end
  http = Pilot.new
  original_http_new = Net::HTTP.method(:new)
  begin
    Net::HTTP.define_singleton_method(:new) { |*| fake_client.new(fake_response.new("{}")) }
    check.call("HTTP rejects unapproved routes before transport", raises.call(Pilot::Stop, "unapproved route") do
      http.http("/agent")
    end)
    check.call("HTTP fake transport parses an allowed bounded response", http.http("/health") == {})
    authenticated_client = fake_client.new(fake_response.new("{}"))
    Net::HTTP.define_singleton_method(:new) { |*| authenticated_client }
    http.instance_variable_set(:@api_key, "synthetic-local-key")
    http.http("/health")
    check.call("local authentication goes only in the request header",
               authenticated_client.last_request["Authorization"] == "Bearer synthetic-local-key" &&
                 authenticated_client.last_request.path == "/health" && authenticated_client.last_request.body.nil?)
    http.remove_instance_variable(:@api_key)
    Net::HTTP.define_singleton_method(:new) { |*| fake_client.new(fake_response.new("x" * 524_289)) }
    check.call("HTTP rejects response bodies above the byte cap", raises.call(Pilot::Stop, "response size bound") do
      http.http("/health")
    end)
  timed_response = Class.new do
    attr_reader :code
    def initialize = (@code = "200")
    def read_body = raise(Timeout::Error, "synthetic timeout")
  end
  Net::HTTP.define_singleton_method(:new) { |*| fake_client.new(timed_response.new) }
  check.call("HTTP timeout from a synthetic response remains a bounded failure",
             raises.call(Timeout::Error, "synthetic timeout") { http.http("/health", nil, seconds: 1) })
  ensure
    Net::HTTP.define_singleton_method(:new, original_http_new)
  end

  # Generate protocol events with a local adapter. The final valid JSON is
  # deliberately synthetic and never reaches a model endpoint.
  packet = cases.first
  response = { "review_id" => packet.fetch("review_id"), "verdict" => "supported", "findings" => [], "omissions" => [] }
  event = lambda do |content, stop: false, truncated: false, stop_type: "eos", tokens: 2|
    { "content" => content, "stop" => stop, "truncated" => truncated,
      "stop_type" => stop_type, "tokens_evaluated" => tokens }
  end
  generator = Class.new(Pilot) do
    attr_accessor :events, :prompt, :tokens, :drm
    def initialize(events)
      super()
      @events = events
      @prompt = "synthetic prompt"
      @tokens = [1, 2]
      @drm = { "pid" => 424_242, "clients" => { "9" => { "vram_bytes" => 4 * Pilot::GIB } } }
      @saved = {}
    end
    def save(name, value) = @saved[name] = value
    def saved = @saved
    def now = (@clock ||= 0.0; @clock += 0.01)
    def endpoint_owned! = true
    def owned_drm = drm
    def http(path, payload = nil, **)
      case path
      when "/apply-template" then { "prompt" => prompt }
      when "/tokenize" then { "tokens" => tokens }
      when "/completion"
        events.each { |item| yield("data: #{JSON.generate(item)}\n") }
        yield("data: [DONE]\n")
        ""
      else raise "unexpected fake route #{path}"
      end
    end
  end
  valid_events = [event.call(JSON.generate(response)[0, 20]), event.call(JSON.generate(response)[20..], stop: true)]
  successful = generator.new(valid_events)
  successful.generate(packet, label: "synthetic")
  check.call("synthetic SSE fragments assemble into the exact closed response and preserve revisions",
             successful.saved["synthetic-response.json"].dig("response") == response &&
               successful.saved["synthetic-response.json"]["request_revision"] == Pilot::Contract.digest(packet) &&
               successful.saved["synthetic-response.json"]["source_revision"] == packet["source_revision"] &&
               successful.saved["synthetic-response.json"]["evidence_revision"] == packet["evidence_revision"])

  truncated = generator.new([event.call(JSON.generate(response), stop: true, truncated: true, stop_type: "limit")])
  check.call("truncated generation is rejected and retained as a failure", raises.call(Pilot::Stop, "missing completion or truncation") do
    truncated.generate(packet, label: "truncated")
  end && truncated.saved.key?("truncated-failure.json") &&
    truncated.saved["truncated-failure.json"]["message"].include?("missing completion or truncation"))

  wrong_identity = response.merge("review_id" => "other")
  invalid = generator.new([event.call(JSON.generate(wrong_identity), stop: true)])
  check.call("contract-invalid generated JSON is rejected with its contract cause", raises.call(SoulCore::ContinuityLab::ValidationError) do
    invalid.generate(packet, label: "invalid")
  end && invalid.saved["invalid-failure.json"]["message"].include?("invalid response identity"))

  oversized = response.merge("omissions" => Array.new(16) { "o" * 2048 })
  oversize_output = generator.new([event.call(JSON.generate(oversized), stop: true)])
  check.call("response byte budget is enforced by the closed response contract", raises.call(SoulCore::ContinuityLab::ValidationError, "response exceeds byte bound") do
    oversize_output.generate(packet, label: "oversized")
  end)

  too_many_tokens = generator.new([event.call(JSON.generate(response), stop: true)])
  too_many_tokens.tokens = Array.new(3073, 1)
  check.call("input token budget rejects over-limit rendered prompts", raises.call(Pilot::Stop, "input token bound") do
    too_many_tokens.generate(packet, label: "token-budget")
  end && too_many_tokens.saved.key?("token-budget-request.json") == false)

  too_large_prompt = generator.new([event.call(JSON.generate(response), stop: true)])
  too_large_prompt.prompt = "p" * 65_537
  check.call("rendered prompt byte budget rejects oversized input", raises.call(Pilot::Stop, "template size bound") do
    too_large_prompt.generate(packet, label: "prompt-budget")
  end)

  bad_stream = generator.new([event.call(7)])
  check.call("non-string SSE content is rejected with a protocol cause", raises.call(Pilot::Stop, "invalid stream content") do
    bad_stream.generate(packet, label: "bad-stream")
  end)

  canceled = generator.new([event.call("{")])
  canceled.generate(packet, label: "cancel", cancel: true)
  check.call("cancellation after first output records no completed review", canceled.saved.dig("cancel-response.json", "status") == "intentionally_canceled" &&
    canceled.saved.dig("cancel-response.json", "completed_review") == false)

  terminal_first = generator.new([event.call(JSON.generate(response), stop: true)])
  check.call("cancellation refuses a first event that is already terminal", raises.call(Pilot::Stop, "cancellation not exercised") do
    terminal_first.generate(packet, label: "terminal-cancel", cancel: true)
  end && terminal_first.saved["terminal-cancel-failure.json"]["message"].include?("first content was terminal"))
end

# Exercise start_server's startup classification with a fake child identity and
# local method overrides. No executable is spawned and no socket is touched.
startup_probe = Class.new(Pilot) do
  attr_accessor :health, :resource_error
  def initialize
    super
    @health = { "status" => "loading" }
    @port_checks = 0
    @clock = [0.0, 0.0, 181.0]
  end
  def port_closed? = (@port_checks += 1) == 1
  def endpoint_owned! = true
  def now = (@clock.shift || 181.0)
  def http(*) = (raise resource_error if resource_error; health)
  def save(*) = nil
end
original_spawn = Process.method(:spawn)
original_waitpid = Process.method(:waitpid)
original_file_read = File.method(:read)
begin
  Process.define_singleton_method(:spawn) { |*| 424_244 }
  Process.define_singleton_method(:waitpid) { |*| nil }
  File.define_singleton_method(:read) { |path, *args, **kwargs| path == "/proc/424244/stat" ? "synthetic-stat" : original_file_read.call(path, *args, **kwargs) }
  Dir.mktmpdir("amd-reviewer-m2-startup-") do |directory|
    deadline_probe = startup_probe.new
    deadline_probe.instance_variable_set(:@output, directory)
    check.call("HTTP 200 without health status ok cannot pass startup and reaches deadline", raises.call(Pilot::Stop, "startup deadline") do
      deadline_probe.start_server("not-ready")
    end)

    resource_probe = startup_probe.new
    resource_probe.instance_variable_set(:@output, directory)
    resource_probe.resource_error = Pilot::Stop.new("AMD thermal bound")
    check.call("startup propagates a resource abort instead of swallowing it as retryable", raises.call(Pilot::Stop, "AMD thermal bound") do
      resource_probe.start_server("resource-abort")
    end)
  end
ensure
  Process.define_singleton_method(:spawn, original_spawn)
  Process.define_singleton_method(:waitpid, original_waitpid)
  File.define_singleton_method(:read, original_file_read)
end

# Reap only this verifier's process group; the instance fakes the already-closed
# endpoint after the child exits. No candidate binary or GPU is involved.
child_owner = Pilot.new
def child_owner.port_closed? = true
child_pid = Process.spawn("sleep", "30", pgroup: true, in: File::NULL, out: File::NULL, err: File::NULL)
child_owner.instance_variable_set(:@child, child_pid)
child_owner.stop_server
check.call("teardown reaps its owned synthetic child and confirms closed endpoint",
           child_owner.instance_variable_get(:@child).nil? &&
             raises.call(Errno::ECHILD) { Process.waitpid(child_pid, Process::WNOHANG) })

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
