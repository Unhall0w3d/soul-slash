#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-chat-replacement-trial"
require_relative "support/mixed_gpu_telemetry"
require_relative "../lib/soul_core/model_runtime_lease_store"

# Private foreground pilot, not a production provider or a service.
class MixedGpuPilot < ChatReplacementTrial
  BINARY = File.join(QUALIFICATION, "mixed-gpu-b9851-build/bin/llama-server")
  BINARY_SHA = "af06ab4513887355396224ab550d433bc3e4405085698d396c64e7bc9dad40d5"
  MODEL = "/home/bhones/ai_models/Ministral-3-14B-Instruct-2512-Q4_K_M.gguf"
  MODEL_SHA = "824e0f3373e69b84f2cae46fdcb9bd1ebc6ab3bfc7acc125d818b7b8178cc613"
  CONDITIONS = %w[amd_full amd_cpu amd_nvidia].freeze
  BUDGET_SECONDS = 2640
  CASES = [
    ["short", "Return only the sum of 17 and 28.", "45"],
    ["evidence", "Source: The cobalt crate contains seven keys. The amber crate contains two maps. Which crate contains the keys? Reply only with the color.", "cobalt"],
    ["prefill", (1..160).map { |i| "Record #{i}: marker is gray." }.join("\n") + "\nFinal record: marker is teal. What is the final record's marker? Reply only with the color.", "teal"]
  ].freeze

  def self.argv(candidate, model)
    raise ArgumentError, "unknown condition" unless CONDITIONS.include?(candidate)
    placement = case candidate
                when "amd_full" then ["--device", "Vulkan0", "--split-mode", "none", "--gpu-layers", "all"]
                when "amd_cpu" then ["--device", "Vulkan0", "--split-mode", "none", "--gpu-layers", "20"]
                else ["--device", "Vulkan0,CUDA0", "--split-mode", "layer", "--gpu-layers", "all", "--tensor-split", "1,1"]
                end
    ["/usr/bin/env", "-u", "VK_ICD_FILENAMES", "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json",
     "VK_LOADER_LAYERS_DISABLE=~implicit~", "GGML_VK_VISIBLE_DEVICES=0", BINARY,
     "--model", model, "--alias", candidate, "--host", "127.0.0.1", "--port", PORT.to_s,
     *placement, "--jinja", "--ctx-size", CONTEXT.to_s, "--predict", "128", "--parallel", "1",
     "--threads", "8", "--threads-batch", "8", "--batch-size", "512", "--ubatch-size", "32",
     "--cache-type-k", "f16", "--cache-type-v", "f16", "--flash-attn", "off", "--fit", "off",
     "--no-context-shift", "--no-warmup", "--reasoning", "off", "--verbosity", "4"]
  end

  def initialize
    raise Abort, "never run model pilot as root" if Process.uid.zero?
    @model = MODEL
    @commands = SoulCore::BoundedCommandRunner.new
    @asset = {"temperature"=>0.0}
    @protocol = {"cutoff_c"=>88, "paced"=>false}
    @samples, @cooling_events = [], []
    @telemetry_mutex = Mutex.new
  end

  def self.compositor_limit_bytes = 1024**3

  def self.compositor_client?(client)
    holders = client.fetch("holders")
    !holders.empty? && holders.all? do |holder|
      holder.fetch("uid") == Process.uid &&
        ["/usr/bin/kwin_wayland", "/usr/bin/kwin_wayland (deleted)"].include?(holder["exe"])
    end
  end

  def self.validate_amd!(sample, previous:, owned_pid:)
    # Aggregate compositor clients: splitting allocations must not bypass its cap.
    compositor_bytes = sample.fetch("clients").select { |c| compositor_client?(c) }.sum { |c| c.fetch("bytes") }
    raise Abort, "AMD compositor allocation reached #{compositor_limit_bytes / 1024**2} MiB bound" if compositor_bytes >= compositor_limit_bytes
    sample.fetch("clients").each do |client|
      holders = client.fetch("holders")
      owned = owned_pid && !holders.empty? && holders.all? { |h| h.fetch("pid") == owned_pid && h.fetch("uid") == Process.uid }
      next if owned
      limit = compositor_client?(client) ? compositor_limit_bytes : 1024**3
      raise Abort, "foreign AMD allocation >= 1 GiB" if client.fetch("bytes") >= limit
      old = previous && previous.fetch("clients").find { |c| c.fetch("id") == client.fetch("id") }
      if (previous && !old && client.fetch("compute").positive?) || (old && client.fetch("compute") - old.fetch("compute") > 10_000_000)
        raise Abort, "foreign AMD compute"
      end
    end
  end

  def self.released_sample?(sample, stopped_pid:, after:)
    sample.fetch("monotonic") >= after && sample.fetch("clients").none? do |client|
      client.fetch("holders").any? { |holder| holder.fetch("pid") == stopped_pid }
    end
  end

  def run
    File.umask(0o077)
    @root_output = Dir.mktmpdir("mixed-gpu-pilot-", QUALIFICATION)
    @output = @root_output
    state, error = "failed", nil
    started = now
    lease = nil
    signals = %w[INT TERM].to_h { |s| [s, Signal.trap(s) { raise Abort, "Canceled by #{s}" }] }
    begin
      Timeout.timeout(self.class::BUDGET_SECONDS, Abort, "pilot wall-clock bound") do
        verify_file!(MODEL, 8_239_593_024, MODEL_SHA)
        raise Abort, "binary changed" unless Digest::SHA256.file(BINARY).hexdigest == BINARY_SHA
        @before = protected_state
        raise Abort, "production NVIDIA runtime active" unless @before.fetch("unit").include?("ActiveState=inactive")
        raise Abort, "production AMD runtime active" unless @before.fetch("amd_units").scan(/^ActiveState=(.*)$/).flatten == ["inactive", "inactive"]
        raise Abort, "trial endpoint occupied" unless port_closed?
        start_telemetry
        initial = sample_resources
        @desktop_baseline = desktop_baseline(initial)
        validate_resources!(initial, admission: true)
        @leases = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
        lease = @leases.acquire_exclusive(provider_id: "external.codex.amd", model_id: "ministral14-mixed-pilot",
          request_id: File.basename(@root_output), resource_group: "amd-vulkan-generation", ttl_seconds: 2760)
        validate_resources!(sample_resources, admission: true)
        save("preflight.json", {"protected"=>@before, "model_sha256"=>MODEL_SHA, "binary_sha256"=>BINARY_SHA,
          "conditions"=>self.class::CONDITIONS, "cases"=>CASES, "repetitions"=>2, "ordering"=>"fixed pilot; not a definitive benchmark",
          "protocol"=>self.class.name, "sustained_cooldown_seconds"=>5, "cooldown_junction_c"=>60,
          "sources"=>[__FILE__, File.join(__dir__, "support/mixed_gpu_telemetry.rb"), File.join(__dir__, "inspect-mixed-gpu-telemetry.rb"), File.join(__dir__, "run-chat-replacement-trial.rb")].to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }})
        self.class::CONDITIONS.each do |condition|
          @candidate = condition
          @output = File.join(@root_output, condition)
          Dir.mkdir(@output, 0o700)
          @generation_count = 0
          @reaped_pid = nil
          cool_down
          validate_resources!(sample_resources, admission: true)
          puts JSON.generate(state: "starting", condition: condition, output: @root_output)
          $stdout.flush
          begin
            start
            start_monitor
            CASES.each do |id, prompt, expected|
              2.times do |repeat|
                cool_down
                response, latency = generate({"model"=>condition, "messages"=>[{"role"=>"user", "content"=>prompt}],
                  "temperature"=>0.0, "max_tokens"=>128, "stream"=>false})
                raise Abort, "HTTP failure" unless response.code == "200"
                parsed = JSON.parse(response.body)
                content = parsed.dig("choices", 0, "message", "content").to_s.strip
                save("result-#{id}-#{repeat}.json", {"case"=>id, "repeat"=>repeat, "content"=>content,
                  "expected"=>expected, "exact"=>content.downcase == expected, "latency_ms"=>latency,
                  "usage"=>parsed["usage"], "timings"=>parsed["timings"], "finish_reason"=>parsed.dig("choices", 0, "finish_reason")})
              end
            end
          ensure
            stopped_pid = @pid
            cleanup_owned_runtime
          end
          raise Abort, "trial endpoint survived cleanup" unless port_closed?
          wait_for_release(stopped_pid)
        end
        state = "completed_pending_placement_review"
      end
    rescue Abort, StandardError => problem
      error = "#{problem.class}: #{problem.message}"
    ensure
      begin
        cleanup_owned_runtime
        stop_telemetry
        @leases.release(lease.fetch("lease_id")) if lease
        @after = protected_state
        raise Abort, "protected state changed" unless @before == @after
      rescue Abort, StandardError => problem
        state = "failed"
        error = [error, "cleanup: #{problem.class}: #{problem.message}"].compact.join("; ")
      end
      @output = @root_output
      save("resource-samples.json", @samples)
      save("receipt.json", {"state"=>state, "error"=>error, "elapsed_seconds"=>(now-started).round(3),
        "owned_pid_if_unreaped"=>@pid, "protected_before"=>@before, "protected_after"=>@after})
      signals.each { |s, handler| Signal.trap(s, handler) }
    end
    puts JSON.generate(state: state, error: error, output: @root_output)
    state == "completed_pending_placement_review"
  end

  private

  def wait_for_release(stopped_pid)
    barrier = now
    deadline = barrier + 10
    loop do
      sample = sample_resources
      validate_resources!(sample)
      if self.class.released_sample?(sample.fetch("amd"), stopped_pid: stopped_pid, after: barrier)
        save("release-observed.json", {"stopped_pid"=>stopped_pid, "after"=>barrier, "sample"=>sample.fetch("amd")})
        return
      end
      raise Abort, "previous model release not observed" if now >= deadline
      sleep 0.1
    end
  end

  def protected_state
    super.merge("amd_units"=>command("systemctl", "--user", "show", "soul-model-gemma.service", "soul-model-dev.service", "--property=ActiveState,MainPID", "--no-pager"))
  end

  def http(path, payload = nil, seconds:)
    raise Abort, "no owned server" unless @pid
    inodes = File.readlines('/proc/net/tcp').drop(1).filter_map do |line|
      fields = line.split
      fields[9] if fields[1] == "0100007F:#{PORT.to_s(16).upcase.rjust(4, '0')}" && fields[3] == "0A"
    end
    sockets = Dir.glob("/proc/#{@pid}/fd/*").filter_map do |fd|
      File.readlink(fd)
    rescue Errno::ENOENT
      nil
    end
    raise IOError, "endpoint not yet owned by trial child" unless inodes.length == 1 && sockets.include?("socket:[#{inodes.first}]")
    super
  end

  def start_telemetry
    @telemetry_io = IO.popen(["sudo", "-n", "/home/bhones/.rbenv/versions/4.0.7/bin/ruby",
      File.join(__dir__, "inspect-mixed-gpu-telemetry.rb"), Process.pid.to_s, (self.class::BUDGET_SECONDS + 60).to_s], "r")
    @telemetry_thread = Thread.new do
      sequence = 0
      previous = nil
      File.open(File.join(@root_output, "telemetry.jsonl"), "wx", 0o600) do |log|
        while (line = @telemetry_io.gets(524_289))
          raise Abort, "oversized telemetry" if line.bytesize > 524_288 || !line.end_with?("\n")
          sample = JSON.parse(line)
          # Retain rejected samples as diagnostic evidence, never as admitted state.
          log.write(line)
          log.flush
          MixedGpuTelemetry.validate_fresh!(sample, now: now, previous_sequence: sequence)
          self.class.validate_amd!(sample, previous: previous, owned_pid: @pid)
          sequence = sample.fetch("sequence")
          @telemetry_mutex.synchronize { @telemetry = sample } if previous
          previous = sample
        end
        raise Abort, "telemetry ended"
      end
    rescue Abort, StandardError => problem
      @telemetry_mutex.synchronize { @telemetry_error = problem.message } unless @telemetry_stopping
    end
    wait_for_telemetry!(deadline: now + 10)
  end

  def wait_for_telemetry!(deadline:)
    loop do
      sample, error = @telemetry_mutex.synchronize { [@telemetry, @telemetry_error] }
      raise Abort, "telemetry rejected: #{error}" if error
      return if sample
      raise Abort, "telemetry startup timeout" if now >= deadline
      sleep 0.1
    end
  end

  def stop_telemetry
    return unless @telemetry_io
    @telemetry_stopping = true
    @telemetry_thread.kill
    @telemetry_thread.join
    # Closing the sole reader causes EPIPE on the bounded helper's next sample.
    Timeout.timeout(8, Abort, "telemetry teardown timeout") { @telemetry_io.close }
    @telemetry_io = nil
  end

  def sample_resources
    sample = super
    amd, error = @telemetry_mutex.synchronize { [@telemetry, @telemetry_error] }
    raise Abort, "telemetry failed: #{error}" if error
    raise Abort, "missing telemetry" unless amd
    MixedGpuTelemetry.validate_fresh!(amd, now: now, previous_sequence: amd.fetch("sequence")-1)
    base = "/sys/bus/pci/devices/#{MixedGpuTelemetry::PCI}"
    hw = Dir.glob("#{base}/hwmon/hwmon*").first or raise Abort, "missing AMD sensors"
    temperatures = Dir.glob("#{hw}/temp*_input").to_h { |p| [File.read(p.sub(/_input$/, "_label")).strip, Integer(File.read(p))/1000.0] }
    swap = Integer(File.read("/proc/vmstat")[/^pswpout (\d+)$/, 1])
    @initial_swap ||= swap
    hardware = %w[power1_average power1_cap fan1_input pwm1 freq1_input freq2_input].to_h do |name|
      [name, Integer(File.read("#{hw}/#{name}"))]
    end
    sample.merge("amd"=>amd, "amd_temperatures"=>temperatures, "amd_hardware_raw"=>hardware, "swap_delta_pages"=>swap-@initial_swap)
  end

  # Operator-approved workday allowance, 2026-10-22. Counts host-wide cumulative
  # swap-outs, not model-owned memory or physical zram usage (4 KiB host pages).
  SWAP_OUT_LIMIT_PAGES = 131_072

  # Historical experiments retain their frozen paging refusal. The production
  # driver may explicitly select observation-only paging without bypassing the
  # surrounding physical RAM, VRAM or temperature checks.
  def validate_swap_out!(sample)
    raise Abort, "swap-out bound" if sample.fetch("swap_delta_pages") > SWAP_OUT_LIMIT_PAGES
  end

  def validate_resources!(sample, admission: false)
    super
    raise Abort, "RAM headroom below 8 GiB" if sample.fetch("ram_available_kib") < 8*1024**2
    validate_swap_out!(sample)
    amd = sample.fetch("amd")
    raise Abort, "AMD headroom bound" if amd.fetch("total")-amd.fetch("used") < (admission ? 10 : 2)*1024**3
    limits = {"edge"=>90, "junction"=>100, "mem"=>90}
    limits.each { |label, limit| raise Abort, "AMD #{label} thermal bound" if sample.fetch("amd_temperatures").fetch(label) >= limit }
  end

  def cool_down
    deadline = now + 180
    since = nil
    loop do
      sample = sample_resources
      @samples << sample
      validate_resources!(sample)
      since = self.class.cool_since(sample, now: now, since: since)
      break if since && now - since >= 5
      raise Abort, "cooling deadline" if now >= deadline
      sleep 1
    end
  end

  def self.cool_since(sample, now:, since:)
    return nil unless sample.fetch("temperature_c") <= 55 && sample.fetch("amd_temperatures").fetch("junction") <= 60
    since || now
  end
end

class MixedGpuThermalProbe < MixedGpuPilot
  CONDITIONS = %w[amd_full].freeze
  BUDGET_SECONDS = 600

end

if $PROGRAM_NAME == __FILE__
  modes = {"--approved-foreground-pilot"=>MixedGpuPilot, "--approved-thermal-probe"=>MixedGpuThermalProbe}
  abort "Expected approved pilot or thermal probe flag" unless ARGV.length == 1 && modes.key?(ARGV.first)
  exit(modes.fetch(ARGV.first).new.run ? 0 : 1)
end
