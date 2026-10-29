# frozen_string_literal: true
require "digest"
require "fileutils"
require "securerandom"
require_relative "gpu_accounting_snapshot"
require_relative "bounded_command_runner"
require_relative "desktop_gpu_allowances"
require_relative "telemetry_diagnostic"
require_relative "creative_workload_admission"

module SoulCore
  # Foreground renderer only; no collector survives run(). Foreign desktop
  # applications are admitted by resources, not executable familiarity.
  class CreativeRenderGuard
    GIB = 1024**3
    BASELINE = "Soul/runtime/qualification/desktop-baseline-20261024-UAjUponi/telemetry.jsonl"
    BASELINE_SHA = "8ba2bcee0c00bf2be925dd203c4320faf266c5d78a303d83cbd01f4561d850ad"
    def initialize(root:, runner: BoundedCommandRunner.new, sampler: nil, control: nil)
      @root, @runner, @sampler, @control = root, runner, sampler, control
    end

    def run(*command, **options, &block)
      return @runner.run(*command, **options, &block) unless File.basename(command.flatten.first.to_s) == "sd-cli"
      samples = []
      client = GpuAccountingSnapshot.new
      handoff_id = @control&.status&.dig("data", "handoff", "handoff_id")
      sample = @sampler || if @control
        -> { remote_capture(client, handoff_id) }
      else
        -> { capture(client) }
      end
      initial = sample.call
      initial_swap = initial.fetch("swap_pages")
      validate!(initial, allowed: [], pid: nil, initial_swap: initial_swap, admission: true)
      samples << initial
      result = @runner.run(*command, **options, monitor: ->(pid) {
        row = sample.call
        samples << row
        validate!(row, allowed: [], pid: pid, initial_swap: initial_swap, admission: false)
      }, &block)
      result
    rescue StandardError => error
      result = BoundedCommandRunner::Result.new(status: "guard_refused", stdout: "", stderr: "#{error.class}: #{error.message}", truncated: false)
    ensure
      if defined?(samples) && samples
        directory = File.join(@root, "Soul/runtime/qualification/creative-monitor")
        FileUtils.mkdir_p(directory, mode: 0o700)
        path = File.join(directory, "#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(8)}.json")
        File.write(path, JSON.pretty_generate({status: result&.status, error: result&.stderr, samples: samples}), mode: "wx", perm: 0o600)
      end
    end

    def remote_capture(client, handoff_id)
      response = @control.telemetry(handoff_id: handoff_id)
      unless response["ok"]
        code=response["diagnostic_code"]
        code='control_unavailable' unless TelemetryDiagnostic::CODES.include?(code)
        raise "coordinator telemetry unavailable: #{code}"
      end
      row = response.fetch("data")
      # Revalidate freshness, monotonic progress and complete accounting at
      # the receiver too; a successful HTTP response is not fresh evidence.
      client.send(:decode, JSON.generate(row.fetch("amd")))
      row
    end

    def validate!(row, allowed:, pid:, initial_swap:, admission:)
      amd = row.fetch("amd")
      CreativeWorkloadAdmission.amd_visual!(amd, owned_pid: pid, admission: admission)
      {"edge"=>90, "junction"=>100, "mem"=>90}.each do |label, limit|
        value = row.fetch("temperatures").fetch(label)
        raise "invalid thermal sensor" unless value.is_a?(Numeric) && value.finite? && value.between?(0, 150)
        raise "AMD #{label} thermal bound" if value >= limit
      end
      raise "RAM headroom below 8 GiB" if row.fetch("ram_available_kib") < 8*1024**2
      delta = row.fetch("swap_pages") - initial_swap
      # Retain host-wide paging for diagnosis, without treating unrelated host
      # reclaim as renderer failure. RAM, VRAM and thermal guards remain above.
      raise "invalid paging telemetry" unless delta.is_a?(Integer) && delta >= 0
      true
    end

    def capture(client)
      amd = client.sample
      hw = Dir.glob("/sys/bus/pci/devices/0000:0a:00.0/hwmon/hwmon*").first or raise "missing AMD sensors"
      temperatures = Dir.glob("#{hw}/temp*_input").to_h { |p| [File.read(p.sub(/_input$/, "_label")).strip, Integer(File.read(p))/1000.0] }
      {"amd"=>amd, "temperatures"=>temperatures,
       "ram_available_kib"=>Integer(File.read("/proc/meminfo")[/^MemAvailable:\s+(\d+)/,1]),
       "swap_pages"=>Integer(File.read("/proc/vmstat")[/^pswpout (\d+)$/,1])}
    end
  end
end
