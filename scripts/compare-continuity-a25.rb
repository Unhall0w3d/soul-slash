#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "compare-amd-reviewer-m3b"
require_relative "support/continuity_cases_a25"
require_relative "support/continuity_protocol_a25"

# Detached experiment: reuse proven ownership/lease/thermal cleanup, not the
# historical review prompts or production streaming/answer parser.
class ContinuityComparisonA25 < AmdReviewerComparisonM3b
  Cases = ContinuityCasesA25
  Protocol = ContinuityProtocolA25
  WINDOW_SECONDS = 3600
  INPUT_LIMIT = 1536
  BRIEF = File.join(ROOT, "docs/soul/CONTINUITY_LAB_A25_BRIEF.md")
  INPUTS = [__FILE__, BRIEF, File.join(__dir__, "support/continuity_cases_a25.rb"),
    File.join(__dir__, "support/continuity_protocol_a25.rb")].freeze
  PARENT = File.join(ROOT, "Soul/runtime/qualification")
  QWEN_SHA = "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785"

  def self.frozen_protocol
    Cases.validate!
    { "schema" => "soul.continuity.a25.v1", "cases" => Cases.cases,
      "plans" => Protocol::SEEDS.to_h { |seed| [seed.to_s, Protocol.plan(seed: seed)] },
      "feasibility" => Protocol.feasibility_plan,
      "hashes" => INPUTS.to_h { |p| [File.expand_path(p), Digest::SHA256.file(p).hexdigest] },
      "input_limit" => INPUT_LIMIT, "window_seconds" => WINDOW_SECONDS,
      "candidate" => asset("qwen35"), "qwen_sha256" => QWEN_SHA,
      "prior_evidence_untouched" => true,
      "budget_interpretation" => "equal output-token and request-time ceilings, not FLOPs or equal realized work" }
  end

  def self.prepare
    File.umask(0o077)
    raise Stop, "unsafe evidence parent" unless File.realpath(PARENT) == PARENT && File.stat(PARENT).uid == Process.uid
    path = Dir.mktmpdir("continuity-a25-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-", PARENT)
    data = frozen_protocol
    data["revision"] = Contract.digest(data)
    File.open(File.join(path, "protocol.json"), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |f|
      f.write(JSON.pretty_generate(data) + "\n"); f.flush; f.fsync
    end
    path
  end

  def initialize(series:, seed:)
    super("qwen35")
    raise Stop, "unregistered seed" unless Protocol::SEEDS.include?(seed)
    @series, @seed = series, seed
    @results = {}
  end

  def preservation
    result = super
    result["hashes"].merge!(INPUTS.to_h { |p| [File.expand_path(p), Digest::SHA256.file(p).hexdigest] })
    result
  end

  def self.validate_effective!(body, payload)
    settings = body.dig("__verbose", "generation_settings")
    raise Stop, "effective settings unavailable" unless settings.is_a?(Hash)
    %w[temperature top_p top_k min_p presence_penalty repeat_penalty seed].each do |key|
      actual = settings[key]
      raise Stop, "effective setting mismatch: #{key}" unless actual.is_a?(Numeric) &&
        actual.finite? && (actual - payload.fetch(key)).abs < 0.00001
    end
    raise Stop, "effective output ceiling mismatch" unless settings["n_predict"] == payload.fetch("max_tokens")
    raise Stop, "unexpected model adapter" unless settings["lora"] == []
    actual_prompt = body.dig("__verbose", "prompt")
    raise Stop, "actual prompt unavailable" unless actual_prompt.is_a?(String) && actual_prompt.bytesize.between?(1, 65_536)
    grammar = settings["grammar"]
    if payload.dig("response_format", "type") == "json_schema"
      raise Stop, "strict grammar unavailable" unless grammar.is_a?(String) && !grammar.empty?
    end
    usage = body.fetch("usage")
    raise Stop, "observed input budget exceeded" unless usage["prompt_tokens"].is_a?(Integer) && usage["prompt_tokens"].between?(1, INPUT_LIMIT)
    raise Stop, "observed output budget exceeded" unless usage["completion_tokens"].is_a?(Integer) && usage["completion_tokens"].between?(0, payload.fetch("max_tokens"))
    raise Stop, "prompt cache reused" unless usage.dig("prompt_tokens_details", "cached_tokens") == 0
    true
  end

  def self.validate_native_branch!(model, thinking, template)
    raise Stop, "unknown native thinking condition" unless %w[qwen amd].include?(model) &&
      (thinking == true || thinking == false)
    # The pinned Qwen3 template leaves the opening think tag to generation;
    # Qwen3.5 prefills it. A shared '<think>' suffix rejects a valid Qwen3 ON
    # branch. OFF explicitly closes an empty reasoning segment in both models.
    suffix = if !thinking
               "<|im_start|>assistant\n<think>\n\n</think>\n\n"
             elsif model == "qwen"
               "<|im_start|>assistant\n"
             else
               "<|im_start|>assistant\n<think>\n"
             end
    raise Stop, "native thinking branch not attested" unless template.is_a?(String) &&
      template.encoding == Encoding::UTF_8 && template.valid_encoding? &&
      template.bytesize.between?(1, 65_536) && template.end_with?(suffix)
    true
  end

  # No arbitrary URL, redirect, retry or proxy. This native non-streaming route
  # preserves the backend's separation of reasoning and final-answer grammar.
  def native_http(model, path, payload, seconds:)
    raise Stop, "native route denied" unless %w[qwen amd].include?(model) &&
      %w[/apply-template /tokenize /v1/chat/completions].include?(path) && seconds.between?(1, 90)
    client = Net::HTTP.new("127.0.0.1", model == "qwen" ? 8082 : PORT, nil)
    client.open_timeout = 2
    client.read_timeout = client.write_timeout = seconds
    client.max_retries = 0
    request = Net::HTTP::Post.new(path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@api_key}" if model == "amd"
    request.body = JSON.generate(payload)
    raise Stop, "request size bound" if request.body.bytesize > 65_536
    bytes = +""
    Timeout.timeout(seconds) do
      client.start do |connection|
        connection.request(request) do |response|
          response.read_body do |chunk|
            bytes << chunk
            raise Stop, "native response size bound" if bytes.bytesize > 524_288
          end
          raise Stop, "native HTTP #{response.code}" unless response.code == "200"
        end
      end
    end
    Lab.parse(bytes)
  end

  def infer_entry(entry, item, previous: nil)
    label = entry.fetch("call_id")
    payload = Protocol.payload(item: item, thinking: entry.fetch("thinking"), contract: entry.fetch("contract"),
      seed: entry.fetch("seed"), previous: previous, extended: entry.fetch("extended"))
    model = entry.fetch("model")
    model == "qwen" ? qwen_observe! : endpoint_owned!
    cooldown = amd_cooldown! if model == "amd"
    payload["model"] = model == "qwen" ? "soul-local-chat" : http("/props").fetch("model_alias")
    # These fields affect native prompt rendering, unlike sampler/output limits.
    preview_payload = payload.slice("messages", "chat_template_kwargs", "reasoning_format", "response_format")
      .merge("add_generation_prompt" => true)
    template = native_http(model, "/apply-template", preview_payload, seconds: 8).fetch("prompt")
    save("#{label}-preview.json", { "entry" => entry, "preview_payload" => preview_payload,
      "preview_rendered_prompt" => template, "protocol_revision" => @protocol_revision })
    self.class.validate_native_branch!(model, entry.fetch("thinking"), template)
    tokens = native_http(model, "/tokenize", { "content" => template, "add_special" => true, "parse_special" => true }, seconds: 8).fetch("tokens")
    raise Stop, "invalid tokenization" unless tokens.is_a?(Array) && tokens.all? { |t| t.is_a?(Integer) }
    save("#{label}-request.json", { "entry" => entry, "payload" => payload, "preview_rendered_prompt" => template,
      "input_tokens" => tokens.length, "protocol_revision" => @protocol_revision,
      "request_revision" => Contract.digest(payload) })
    if !tokens.length.between?(1, INPUT_LIMIT)
      result = { "status" => "skipped_prerequisite", "reason" => "essential input exceeds frozen token budget", "input_tokens" => tokens.length }
      save("#{label}-result.json", result)
      return result
    end
    max_calls = @seed == Protocol::SEEDS.first ? 110 : 102
    raise Stop, "generation count bound" if @generation_count >= max_calls
    @generation_count += 1
    started = now
    drm_before = owned_drm if model == "amd"
    @qwen_inflight = true if model == "qwen"
    body = native_http(model, "/v1/chat/completions", payload, seconds: entry.fetch("deadline_seconds"))
    elapsed = now - started
    # Preserve the complete returned evidence before any postcondition can fail.
    save("#{label}-response.json", { "body" => body, "elapsed_seconds" => elapsed,
      "drm_before" => drm_before, "drm_after" => model == "amd" ? owned_drm : nil,
      "cooldown_seconds" => cooldown, "protocol_revision" => @protocol_revision })
    qwen_quiescent! if model == "qwen"
    self.class.validate_effective!(body, payload)
    result = Protocol.parse(body, item: item, contract: entry.fetch("contract"))
    actual_prompt = body.fetch("__verbose").fetch("prompt")
    settings = body.fetch("__verbose").fetch("generation_settings")
    result.merge!("elapsed_seconds" => elapsed, "entry" => entry,
      "actual_prompt_sha256" => Digest::SHA256.hexdigest(actual_prompt),
      "preview_matches_actual_prompt" => template == actual_prompt,
      "effective_grammar_sha256" => Digest::SHA256.hexdigest(settings["grammar"].to_s))
    save("#{label}-result.json", result)
    result
  rescue StandardError, SignalException => error
    save("#{label}-failure.json", { "class" => error.class.name, "message" => error.message,
      "generation_may_have_started" => !!started, "automatic_retry" => false }) if @output
    raise
  end

  def compare_cases
    if @seed == Protocol::SEEDS.first
      Protocol.feasibility_plan.each do |entry|
        result = infer_entry(entry, Protocol.feasibility_item)
        raise Stop, "native feasibility did not complete: #{entry['call_id']}" unless result["status"] == "complete"
        raise Stop, "native reasoning separation failed" unless result["reasoning_present"] == entry["thinking"]
        if entry["contract"] == "strict"
          raise Stop, "calibration JSON semantics failed" unless result.dig("strict_score", "correct")
        end
      end
      save("feasibility.json", { "state" => "complete", "calls" => 8, "protocol_revision" => @protocol_revision,
        "scope" => "native thinking branches, separate reasoning/final, strict grammar present and simple JSON calibration; not general semantic proof" })
    end
    @plan.each_with_index do |entry, index|
      item = @cases.find { |candidate| candidate["id"] == entry["case_id"] } or raise Stop, "unknown frozen case"
      prior = @results[entry["requires_call_id"]] if entry["stage"] == "reconsider"
      skip = Protocol.prerequisite_skip(prior) if entry["stage"] == "reconsider"
      result = if skip
                 save("#{entry.fetch('call_id')}-result.json", skip.merge("entry" => entry))
                 skip
               else
                 infer_entry(entry, item, previous: prior && prior["final_answer"])
               end
      @results[entry.fetch("call_id")] = result
      @rows << { "entry" => entry, "result" => result }
      puts JSON.generate("completed_cells" => index + 1, "planned_cells" => @plan.length,
        "generations" => @generation_count, "last_status" => result["status"])
    end
    raise Stop, "incomplete seed window" unless @rows.length == 102
    save("scores.json", { "rows" => @rows, "generations" => @generation_count,
      "semantic_assessment" => "pending_identity_masked_review", "protocol_revision" => @protocol_revision })
  end

  def run(*argv, timeout_seconds:, **)
    raise Stop, "unexpected A25 gate invocation" unless argv == ["fixed-continuity-a25"] && timeout_seconds == WINDOW_SECONDS
    store = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
    owner = Thread.current
    monitor = Thread.new do
      loop do
        sleep MONITOR_SECONDS
        sample = snapshot
        @samples << sample
        self.class.check_resources!(sample, @initial)
        raise Stop, "server log bound" if @log && File.size(@log) > 16 * 1024**2
      end
    rescue StandardError => error
      owner.raise(error)
    end
    begin
      store.with_control_lock do
        self.class.allowed_window!(store.leases_for_quiescent_admission_unlocked, Process.pid)
        begin
          Timeout.timeout(WINDOW_SECONDS) do
            qwen_observe!
            start_server("comparison")
            compare_cases
            stop_server
            wait_release("normal")
            qwen_observe!
          end
        ensure
          monitor.kill; monitor.join
          stop_server
          qwen_quiescent! if @qwen_inflight
        end
      end
      SoulCore::BoundedCommandRunner::Result.new(status: "ok", exit_status: 0, truncated: false)
    ensure
      monitor.kill; monitor.join
      stop_server
      save("resource-samples.json", @samples)
    end
  end

  def execute
    File.umask(0o077)
    raise Stop, "unsafe series root" unless File.realpath(@series) == @series && File.dirname(@series) == PARENT &&
      File.stat(@series).uid == Process.uid && (File.stat(@series).mode & 0o777) == 0o700
    protocol = Lab.parse(File.read(File.join(@series, "protocol.json")))
    @protocol_revision = protocol.delete("revision")
    raise Stop, "frozen protocol changed" unless Contract.digest(protocol) == @protocol_revision && protocol == self.class.frozen_protocol
    if @seed != Protocol::SEEDS.first
      first = Lab.parse(File.read(File.join(@series, "seed-#{Protocol::SEEDS.first}", "feasibility.json")))
      raise Stop, "native feasibility missing" unless first["state"] == "complete" && first["protocol_revision"] == @protocol_revision
      Protocol::SEEDS.take(Protocol::SEEDS.index(@seed)).each do |prior_seed|
        prior = File.join(@series, "seed-#{prior_seed}")
        gate = Lab.parse(File.read(File.join(prior, "gate-result.json")))
        closeout = Lab.parse(File.read(File.join(prior, "preservation.json")))
        raise Stop, "prior window incomplete or unsafe" unless gate["ok"] &&
          %w[unchanged runtime_unchanged own_lease_gone endpoint_closed].all? { |key| closeout[key] == true } &&
          closeout["qwen_request_unsettled"] == false
      end
    end
    @output = File.join(@series, "seed-#{@seed}")
    Dir.mkdir(@output, 0o700) # Existing/failed windows are evidence, never resumed or overwritten.
    @output_created = true
    puts "EVIDENCE #{@output}"
    @cases = Cases.cases
    @plan = Protocol.plan(seed: @seed)
    @before = preservation
    @initial = snapshot
    core = Lab.parse(File.read(File.join(ROOT, "Soul/runtime/model_runtime/core_selection.json"))).fetch("active_core_id")
    raise Stop, "unsuitable Core" unless %w[amd-free dev music].include?(core)
    pid = @before.fetch("qwen")[/^MainPID=(\d+)$/, 1] or raise Stop, "Qwen PID missing"
    @observer = Continuity::QwenHostObserver.new(root: ROOT, client: @qwen, expected_pid: Integer(pid), expected_core: core)
    raise Stop, "unsupported page size" unless command("getconf", "PAGESIZE").strip == "4096"
    self.class.check_resources!(@initial, @initial)
    path = @asset.fetch("path")
    stat = File.lstat(path)
    raise Stop, "unsafe model path" unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && File.realpath(path) == path
    raise Stop, "model hash mismatch" unless stat.size == @asset["size"] && Digest::SHA256.file(path).hexdigest == @asset["sha256"]
    raise Stop, "Qwen weights changed" unless Digest::SHA256.file(Continuity::QwenHostObserver::MODEL).hexdigest == QWEN_SHA
    libs = Dir.glob("/usr/lib/ollama/*.so*").select { |p| File.file?(p) && !File.symlink?(p) } + [SERVER, PLUGIN, Continuity::QwenHostObserver::SERVER]
    @runtime_hashes = libs.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
    unless @seed == Protocol::SEEDS.first
      first_baseline = Lab.parse(File.read(File.join(@series, "seed-#{Protocol::SEEDS.first}", "baseline.json")))
      raise Stop, "runtime changed between independent seeds" unless first_baseline["runtime_hashes"] == @runtime_hashes && first_baseline["preservation"] == @before
    end
    @api_key = SecureRandom.hex(32)
    @key_path = File.join(@output, "local-api-key")
    File.open(@key_path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |f| f.puts(@api_key) }
    save("baseline.json", { "preservation" => @before, "runtime_hashes" => @runtime_hashes,
      "initial" => @initial, "protocol_revision" => @protocol_revision })
    guard = GuardedComparisonLeases.new(store: SoulCore::ModelRuntimeLeaseStore.new(root: ROOT), pilot: self)
    result = SoulCore::ExternalAmdWorkloadGate.new(root: ROOT, runner: self, leases: guard).run(
      command: ["fixed-continuity-a25"], timeout_seconds: WINDOW_SECONDS, min_free_bytes: 11 * GIB)
    save("gate-result.json", result)
    puts JSON.generate(result)
    result["ok"]
  rescue StandardError, SignalException => error
    save("failure.json", { "class" => error.class.name, "message" => error.message,
      "generations" => @generation_count, "completed_cells" => @rows.length }) if @output_created
    warn "FAILED #{error.class}: #{error.message}"
    false
  ensure
    stop_server
    if @output_created && @before
      after = preservation
      runtime_unchanged = !@runtime_hashes || @runtime_hashes.all? { |p, sha| Digest::SHA256.file(p).hexdigest == sha }
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
      retained = leases.with_control_lock { leases.leases_for_quiescent_admission_unlocked }
      gone = retained.none? { |lease| lease["pid"] == Process.pid && lease["provider_id"] == "external.codex.amd" }
      closed = port_closed?
      save("preservation.json", { "unchanged" => @before == after, "before" => @before, "after" => after,
        "runtime_unchanged" => runtime_unchanged, "own_lease_gone" => gone, "qwen_request_unsettled" => @qwen_inflight,
        "endpoint_closed" => closed, "final_snapshot" => snapshot })
      raise Stop, "baseline/runtime/lease closeout failed" unless @before == after && runtime_unchanged && gone && !@qwen_inflight && closed
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Use pinned Ruby 4.0.7" unless RUBY_VERSION == "4.0.7"
  $stdout.sync = true
  Signal.trap("TERM") { raise Interrupt, "termination requested" }
  if ARGV == ["--prepare"]
    puts ContinuityComparisonA25.prepare
  elsif ARGV.length == 3 && ARGV.first == "--approved-window"
    exit(ContinuityComparisonA25.new(series: File.expand_path(ARGV[1]), seed: Integer(ARGV[2])).execute ? 0 : 1)
  else
    abort "Use --prepare, or --approved-window PRIVATE_SERIES_ROOT REGISTERED_SEED"
  end
end
