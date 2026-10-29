#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "openssl"
require "json"
require "net/http"
require "socket"
require "time"
require "timeout"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "support/chat_replacement_evaluator"

# Foreground qualification only. No service transitions, production selection,
# real tools, cloud calls, or persistent monitoring are part of this runner.
class ChatReplacementTrial
  class Abort < Exception; end
  ROOT = File.expand_path("..", __dir__)
  QUALIFICATION = File.join(ROOT, "Soul/runtime/qualification")
  SERVER = "/home/bhones/.local/opt/llama.cpp-b9851-cuda-sm61/bin/llama-server"
  SERVER_SHA = "9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81"
  BUILD = "b9851-0eca4d490"
  PORT = 18082
  CONTEXT = 4096
  GENERATION_LIMIT = 768
  TOTAL_SECONDS = 2700
  REQUEST_SECONDS = 120
  MAX_GENERATIONS = 48
  MAX_RESPONSE_BYTES = 524_288
  COOLING_SECONDS = 180
  PROTOCOLS = {
    "baseline-v1" => { "cutoff_c" => 80, "paced" => false }.freeze,
    "cooling-v2" => { "cutoff_c" => 88, "paced" => true }.freeze
  }.freeze
  ASSETS = JSON.parse(File.read(File.join(__dir__, "support/chat_replacement_assets.json"))).freeze
  Contract = SoulCore::ConversationProviderContract

  class Client < SoulCore::ConversationProviderClient
    def initialize(owner:, **arguments)
      @owner = owner
      super(**arguments)
    end

    private

    def post_json(uri, payload, provider:, timeout_seconds:)
      raise Abort, "Non-trial endpoint refused" unless uri.to_s == "http://127.0.0.1:18082/v1/chat/completions"
      @owner.generate(payload)
    end
  end

  attr_reader :output

  def initialize(candidate:, assets:, protocol: "baseline-v1")
    @protocol_id = protocol
    @protocol = PROTOCOLS.fetch(protocol)
    @candidate = candidate
    @asset = ASSETS.fetch(candidate)
    @assets = File.expand_path(assets)
    raise ArgumentError, "Assets must be inside qualification storage" unless @assets.start_with?("#{QUALIFICATION}/")
    stat = File.lstat(@assets)
    raise ArgumentError, "Unsafe asset directory" unless File.realpath(@assets) == @assets &&
      stat.directory? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
    @model = File.join(@assets, @asset.fetch("file"))
    @commands = SoulCore::BoundedCommandRunner.new
    @pid = nil
    @monitor = nil
    @generation_count = 0
    @samples = []
    @cooling_events = []
    @cleanup = nil
  end

  def run
    started = now
    File.umask(0o077)
    @output = Dir.mktmpdir("chat-replacement-#{@protocol_id}-#{@candidate}-", QUALIFICATION)
    puts JSON.generate("state" => "preflight", "output" => @output)
    $stdout.flush
    state = "failed"
    error = nil
    previous_signals = {}
    begin
      verify_file!(@model, @asset.fetch("size"), @asset.fetch("sha256"))
      raise Abort, "Server digest mismatch" unless Digest::SHA256.file(SERVER).hexdigest == SERVER_SHA
      @before = protected_state
      raise Abort, "Production NVIDIA service is not inactive" unless @before.fetch("unit").include?("ActiveState=inactive")
      raise Abort, "Trial port occupied" unless port_closed?
      sample = sample_resources
      @desktop_baseline = desktop_baseline(sample)
      validate_resources!(sample, admission: true)
      save("preflight.json", "protected" => @before, "resources" => sample,
        "desktop_baseline" => @desktop_baseline,
        "protocol_id" => @protocol_id, "thermal_policy" => @protocol,
        "asset" => @asset, "server_sha256" => SERVER_SHA, "source_hashes" => source_hashes)
      save("source-snapshot.json", source_hashes.keys.to_h { |path| [path, File.read(File.join(ROOT, path))] })
      previous_signals = %w[INT TERM].to_h { |signal| [signal, Signal.trap(signal) { raise Abort, "Canceled by #{signal}" }] }
      # Follow-up cooling and preflight count against the same candidate budget;
      # reserve a minute for bounded monitor/owned-child teardown and read-back.
      remaining = @protocol.fetch("paced") ? TOTAL_SECONDS - (now - started) - 60 : TOTAL_SECONDS
      raise Abort, "Candidate wall-clock limit during preflight" unless remaining.positive?
      Timeout.timeout(remaining, Abort, "Candidate wall-clock limit") do
        pace_resources(stage: "before_start", trigger_c: 41, resume_c: 40, admission: true)
        start
        start_monitor
        feasibility
        evaluation_root = Dir.mktmpdir("isolated-state-", @output)
        evaluate(evaluation_root) do |record|
          index = record["kind"] == "case" ? "#{record.fetch('case_id')}-#{record.fetch('sample')}" : "continuity-#{record.fetch('turn')}"
          index = "#{record.fetch('condition').tr('/', '-')}-#{index}" if record.key?("condition")
          save("case-#{index}.json", record)
          puts JSON.generate("state" => "case_recorded", "case" => index)
          $stdout.flush
        end
        state = "completed_pending_semantic_review"
      end
    rescue Abort, StandardError => exception
      error = { "class" => exception.class.name, "message" => exception.message }
    ensure
      # Cleanup has its own finite limit and must not be cut short by a repeated
      # signal or the trial watchdog. Never forget an unreaped owned process.
      %w[INT TERM].each { |signal| Signal.trap(signal, "IGNORE") } unless previous_signals.empty?
      Thread.handle_interrupt(Abort => :never) do
        begin
          cleanup_owned_runtime
          @cleanup = { "owned_child_reaped" => @pid.nil?, "port_closed" => port_closed? }
          raise Abort, "Trial port remains occupied; no unrelated process was stopped" unless @cleanup.fetch("port_closed")
          @after = protected_state if @before
          raise Abort, "Protected production state changed during trial" if @before && @after != @before
        rescue Abort, StandardError => cleanup_error
          state = "failed"
          error = { "class" => cleanup_error.class.name, "message" => cleanup_error.message, "prior_error" => error }
        end
      end
      previous_signals.each { |signal, handler| Signal.trap(signal, handler) }
      save("resources.json", @samples)
      save("cooling.json", @cooling_events)
      save("receipt.json", "state" => state, "candidate" => @candidate, "generation_count" => @generation_count,
        "protocol_id" => @protocol_id, "thermal_policy" => @protocol,
        "wall_seconds" => (now - started).round(3),
        "cooling_ms" => @cooling_events.sum { |event| event.fetch("elapsed_ms") }.round(2),
        "error" => error, "cleanup" => @cleanup, "owned_pid_if_unreaped" => @pid, "protected_after" => @after,
        "completed_at" => Time.now.utc.iso8601(6))
    end
    puts JSON.generate("state" => state, "output" => @output, "error" => error)
    state == "completed_pending_semantic_review"
  end

  def context_limit = CONTEXT
  def request_seconds = REQUEST_SECONDS

  def generate(payload)
    raise Abort, "Generation budget exceeded" if @generation_count >= max_generations
    pace_resources(stage: "before_request_#{@generation_count + 1}", trigger_c: 75, resume_c: 55)
    @generation_count += 1
    # Both candidates retain their own sampling conventions and embedded
    # templates. No Qwen grammar, suffix, identity tuning, or repetition policy.
    payload = prepare_payload(payload)
    raise Abort, "Wrong request alias" unless payload["model"] == @candidate
    raise Abort, "Unexpected generation ceiling" unless payload["max_tokens"].is_a?(Integer) &&
      payload["max_tokens"].between?(1, generation_limit)
    prefix = format("request-%02d", @generation_count)
    save("#{prefix}.json", payload)
    template_input = payload.slice("messages", "tools", "tool_choice", "chat_template_kwargs")
    template_input["add_generation_prompt"] = true
    template = json_http("/apply-template", template_input)
    prompt = template.fetch("prompt")
    raise Abort, "Unbounded or invalid template output" unless prompt.is_a?(String) && prompt.bytesize.between?(1, 65_536)
    tokens = json_http("/tokenize", { "content" => prompt, "add_special" => false, "parse_special" => true }).fetch("tokens")
    raise Abort, "Input exceeds declared context headroom" unless tokens.is_a?(Array) &&
      tokens.length + payload.fetch("max_tokens") <= context_limit - 32
    save("#{prefix}-template.json", "prompt" => prompt, "input_tokens" => tokens.length)
    started = now
    response = http("/v1/chat/completions", payload, seconds: request_seconds)
    elapsed = ((now - started) * 1000).round(2)
    save("#{prefix}-raw.json", "http_status" => response.code.to_i, "body" => response.body, "latency_ms" => elapsed)
    [response, elapsed]
  rescue Timeout::Error, IOError, SystemCallError => error
    raise Abort, "Transport interrupted; no further generation: #{error.class}: #{error.message}"
  end

  def self.validate_sample!(sample, expected_pid:, admission:, desktop_baseline: [], cutoff_c: 80)
    raise Abort, "Unapproved NVIDIA cutoff" unless [80, 88].include?(cutoff_c)
    raise Abort, "Unexpected NVIDIA device" unless sample.fetch("name") == "NVIDIA GeForce GTX 1070"
    raise Abort, "NVIDIA #{cutoff_c} C cutoff" unless sample.fetch("temperature_c") < cutoff_c
    raise Abort, "Less than 4 GiB available RAM" unless sample.fetch("ram_available_kib") >= 4 * 1024 * 1024
    allowed = expected_pid ? [expected_pid] : []
    desktop_baseline.each do |baseline|
      current = sample.fetch("processes", []).find { |process| process["pid"] == baseline.fetch("pid") }
      next unless current
      identity_keys = %w[pid uid comm argv0 start_ticks]
      raise Abort, "Desktop process identity changed" unless current.slice(*identity_keys) == baseline.slice(*identity_keys)
      raise Abort, "Desktop NVIDIA allocation exceeds 64 MiB" unless current.fetch("used_mib") <= 64
      allowed << current.fetch("pid")
    end
    raise Abort, "Another NVIDIA compute process is present" unless (sample.fetch("compute_pids") - allowed).empty?
    raise Abort, "Insufficient free NVIDIA VRAM for admission" if admission && sample.fetch("free_mib") < 6656
  end

  def self.argv(candidate, model)
    [SERVER, "--model", model, "--alias", candidate, "--host", "127.0.0.1", "--port", PORT.to_s,
      "--device", "CUDA0", "--split-mode", "none", "--main-gpu", "0", "--jinja",
      "--ctx-size", CONTEXT.to_s, "--predict", GENERATION_LIMIT.to_s, "--parallel", "1",
      "--threads", "8", "--threads-batch", "8", "--batch-size", "1024", "--ubatch-size", "256",
      "--cache-type-k", "f16", "--cache-type-v", "f16", "--flash-attn", "off",
      "--fit", "on", "--fit-target", "1024", "--no-context-shift", "--no-warmup",
      "--reasoning", "off"]
  end

  private

  def max_generations = MAX_GENERATIONS
  def generation_limit = GENERATION_LIMIT

  def prepare_payload(payload)
    payload = payload.merge("seed" => 731_000 + @generation_count, "cache_prompt" => false)
    %w[top_p top_k].each { |key| payload[key] = @asset[key] if @asset.key?(key) }
    payload
  end

  def evaluate(root, &block)
    SoulCore::ChatReplacementEvaluator.new(root: root, client: client(root), provider: provider,
      temperature: @asset.fetch("temperature"), reasoning_mode: @asset.fetch("reasoning_mode")).run(&block)
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def pace_resources(stage:, trigger_c:, resume_c:, admission: false)
    return unless @protocol && @protocol.fetch("paced")
    started = now
    event = { "stage" => stage, "state" => "failed", "waited" => false }
    begin
      sample = sample_resources
      @samples << sample
      validate_resources!(sample, admission: admission)
      event["from_c"] = sample.fetch("temperature_c")
      if sample.fetch("temperature_c") >= trigger_c
        event["waited"] = true
        puts JSON.generate("state" => "cooling", "stage" => stage,
          "temperature_c" => sample.fetch("temperature_c"), "resume_c" => resume_c)
        $stdout.flush
        until sample.fetch("temperature_c") <= resume_c
          raise Abort, "Cooling deadline exceeded" if now - started >= COOLING_SECONDS
          sleep 1
          sample = sample_resources
          @samples << sample
          # A hot sample or foreign workload aborts even while waiting. Cooling
          # is not permission to defer the hard cutoff or resource ownership gate.
          validate_resources!(sample, admission: admission)
          raise Abort, "Cooling deadline exceeded" if now - started >= COOLING_SECONDS
        end
      end
      event["to_c"] = sample.fetch("temperature_c")
      event["state"] = "complete"
    ensure
      event["elapsed_ms"] = ((now - started) * 1000).round(2)
      @cooling_events << event
    end
  end

  def save(name, data)
    File.open(File.join(@output, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(JSON.pretty_generate(data) + "\n")
      file.flush
      file.fsync
    end
  end

  def source_hashes
    [__FILE__, File.join(__dir__, "support/chat_replacement_assets.json"),
      File.join(__dir__, "support/chat_replacement_cases.rb"),
      File.join(__dir__, "support/chat_replacement_evaluator.rb"),
      File.join(ROOT, "lib/soul_core/conversation_provider_client.rb"),
      File.join(ROOT, "lib/soul_core/conversation_context_builder.rb"),
      File.join(ROOT, "lib/soul_core/conversation_identity_profile.rb")].to_h do |path|
      [path.delete_prefix("#{ROOT}/"), Digest::SHA256.file(path).hexdigest]
    end
  end

  def command(*args)
    result = @commands.run(*args, timeout_seconds: 5, max_output_bytes: 16_384)
    raise Abort, "Read-only check failed: #{args.first}: #{result.status}" unless result.success? && !result.truncated
    result.stdout
  end

  def protected_state
    { "unit" => command("systemctl", "--user", "show", "llama-server.service",
        "--property=ActiveState,SubState,MainPID", "--no-pager"),
      "files" => [".env", "Soul/config/model_runtime_profiles.local.yaml",
        "Soul/runtime/model_runtime/selected_profile.json"].to_h do |name|
          path = File.join(ROOT, name)
          [name, File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil]
        end }
  end

  def sample_resources
    line = command("nvidia-smi", "-i", "0", "--query-gpu=name,memory.used,memory.free,temperature.gpu",
      "--format=csv,noheader,nounits").strip
    raise Abort, "Unexpected NVIDIA telemetry rows" unless line.lines.length == 1
    name, used, free, temperature = line.split(",").map(&:strip)
    processes = command("nvidia-smi", "-i", "0", "--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits")
      .lines.map do |row|
        pid, used_mib = row.strip.split(",").map { |value| Integer(value.strip) }
        proc_path = "/proc/#{pid}"
        { "pid" => pid, "used_mib" => used_mib, "uid" => File.stat(proc_path).uid,
          "comm" => File.read("#{proc_path}/comm").strip,
          "argv0" => File.binread("#{proc_path}/cmdline", 4096).split("\0").first,
          "start_ticks" => Integer(File.read("#{proc_path}/stat").split(") ", 2).last.split.fetch(19)) }
      end
    ram = File.read("/proc/meminfo").match(/^MemAvailable:\s+(\d+)/)
    { "at" => Time.now.utc.iso8601(6), "name" => name, "used_mib" => Integer(used),
      "free_mib" => Integer(free), "temperature_c" => Integer(temperature),
      "compute_pids" => processes.map { |process| process.fetch("pid") }, "processes" => processes,
      "ram_available_kib" => Integer(ram[1]) }
  end

  def desktop_baseline(sample)
    processes = sample.fetch("processes")
    raise Abort, "Unexpected desktop baseline size" unless processes.length <= 1
    processes.each do |process|
      raise Abort, "Existing compute workload is not the small Plasma baseline" unless
        process["comm"] == "kwin_wayland" && process["argv0"] == "/usr/bin/kwin_wayland" &&
        process["uid"] == Process.uid && process["used_mib"] <= 64
      executable = File.stat("/usr/bin/kwin_wayland")
      raise Abort, "Untrusted Plasma executable path" unless executable.uid.zero? && (executable.mode & 0o022).zero?
    end
    processes
  end

  def validate_resources!(sample, admission: false)
    self.class.validate_sample!(sample, expected_pid: @pid, admission: admission,
      desktop_baseline: @desktop_baseline || [], cutoff_c: (@protocol || PROTOCOLS.fetch("baseline-v1")).fetch("cutoff_c"))
  end

  def port_closed?
    socket = Socket.tcp("127.0.0.1", PORT, connect_timeout: 2)
    socket.close
    false
  rescue Errno::ECONNREFUSED
    true
  end

  def verify_file!(path, size, digest)
    stat = File.lstat(path)
    raise Abort, "Unsafe asset" unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
      stat.uid == Process.uid && File.realpath(path) == path
    raise Abort, "Asset size mismatch" unless stat.size == size
    # OpenSSL accelerates the same full SHA-256 check; no metadata/hash cache.
    # Pin the opened inode and reject replacement or modification during hashing.
    fingerprint = ->(s) { [s.dev,s.ino,s.mode,s.uid,s.gid,s.nlink,s.size,s.mtime,s.ctime] }
    expected = fingerprint.call(stat)
    actual = File.open(path, "rb") do |file|
      raise Abort, "Asset changed before verification" unless fingerprint.call(file.stat) == expected
      hash = OpenSSL::Digest::SHA256.new
      buffer = +""
      hash.update(buffer) while file.read(1024 * 1024, buffer)
      raise Abort, "Asset changed during verification" unless fingerprint.call(file.stat) == expected &&
        fingerprint.call(File.lstat(path)) == expected && File.realpath(path) == path
      hash.hexdigest
    end
    raise Abort, "Asset digest mismatch" unless actual == digest
  end

  def start
    args = self.class.argv(@candidate, @model)
    # Inherited LLAMA_ARG/HF credentials and endpoints must not affect this
    # process. All model assets and endpoints are explicitly supplied.
    environment = ENV.keys.grep(/\A(?:LLAMA_|HF_|HUGGING_FACE_|CUDA_VISIBLE_DEVICES)/).to_h { |key| [key, nil] }
    environment["CUDA_VISIBLE_DEVICES"] = "0"
    save("launch.json", "argv" => args, "environment_overrides" => environment.keys)
    File.open(File.join(@output, "server.log"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |log|
      @pid = Process.spawn(environment, *args, out: log, err: log, pgroup: true)
    end
    save("owned-process.json", "pid" => @pid, "process_group" => @pid, "started_at" => Time.now.utc.iso8601(6))
    deadline = now + 240
    loop do
      validate_resources!(sample_resources)
      if Process.waitpid(@pid, Process::WNOHANG)
        @reaped_pid = @pid
        raise Abort, "Server exited during startup"
      end
      begin
        break if json_http("/health", nil, seconds: 2)["status"] == "ok"
      rescue StandardError
        raise Abort, "Startup timeout" if now >= deadline
        sleep 0.5
      end
      raise Abort, "Startup timeout" if now >= deadline
    end
    props = json_http("/props")
    raise Abort, "Server identity mismatch" unless server_identity_matches?(props)
    template = props.fetch("chat_template")
    raise Abort, "Gemma thinking switch absent" if @candidate == "gemma4-e4b-it" && !template.include?("enable_thinking")
    save("props.json", props.merge("template_sha256" => Digest::SHA256.hexdigest(template)))
  end

  def server_identity_matches?(props)
    props["model_path"] == @model && props["model_alias"] == @candidate &&
      props["build_info"] == BUILD && props["total_slots"] == 1 &&
      props.dig("default_generation_settings", "n_ctx") == context_limit
  end

  def start_monitor
    owner = Thread.current
    @monitor_stop = false
    @monitor = Thread.new do
      until @monitor_stop
        sample = sample_resources
        @samples << sample
        validate_resources!(sample)
        sleep 1
      end
    rescue Abort, StandardError => error
      owner.raise(Abort, "Resource monitor: #{error.message}") unless @monitor_stop
    end
  end

  def stop_monitor
    return unless @monitor
    @monitor_stop = true
    raise Abort, "Resource monitor did not stop" unless @monitor.join(20)
    @monitor = nil
  end

  def cleanup_owned_runtime
    begin
      stop_monitor
    ensure
      stop
    end
  end

  def stop
    return unless @pid
    pid = @pid
    # A child observed/reaped during startup must not receive a reused-PID kill.
    reaped = @reaped_pid == pid ? pid : Process.waitpid(pid, Process::WNOHANG)
    unless reaped
      Process.kill("TERM", -pid)
      deadline = now + 15
      until (reaped = Process.waitpid(pid, Process::WNOHANG)) || now >= deadline
        sleep 0.1
      end
      unless reaped
        Process.kill("KILL", -pid)
        Timeout.timeout(5, Abort, "Owned child could not be reaped") { Process.waitpid(pid) }
      end
    end
    begin
      Process.kill(0, -pid)
      raise Abort, "Owned process group still present"
    rescue Errno::ESRCH
      @pid = nil
    end
  rescue Errno::ECHILD
    raise Abort, "Owned child's reaping status is unknown; PID retained for inspection"
  end

  def provider
    @provider ||= Contract::ProviderDefinition.new(id: "local.chat_replacement_trial", label: @candidate,
      transport: "openai_compatible", endpoint: "http://127.0.0.1:#{PORT}/v1",
      model: @candidate, privacy_class: "local_only", configured: true,
      capabilities: %w[chat tools structured_output reasoning_control])
  end

  def client(root)
    Client.new(owner: self, root: root, env: { "SOUL_LOCAL_OPENAI_DIALECT" => "llamacpp" })
  end

  def feasibility
    root = Dir.mktmpdir("feasibility-state-", @output)
    probe_client = client(root)
    plain = probe(probe_client, [{ "role" => "user", "content" => "Reply with exactly HELLO and no other text." }])
    raise Abort, "Ordinary output feasibility failed" unless plain.content.strip == "HELLO"
    schema = { "type" => "json_schema", "json_schema" => { "name" => "probe", "strict" => true,
      "schema" => { "type" => "object", "properties" => { "n" => { "type" => "integer" } }, "required" => ["n"], "additionalProperties" => false } } }
    structured = probe(probe_client, [{ "role" => "user", "content" => 'Return exactly {"n":7} as JSON.' }], response_format: schema)
    raise Abort, "JSON feasibility failed" unless JSON.parse(structured.content) == { "n" => 7 }
    tool = { "type" => "function", "function" => { "name" => "read_marker", "description" => "Read one synthetic marker.",
      "parameters" => { "type" => "object", "properties" => { "id" => { "type" => "string" } }, "required" => ["id"], "additionalProperties" => false } } }
    messages = [{ "role" => "user", "content" => "Read marker M42 using read_marker, then tell me its color." }]
    call = probe(probe_client, messages, tools: [tool], tool_choice: "required", allow_tools: true)
    item = call.tool_calls.fetch(0)
    raise Abort, "Tool feasibility failed" unless call.tool_calls.length == 1 &&
      item.dig("function", "name") == "read_marker" && !item["id"].to_s.empty? &&
      JSON.parse(item.dig("function", "arguments")) == { "id" => "M42" }
    messages += [{ "role" => "assistant", "content" => call.content, "tool_calls" => call.tool_calls },
      { "role" => "tool", "tool_call_id" => item.fetch("id"), "name" => "read_marker", "content" => '{"color":"cobalt"}' }]
    final = probe(probe_client, messages, tools: [tool], tool_choice: "auto")
    raise Abort, "Tool round-trip feasibility failed" unless final.content.match?(/\bcobalt\b/i)
    save("feasibility.json", "state" => "passed", "probes" => 4, "separate_from_scored_cases" => true)
  end

  def probe(probe_client, messages, allow_tools: false, **options)
    messages = [{ "role" => "system", "content" => "You are a concise assistant. Use only supplied evidence." }] + messages
    request = Contract::RequestEnvelope.new(conversation_id: "feasibility", messages: messages, model: @candidate,
      temperature: @asset.fetch("temperature"), max_output_tokens: 128,
      reasoning_mode: @asset.fetch("reasoning_mode"), **options)
    response = probe_client.chat(provider: provider, request: request)
    raise Abort, "Feasibility provider error: #{response.error}" if response.error
    raise Abort, "Feasibility truncated" if response.finish_reason == "length"
    raise Abort, "Unexpected feasibility tool call" if !allow_tools && !response.tool_calls.empty?
    response
  end

  def json_http(path, payload = nil, seconds: 10)
    response = http(path, payload, seconds: seconds)
    raise "HTTP #{response.code} on #{path}" unless response.code == "200"
    JSON.parse(response.body)
  end

  def http(path, payload = nil, seconds:)
    raise Abort, "Unapproved endpoint path" unless %w[/health /props /apply-template /tokenize /v1/chat/completions].include?(path)
    connection = Net::HTTP.new("127.0.0.1", PORT, nil)
    connection.open_timeout = 2
    connection.read_timeout = connection.write_timeout = seconds
    connection.max_retries = 0
    request = payload ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload) if payload
    Timeout.timeout(seconds) do
      connection.start do |http|
        http.request(request) do |response|
          body = +"".b
          response.read_body do |chunk|
            body << chunk.b
            raise Abort, "Response exceeds byte bound" if body.bytesize > MAX_RESPONSE_BYTES
          end
          body.force_encoding(Encoding::UTF_8)
          raise Abort, "Invalid response UTF-8" unless body.valid_encoding?
          return Struct.new(:code, :body).new(response.code, body)
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  modes = { "--approved-local-trial" => "baseline-v1", "--approved-cooling-followup" => "cooling-v2" }
  abort "Usage: run-chat-replacement-trial.rb --approved-local-trial|--approved-cooling-followup CANDIDATE ASSETS_DIRECTORY" unless ARGV.length == 3 && modes.key?(ARGV[0])
  exit(ChatReplacementTrial.new(candidate: ARGV[1], assets: ARGV[2], protocol: modes.fetch(ARGV[0])).run ? 0 : 1)
end
