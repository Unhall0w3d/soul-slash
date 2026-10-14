#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "net/http"
require "timeout"
require "time"
require_relative "support/continuity_model_cases_a23"
require_relative "../lib/soul_core/continuity_lab/qwen_host_observer"
require_relative "../lib/soul_core/continuity_lab/qwen_stream_response"

# An experimental foreground runner, not a change to the production broker.
class ContinuityModelComparisonA23
  class SuiteDeadline < Exception; end
  class ResourceStop < Exception; end
  Lab = SoulCore::ContinuityLab
  Cases = Lab::ContinuityModelCasesA23
  ROOT = File.expand_path("..", __dir__)
  SERVER = Lab::QwenHostObserver::SERVER
  MODEL8 = Lab::QwenHostObserver::MODEL
  UNIT = "/home/bhones/.config/systemd/user/llama-server.service"
  ASSETS = File.join(__dir__, "support/continuity_model_assets_a23.json")
  MODEL_ROOT = "/home/bhones/ai_models/continuity-a23"
  SERVER_SHA = "9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81"
  MODEL8_SHA = "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785"
  GRAMMAR = File.read(File.join(ROOT, "lib/soul_core/continuity_lab/qwen_reply_a18.gbnf"))
  COMMON = { "top_k" => 20, "min_p" => 0.0, "repeat_penalty" => 1.0,
    "presence_penalty" => 0.0, "seed" => 4242, "cache_prompt" => false,
    "stream" => true, "n_predict" => 768, "grammar" => GRAMMAR }.freeze
  SETTINGS = {
    "qwen8" => COMMON.merge("temperature" => 0.6, "top_p" => 0.95, "repeat_penalty" => 1.05, "presence_penalty" => 0.5),
    "qwen35" => COMMON.merge("temperature" => 0.7, "top_p" => 0.8, "presence_penalty" => 1.5),
    "ministral14" => COMMON.merge("temperature" => 0.05, "top_p" => 1.0, "top_k" => 0),
    "qwen30" => COMMON.merge("temperature" => 0.7, "top_p" => 0.8)
  }.freeze

  def initialize
    @commands = SoulCore::BoundedCommandRunner.new
    @child = nil
    @restore_required = false
    @port = 8082
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def command(*argv, seconds: 10)
    result = @commands.run(*argv, timeout_seconds: seconds, max_output_bytes: 16_384)
    raise "Command failed #{argv.first}: #{result.stderr}" unless result.success? && !result.truncated
    result.stdout
  end

  def save(name, data)
    File.open(File.join(@output, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(JSON.pretty_generate(data) + "\n")
      file.flush
      file.fsync
    end
  end

  def http(path, payload = nil, seconds: 10)
    raise "Unapproved route" unless %w[/health /props /slots /apply-template /tokenize /completion].include?(path)
    client = Net::HTTP.new("127.0.0.1", @port, nil)
    client.open_timeout = 2
    client.read_timeout = client.write_timeout = seconds
    client.max_retries = 0
    request = payload ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload) if payload
    Timeout.timeout(seconds) do
      client.start do |connection|
        connection.request(request) do |response|
          raise "HTTP #{response.code} #{path}" unless response.code == "200"
          if block_given?
            response.read_body { |chunk| yield chunk }
          else
            bytes = +""
            response.read_body do |chunk|
              bytes << chunk
              raise "Response too large" if bytes.bytesize > 524_288
            end
            return JSON.parse(bytes)
          end
        end
      end
    end
  end

  def unit
    command("systemctl", "--user", "show", "llama-server.service", "--property=ActiveState,SubState,MainPID", "--no-pager").lines.to_h { |line| line.strip.split("=", 2) }
  end

  def snapshot
    gpu = command("nvidia-smi", "--query-gpu=name,memory.used,memory.free,temperature.gpu,utilization.gpu", "--format=csv,noheader,nounits")
    memory = File.read("/proc/meminfo").lines.filter_map { |line| match = line.match(/^(MemAvailable|SwapFree|SwapTotal):\s+(\d+)/); [match[1], match[2].to_i] if match }.to_h
    paging = File.read("/proc/vmstat").lines.filter_map { |line| key, value = line.split; [key, value.to_i] if %w[pswpin pswpout].include?(key) }.to_h
    { "at" => Time.now.utc.iso8601(6), "gpu" => gpu.strip, "memory_kib" => memory, "paging_pages" => paging }
  end

  def check_idle(pid)
    Lab::QwenHostObserver.validate_slots!(http("/slots"))
    pids = command("nvidia-smi", "--query-compute-apps=pid", "--format=csv,noheader,nounits").lines.map { |line| Integer(line.strip) }
    raise "Unexpected NVIDIA compute client" unless pids == [pid]
    sample = snapshot
    validate_resources(sample)
    sample
  end

  def validate_resources(sample)
    raise ResourceStop, "GPU thermal limit" if sample.fetch("gpu").split(",")[3].to_i >= 80
    raise ResourceStop, "Insufficient available RAM" if sample.dig("memory_kib", "MemAvailable") < 4 * 1024 * 1024
  end

  def verify_asset(path, size, sha)
    stat = File.lstat(path)
    raise "Unsafe asset" unless stat.file? && !stat.symlink? && stat.nlink == 1 && File.realpath(path) == path
    raise "Asset size mismatch" unless stat.size == size
    raise "Asset digest mismatch" unless Digest::SHA256.file(path).hexdigest == sha
  end

  def candidate_args(id, path)
    args = [SERVER, "--model", path, "--alias", "continuity-a23-#{id}", "--host", "127.0.0.1", "--port", "8095",
      "--jinja", "--split-mode", "none", "--main-gpu", "0", "--ctx-size", "4096",
      "--predict", "768", "--threads", "8", "--threads-batch", "8", "--parallel", "1",
      "--batch-size", "1024", "--ubatch-size", "256", "--cache-type-k", "f16", "--cache-type-v", "f16",
      "--flash-attn", "off", "--fit", "on", "--fit-target", "1024", "--no-context-shift", "--no-warmup"]
    args += ["--cpu-moe"] if %w[qwen35 qwen30].include?(id)
    args
  end

  def start_candidate(id, path)
    @port = 8095
    begin
      probe = TCPSocket.new("127.0.0.1", @port)
      probe.close
      raise "Candidate port already occupied"
    rescue Errno::ECONNREFUSED
      # Only a verified unused local endpoint is acceptable.
    end
    args = candidate_args(id, path)
    save("#{id}-launch.json", { "argv" => args, "environment" => { "CUDA_VISIBLE_DEVICES" => "0" } })
    log = File.open(File.join(@output, "#{id}-server.log"), File::WRONLY | File::CREAT | File::EXCL, 0o600)
    started = now
    @child = Process.spawn({ "CUDA_VISIBLE_DEVICES" => "0" }, *args, out: log, err: log, pgroup: true)
    log.close
    deadline = now + 240
    loop do
      if Process.waitpid(@child, Process::WNOHANG)
        status = $?.exitstatus
        @child = nil
        raise "Candidate startup exited #{status}"
      end
      begin
        break if http("/health", seconds: 2)["status"] == "ok"
      rescue StandardError
        raise "Candidate startup timeout" if now >= deadline
        sleep 0.5
      end
    end
    props = http("/props")
    raise "Candidate identity mismatch" unless props["model_path"] == path && props["model_alias"] == "continuity-a23-#{id}" && props["build_info"] == "b9851-0eca4d490" && props["total_slots"] == 1 && props.dig("default_generation_settings", "n_ctx") == 4096
    save("#{id}-props.json", props.merge("startup_seconds" => now - started, "template_sha256" => Digest::SHA256.hexdigest(props.fetch("chat_template"))))
    @child
  end

  def stop_candidate
    return unless @child
    pid = @child
    Thread.handle_interrupt(Interrupt => :never, SuiteDeadline => :never, ResourceStop => :never) do
      begin
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH
        # Still reap the owned child if it has just exited.
      end
      deadline = now + 15
      final_deadline = deadline + 5
      killed = false
      loop do
        begin
          break if Process.waitpid(pid, Process::WNOHANG)
        rescue Errno::ECHILD
          break
        end
        raise "Owned candidate could not be reaped" if now >= final_deadline
        if now >= deadline && !killed
          Process.kill("KILL", -pid)
          killed = true
        end
        sleep 0.1
      end
      begin
        Process.kill(0, -pid)
        raise "Owned candidate process group survived reaping"
      rescue Errno::ESRCH
        @child = nil
      end
    end
  end

  def with_restoration
    @restore_required = true
    yield
  ensure
    # Finish bounded recovery despite a second cancellation request. SIGKILL or
    # host loss still requires manual recovery from the retained launch receipt.
    previous = %w[INT TERM].to_h { |signal| [signal, Signal.trap(signal, "IGNORE")] }
    begin
      Thread.handle_interrupt(Interrupt => :never, SuiteDeadline => :never, ResourceStop => :never) { restore }
    ensure
      previous.each { |signal, handler| Signal.trap(signal, handler) }
    end
  end

  def generate(id, case_id, messages, pid, limit: 768)
    before = check_idle(pid)
    template = http("/apply-template", { "messages" => messages, "add_generation_prompt" => true,
      "chat_template_kwargs" => { "enable_thinking" => false } })
    prompt = template.fetch("prompt")
    raise "Invalid template" unless prompt.is_a?(String) && !prompt.empty? && prompt.bytesize < 65_536
    tokens = http("/tokenize", { "content" => prompt, "add_special" => true, "parse_special" => true }).fetch("tokens")
    raise "Input token bound" unless tokens.is_a?(Array) && tokens.length.between?(1, 3072) && tokens.all? { |token| token.is_a?(Integer) }
    payload = SETTINGS.fetch(id).merge("prompt" => tokens, "n_predict" => limit)
    save("#{id}-#{case_id}-request.json", { "messages" => messages, "prompt" => prompt, "tokens" => tokens,
      "settings" => payload.reject { |key, _| key == "prompt" }, "before" => before })
    started = now
    first = nil
    samples = []
    owner = Thread.current
    monitor = Thread.new do
      loop do
        sleep 2
        sample = snapshot
        samples << sample
        validate_resources(sample)
      end
    rescue Exception => error
      owner.raise(error) unless error.is_a?(SystemExit)
    end
    stream = Lab::QwenStreamResponse.new(on_progress: ->(event) { first ||= now - started unless event.dig("fragment", "content").to_s.empty? })
    begin
      http("/completion", payload, seconds: 120) { |chunk| stream.feed(chunk) }
      result = stream.finish
      raise "Input count/truncation mismatch" unless result["tokens_evaluated"] == tokens.length && result["truncated"] == false
      row = { "case_id" => case_id, "model" => id, "seconds" => now - started, "first_token_seconds" => first,
        "input_tokens" => tokens.length, "raw" => result, "before" => before, "after" => snapshot, "samples" => samples }
      save("#{id}-#{case_id}-response.json", row)
      row
    rescue StandardError, Interrupt, SuiteDeadline, ResourceStop => error
      save("#{id}-#{case_id}-failure.json", { "error" => error.class.name, "message" => error.message, "seconds" => now - started, "partial" => stream.diagnostic })
      raise
    ensure
      monitor.kill
      monitor.join
    end
  end

  def evaluate_model(id, pid)
    puts "WARMUP #{id}"
    generate(id, "warmup", [{ "role" => "system", "content" => Lab::DirectEvidence::PROTOCOL }, { "role" => "user", "content" => "Say hello briefly." }], pid, limit: 48)
    rows = []
    Cases.groups.each do |group|
      history = []
      group.fetch("cases").each_with_index do |spec, index|
        case_id = spec.fetch("id")
        puts "START #{id} #{case_id}"
        row = generate(id, case_id, Cases.messages(group: group, spec: spec, history: history), pid)
        begin
          reply = JSON.parse(row.dig("raw", "content"))
          raise "Invalid reply shape" unless reply.is_a?(Hash) && reply.keys.sort == %w[action content] && reply["action"] == "reply" && reply["content"].is_a?(String)
          row["answer"] = reply.fetch("content")
          row["screen"] = Cases.mechanical_screen(spec: spec, text: row.fetch("answer"))
          row["status"] = row.dig("raw", "stop_type") == "limit" ? "output_limit" : "returned"
          history << { "user" => spec.fetch("content"), "assistant" => row.fetch("answer") }
        rescue JSON::ParserError, RuntimeError => error
          row["status"] = "invalid_output"
          row["error"] = error.message
        end
        rows << row
        save("#{id}-#{case_id}-assessment.json", row)
        puts "RESULT #{id} #{case_id} #{row['status']} #{row['seconds'].round(2)}s missing=#{row.dig('screen', 'missing')}"
        if row["status"] != "returned"
          group.fetch("cases").drop(index + 1).each do |skipped|
            skip = { "model" => id, "case_id" => skipped.fetch("id"), "status" => "skipped_dependency", "because" => case_id }
            rows << skip
            save("#{id}-#{skipped.fetch('id')}-assessment.json", skip)
          end
          break
        end
      end
    end
    save("#{id}-summary.json", { "model" => id, "expected_cases" => 15, "results" => rows, "assessment" => "regex_screen_requires_semantic_review" })
  end

  def restore
    stop_candidate
    return unless @restore_required
    raise "Baseline service file changed" unless Digest::SHA256.file(UNIT).hexdigest == @unit_sha
    command("systemctl", "--user", "start", "llama-server.service", seconds: 120)
    @port = 8082
    deadline = now + 120
    loop do
      begin
        Lab::QwenHostObserver.validate_props!(http("/props", seconds: 3))
        state = unit
        raise "Baseline not running" unless state["ActiveState"] == "active" && state["SubState"] == "running"
        raise "Baseline health not OK" unless http("/health")["status"] == "ok"
        observer = Lab::QwenHostObserver.new(root: ROOT, client: Lab::QwenTransport.new, expected_pid: Integer(state.fetch("MainPID")))
        observer.call
        sample = check_idle(Integer(state.fetch("MainPID")))
        save("restoration.json", { "verified" => true, "unit" => state, "host" => observer.last_evidence, "sample" => sample, "unit_sha256" => @unit_sha })
        @restore_required = false
        puts "RESTORED baseline Qwen3-8B; active, correct template, idle"
        return
      rescue StandardError
        raise if now >= deadline
        sleep 0.5
      end
    end
  end

  def run
    File.umask(0o077)
    @output = File.join(ROOT, "Soul/runtime/qualification/continuity-model-a23-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
    Dir.mkdir(@output, 0o700)
    puts "EVIDENCE #{@output}"
    assets = JSON.parse(File.read(ASSETS))
    raise "Runtime digest changed" unless Digest::SHA256.file(SERVER).hexdigest == SERVER_SHA
    verify_asset(MODEL8, 5_027_783_488, MODEL8_SHA)
    assets.each_value { |asset| verify_asset(File.join(MODEL_ROOT, asset.fetch("file")), asset.fetch("size"), asset.fetch("sha256")) }
    @unit_sha = Digest::SHA256.file(UNIT).hexdigest
    source_paths = [__FILE__, ASSETS, File.join(ROOT, "scripts/support/continuity_model_cases_a23.rb")] + Dir.glob(File.join(ROOT, "lib/soul_core/continuity_lab/*.rb"))
    save("protocol.json", { "schema" => "soul.continuity.model_comparison.a23", "assets" => assets, "baseline_model_sha256" => MODEL8_SHA,
      "runtime_sha256" => SERVER_SHA, "unit_sha256" => @unit_sha, "settings" => SETTINGS, "groups" => Cases.groups,
      "sources" => source_paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }, "budget_seconds" => 2700,
      "semantic_review_required" => true, "production_qualification" => false })
    leases = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
    leases.with_control_lock do
      raise "Retained model leases" unless leases.leases_for_quiescent_admission_unlocked.empty?
      state = unit
      pid = Integer(state.fetch("MainPID"))
      observer = Lab::QwenHostObserver.new(root: ROOT, client: Lab::QwenTransport.new, expected_pid: pid)
      observer.call
      save("initial.json", { "unit" => state, "host" => observer.last_evidence, "snapshot" => check_idle(pid) })
      with_restoration do
        Timeout.timeout(2700, SuiteDeadline) do
          evaluate_model("qwen8", pid)
          observer.call
          check_idle(pid)
          @restore_required = true
          command("systemctl", "--user", "stop", "llama-server.service", seconds: 45)
          raise "Baseline failed to stop" unless unit["ActiveState"] == "inactive"
          assets.each do |id, asset|
            begin
              puts "LOAD #{id}"
              candidate_pid = start_candidate(id, File.join(MODEL_ROOT, asset.fetch("file")))
              evaluate_model(id, candidate_pid)
            rescue StandardError => error
              save("#{id}-model-failure.json", { "class" => error.class.name, "message" => error.message })
              puts "MODEL_FAILED #{id}: #{error.message}"
            ensure
              stop_candidate
            end
          end
        end
      end
    end
    puts "FINISHED #{@output}"
  rescue StandardError, Interrupt, SuiteDeadline, ResourceStop => error
    save("failure.json", { "class" => error.class.name, "message" => error.message, "restoration_required" => @restore_required }) if @output
    warn "FAILED: #{error.class}: #{error.message}"
    raise
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Use --approved-comparison" unless ARGV == ["--approved-comparison"]
  $stdout.sync = true
  Signal.trap("TERM") { raise Interrupt, "termination requested" }
  ContinuityModelComparisonA23.new.run
end
