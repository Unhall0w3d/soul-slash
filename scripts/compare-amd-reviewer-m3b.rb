#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "compare-amd-reviewer-m3"
require_relative "support/amd_reviewer_cases_m3b"

# Qualification-only specialization; historical M2/M3 and production stay intact.
class AmdReviewerComparisonM3b < AmdReviewerComparisonM3
  NEW_ASSETS = File.join(__dir__, "support/amd_reviewer_assets_m3b.json")
  MODEL_PARENT = "/home/bhones/ai_models/amd-reviewer-m3b"
  SOURCE = File.join(ROOT, "Soul/runtime/qualification/amd-reviewer-m3-20261013T201325Z-20261013-1965115-u4kowy/scores.json")
  SOURCE_SHA = "a77dc632a6c8b966213232bdf05c35ae76edfb93fddd051eaf5e9b3bbc1c6c7b"
  CASES_DIGEST = "sha256:803e86da034c6e75ef8b20432aa1faa06c1e8bc781ce707c4c48481f9d7bda98"
  MODEL_IDS = %w[ministral14 qwen35 phi4].freeze
  LIMIT = 48
  THERMAL_ABORT = { "edge" => 90, "junction" => 100, "mem" => 90 }.freeze
  MONITOR_SECONDS = 0.5

  def self.thermal_limits(hw)
    # These three reviewed sensor channels must all be attested, not an empty glob.
    (1..3).flat_map { |index| %w[crit emergency].map { |kind| "temp#{index}_#{kind}" } }.to_h do |name|
      value = Integer(File.read(File.join(hw, name)))
      raise Stop, "invalid driver thermal limit: #{name}" unless value.positive?
      [name, value]
    end
  end

  def self.check_resources!(sample, initial)
    THERMAL_ABORT.each do |sensor, limit|
      value = sample.fetch("temperatures").fetch(sensor)
      raise Stop, "invalid AMD thermal sample: #{sensor}" unless value.is_a?(Numeric) && value.finite?
      raise Stop, "AMD thermal bound: #{sensor} >= #{limit} C" if value >= limit
    end
    raise Stop, "AMD headroom bound" if sample.fetch("vram_total") - sample.fetch("vram_used") < 2 * GIB
    raise Stop, "RAM headroom bound" if sample.fetch("memory").fetch("MemAvailable") < 8 * GIB
    raise Stop, "swap-out bound" if sample.fetch("paging_pages").fetch("pswpout") - initial.fetch("paging_pages").fetch("pswpout") > 65_536
  end

  def self.asset(id)
    raise Stop, "unknown candidate" unless MODEL_IDS.include?(id)
    if id == "ministral14"
      Lab.parse(File.read(ASSETS)).fetch(id).merge("path" => MODEL)
    else
      data = Lab.parse(File.read(NEW_ASSETS)).fetch(id)
      data.merge("path" => File.join(MODEL_PARENT, data.fetch("file")))
    end
  end

  def self.launch_args(name, asset)
    args = argv(name)
    args[args.index("--model") + 1] = asset.fetch("path")
    args
  end

  def self.sampler(schema)
    super.merge("presence_penalty" => 0.0, "frequency_penalty" => 0.0, "dry_multiplier" => 0.0,
      "mirostat" => 0, "typical_p" => 1.0, "xtc_probability" => 0.0, "dynatemp_range" => 0.0)
  end

  def self.validate_completion!(final, tokens)
    result = super
    actual = final.fetch("generation_settings")
    sampler(nil).reject { |key, _| %w[stream cache_prompt json_schema].include?(key) }.each do |key, expected|
      value = actual.fetch(key)
      raise Stop, "effective sampler mismatch: #{key}" unless value.is_a?(Numeric) && (value - expected).abs < 0.00001
    end
    raise Stop, "unexpected sampler pipeline" unless actual["samplers"] == %w[penalties dry top_n_sigma top_k typ_p top_p min_p xtc temperature]
    raise Stop, "unexpected adapter" unless actual["lora"] == []
    result
  end

  def self.control_messages(item, original)
    data = { "task" => Cases.public_case(item).reject { |key, _| key == "id" }, "original_answer" => original,
      "instruction" => "Reconsider the original answer using only the task evidence. Return a final answer; correct errors supported by evidence and preserve a correct original. No reviewer feedback is supplied." }
    [{ "role" => "system", "content" => ANSWER_INSTRUCTION }, { "role" => "user", "content" => JSON.generate(data) }]
  end

  def self.review_packet(item, answer, id, at: Time.now.to_i)
    packet = super
    packet["evidence"].each { |e| e["provenance"] = "synthetic-m3b-comparison" }
    packet["evidence_revision"] = Contract.digest(packet["evidence"])
    packet["source_event_id"] = packet["source_event_id"].sub(/\Am3-/, "m3b-")
    Contract.request!(packet)
  end

  def initialize(id)
    super()
    @candidate_id, @asset = id, self.class.asset(id)
  end

  def preservation
    result = super
    extra = [File.expand_path(__FILE__), NEW_ASSETS, SOURCE,
      File.join(__dir__, "support/amd_reviewer_cases_m3b.rb"), File.join(ROOT, "docs/soul/AMD_REVIEWER_M3B_BRIEF.md")]
    result["hashes"].merge!(extra.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] })
    base = "/sys/bus/pci/devices/#{SoulCore::AmdWhisperDevice::PCI}"
    hw = Dir.glob("#{base}/hwmon/hwmon*").first or raise Stop, "missing AMD hardware settings"
    # Read-only attestation; never write LACT/sysfs settings during qualification.
    result["amd_hardware_settings"] = { "od_clocks_voltage" => File.read("#{base}/pp_od_clk_voltage"),
      "power_cap_microwatts" => Integer(File.read("#{hw}/power1_cap")),
      "thermal_limits" => self.class.thermal_limits(hw) }
    result
  end

  def http(path, payload = nil, **options, &block)
    if path == "/apply-template" && @asset["thinking"] == false
      payload = payload.merge("chat_template_kwargs" => { "enable_thinking" => false })
    end
    result = super(path, payload, **options, &block)
    if path == "/apply-template" && @asset["thinking"] == false
      raise Stop, "non-thinking native template not attested" unless result.fetch("prompt").rstrip.end_with?("</think>")
    end
    result
  end

  def infer(model, messages, schema, label)
    raise Stop, "M3B generation budget exceeded" if @generation_count >= LIMIT
    super
  end

  def start_server(label)
    raise Stop, "pilot endpoint occupied" unless port_closed?
    @log = File.join(@output, "#{label}-server.log")
    name = "amd-reviewer-m2-#{File.basename(@output).split('-').last}-#{label}"
    args = self.class.launch_args(name, @asset) + ["--api-key-file", @key_path]
    launch = { "argv" => args, "environment" => self.class.environment, "candidate_id" => @candidate_id }
    started = now
    File.open(@log, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |f|
      @child = Process.spawn(self.class.environment, *args, out: f, err: f, in: File::NULL, pgroup: true, unsetenv_others: true)
    end
    launch["pid"] = @child
    launch["process_stat"] = File.read("/proc/#{@child}/stat")
    save("#{label}-launch.json", launch)
    deadline = now + 180
    loop do
      if Process.waitpid(@child, Process::WNOHANG)
        @child = nil
        raise Stop, "candidate exited during startup; see retained server log"
      end
      begin
        unless port_closed?
          endpoint_owned!
          break if http("/health", seconds: 2)["status"] == "ok"
        end
      rescue Loading, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError
        # Loading-only retry: inherited resource aborts must propagate.
      end
      raise Stop, "startup deadline" if now >= deadline
      sleep 0.25
    end
    props = http("/props")
    raise Stop, "runtime model/slot/context identity mismatch" unless props["model_path"] == @asset.fetch("path") && props["model_alias"] == name && props["total_slots"] == 1 && props.dig("default_generation_settings", "n_ctx") == 4096
    raise Stop, "runtime executable changed" unless File.realpath("/proc/#{@child}/exe") == SERVER
    raise Stop, "Vulkan backend not mapped" unless File.read("/proc/#{@child}/maps").include?(PLUGIN)
    layers = self.class.offload_evidence(File.binread(@log))
    save("#{label}-ready.json", { "startup_seconds" => now - started, "props" => props,
      "template_sha256" => Digest::SHA256.hexdigest(props.fetch("chat_template")), "offloaded_layers" => layers,
      "mapped_vulkan" => true, "owned_drm" => owned_drm, "snapshot" => snapshot })
  end

  def compare_cases
    @cases.each_with_index.to_a.rotate(MODEL_IDS.index(@candidate_id)).each do |item, index|
      id = format("case-%02d", index + 1)
      original = @originals.fetch(item.fetch("id"))
      baseline = Cases.score(original, item)
      # Both control and review-assisted branches start from the immutable source.
      control = infer("qwen", self.class.control_messages(item, original), self.class.answer_schema(item), "#{id}-control")
      critique = review("amd", item, original, "#{id}-amd-review")
      revised = answer("qwen", item, "#{id}-amd-revision", original: original, review: critique)
      seed = review("amd", item, item.fetch("seeded_answer"), "#{id}-amd-seed")
      row = { "id" => item["id"], "original" => original, "baseline" => baseline, "review" => critique,
        "revision" => revised, "revision_score" => Cases.score(revised, item),
        "control" => control, "control_score" => Cases.score(control, item),
        "seed_review" => seed, "seed_expected" => item["seeded_verdict"] }
      @rows << row
      save("#{id}-scores.json", row)
      puts JSON.generate({ "candidate" => @candidate_id, "case" => index + 1, "generations" => @generation_count,
        "baseline" => baseline["correct"], "revision" => row.dig("revision_score", "correct"), "control" => row.dig("control_score", "correct") })
    end
    fresh = AmdReviewerCasesM3b.cases.each_with_index.to_a.rotate(MODEL_IDS.index(@candidate_id)).map do |item, index|
      output = review("amd", item, item.fetch("seeded_answer"), format("heldout-%02d", index + 1))
      { "id" => item["id"], "expected" => item["seeded_verdict"], "review" => output }
    end
    raise Stop, "incomplete comparison" unless @generation_count == LIMIT && @rows.length == 10 && fresh.length == 8
    save("scores.json", { "rows" => @rows, "heldout" => fresh, "generations" => @generation_count, "protocol_revision" => @protocol_revision })
    save("summary.json", { "candidate" => @candidate_id, "cases" => @rows.length,
      "baseline_correct" => @rows.count { |r| r.dig("baseline", "correct") },
      "control_correct" => @rows.count { |r| r.dig("control_score", "correct") },
      "revised_correct" => @rows.count { |r| r.dig("revision_score", "correct") },
      "corrected" => @rows.count { |r| !r.dig("baseline", "correct") && r.dig("revision_score", "correct") },
      "spoiled" => @rows.count { |r| r.dig("baseline", "correct") && !r.dig("revision_score", "correct") },
      "old_seed_correct" => @rows.count { |r| r.dig("seed_review", "verdict") == r["seed_expected"] },
      "heldout_seed_correct" => fresh.count { |r| r.dig("review", "verdict") == r["expected"] } })
  end

  # Same bounded lifecycle as M3, with the explicitly approved v2 sample cadence.
  # Keep historical M2/M3 source and their threshold tests unchanged.
  def run(*argv, timeout_seconds:, **)
    raise Stop, "unexpected gate invocation" unless argv == ["fixed-m3b-v2-comparison"] && timeout_seconds == MAX_SECONDS
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
    rescue StandardError => e
      owner.raise(e)
    end
    begin
      store.with_control_lock do
        self.class.allowed_window!(store.leases_for_quiescent_admission_unlocked, Process.pid)
        begin
          Timeout.timeout(MAX_SECONDS) do
            qwen_observe!
            start_server("comparison")
            compare_cases
            stop_server
            wait_release("normal")
            qwen_observe!
          end
        ensure
          monitor.kill
          monitor.join
          stop_server
          qwen_quiescent! if @qwen_inflight
        end
      end
      SoulCore::BoundedCommandRunner::Result.new(status: "ok", exit_status: 0, truncated: false)
    rescue ArgumentError => e
      raise Stop, "comparison #{e.class}: #{e.message}"
    ensure
      monitor.kill
      monitor.join
      stop_server
      save("resource-samples.json", @samples)
    end
  end

  def execute
    File.umask(0o077)
    Cases.validate!
    AmdReviewerCasesM3b.validate!
    raise Stop, "historical source changed" unless Digest::SHA256.file(SOURCE).hexdigest == SOURCE_SHA
    source = Lab.parse(File.read(SOURCE))
    @cases = Cases.cases
    raise Stop, "historical fixtures changed" unless Contract.digest(@cases) == CASES_DIGEST
    @originals = source.fetch("rows").to_h { |r| [r.fetch("id"), r.fetch("original")] }
    raise Stop, "source case identity mismatch" unless @originals.keys.sort == @cases.map { |c| c["id"] }.sort
    @cases.each { |c| Cases.score(@originals.fetch(c["id"]), c) }
    parent = File.join(ROOT, "Soul/runtime/qualification")
    raise Stop, "unsafe evidence parent" unless File.realpath(parent) == parent && File.stat(parent).uid == Process.uid
    @output = Dir.mktmpdir("amd-reviewer-m3b-#{@candidate_id}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-", parent)
    puts "EVIDENCE #{@output}"
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
    qwen_hash = Digest::SHA256.file(Continuity::QwenHostObserver::MODEL).hexdigest
    raise Stop, "Qwen weights changed" unless qwen_hash == "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785"
    libs = Dir.glob("/usr/lib/ollama/*.so*").select { |p| File.file?(p) && !File.symlink?(p) } + [SERVER, PLUGIN, Continuity::QwenHostObserver::SERVER]
    @runtime_hashes = libs.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
    @api_key = SecureRandom.hex(32)
    @key_path = File.join(@output, "local-api-key")
    File.open(@key_path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |f| f.puts(@api_key) }
    protocol = { "schema" => "soul.reviewer.comparison.m3b.v2", "candidate" => @candidate_id, "asset" => @asset,
      "cases" => @cases, "heldout" => AmdReviewerCasesM3b.cases, "originals" => @originals, "source_sha256" => SOURCE_SHA,
      "qwen_model_sha256" => qwen_hash, "runtime_hashes" => @runtime_hashes, "preservation" => @before,
      "max_generations" => LIMIT, "max_seconds" => MAX_SECONDS, "initial" => @initial,
      "answer_instruction" => ANSWER_INSTRUCTION, "verdict_definitions" => VERDICTS,
      "sampler" => self.class.sampler(nil), "scoring" => "exact_fields_casefold_trim_only",
      "thermal_abort_celsius" => THERMAL_ABORT, "monitor_interval_seconds" => MONITOR_SECONDS,
      "cooldown" => { "minimum_seconds" => 3, "edge_max" => 55, "junction_max" => 70, "timeout_seconds" => 30 },
      "primary_task_contract" => "unchanged", "visibility" => "detached_not_available_to_soul" }
    @protocol_revision = Contract.digest(protocol)
    save("protocol.json", protocol.merge("protocol_revision" => @protocol_revision))
    guard = GuardedComparisonLeases.new(store: SoulCore::ModelRuntimeLeaseStore.new(root: ROOT), pilot: self)
    # Preserve M3's gate/control-lock semantics with the approved v2 monitor.
    result = SoulCore::ExternalAmdWorkloadGate.new(root: ROOT, runner: self, leases: guard).run(
      command: ["fixed-m3b-v2-comparison"], timeout_seconds: MAX_SECONDS, min_free_bytes: 11 * GIB)
    save("gate-result.json", result)
    puts JSON.generate(result)
    result["ok"]
  rescue StandardError, SignalException => e
    save("failure.json", { "error" => e.class.name, "message" => e.message, "completed_cases" => @rows.length,
      "generations" => @generation_count, "unsettled" => unsettled? }) if @output
    warn "FAILED #{e.class}: #{e.message}"
    false
  ensure
    stop_server
    if @output && @before
      after = preservation
      runtime_unchanged = !@runtime_hashes || @runtime_hashes.all? { |p, sha| Digest::SHA256.file(p).hexdigest == sha }
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
      retained = leases.with_control_lock { leases.leases_for_quiescent_admission_unlocked }
      gone = retained.none? { |l| l["pid"] == Process.pid && l["provider_id"] == "external.codex.amd" }
      save("preservation.json", { "unchanged" => @before == after, "before" => @before, "after" => after,
        "runtime_unchanged" => runtime_unchanged, "own_lease_gone" => gone, "qwen_request_unsettled" => @qwen_inflight,
        "endpoint_closed" => port_closed?, "final_snapshot" => snapshot })
      raise Stop, "baseline/runtime/lease closeout failed" unless @before == after && runtime_unchanged && gone && !@qwen_inflight && port_closed?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Use --approved-m3b-comparison MODEL" unless ARGV.length == 2 && ARGV.first == "--approved-m3b-comparison" && AmdReviewerComparisonM3b::MODEL_IDS.include?(ARGV.last)
  $stdout.sync = true
  Signal.trap("TERM") { raise Interrupt, "termination requested" }
  exit(AmdReviewerComparisonM3b.new(ARGV.last).execute ? 0 : 1)
end
