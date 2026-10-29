# frozen_string_literal: true

require "json"
require "timeout"

module MixedGpuTelemetry
  PCI = "0000:0a:00.0"
  MAX_SECONDS = 2700
  class Invalid < StandardError; end
  class IncompleteOwnership < Invalid; end

  def self.start_ticks(text)
    Integer(text.split(") ", 2).fetch(1).split.fetch(19))
  end

  def self.parse_client(text)
    return nil unless text.match?(/^drm-pdev:\s+#{Regexp.escape(PCI)}$/)
    id = text[/^drm-client-id:\s+(\d+)$/, 1]
    resident = text.match(/^drm-resident-vram:\s+(\d+) (KiB|MiB|GiB)$/)
    raise Invalid, "incomplete AMD client" unless id && resident
    {"id" => id, "bytes" => resident[1].to_i * {"KiB"=>1024, "MiB"=>1024**2, "GiB"=>1024**3}.fetch(resident[2]),
     "compute" => text.scan(/^drm-engine-compute[^:]*:\s+(\d+) ns$/).flatten.sum(&:to_i)}
  end

  def self.validate_fresh!(sample, now:, previous_sequence:)
    raise Invalid, "telemetry is not a sample" unless sample.fetch("state") == "sample"
    age = now - Float(sample.fetch("monotonic"))
    raise Invalid, "stale or future telemetry" unless age.between?(0, 3)
    raise Invalid, "replayed telemetry" unless Integer(sample.fetch("sequence")) > previous_sequence
    raise Invalid, "wrong GPU" unless sample.fetch("pci") == PCI
    total, used = sample.values_at("total", "used")
    raise Invalid, "invalid VRAM totals" unless total.is_a?(Integer) && total >= 15 * 1024**3 && used.is_a?(Integer) && used.between?(0, total)
    clients = sample.fetch("clients")
    raise Invalid, "duplicate DRM clients" unless clients.map { |c| c.fetch("id") }.uniq.length == clients.length
    accounted = clients.sum do |client|
      bytes = client.fetch("bytes")
      raise Invalid, "invalid client allocation" unless bytes.is_a?(Integer) && bytes >= 0
      bytes
    end
    raise IncompleteOwnership, "AMD memory ownership is incomplete" if used > accounted + 256 * 1024**2
    sample
  end

  class Collector
    def initialize(parent_pid:, uid:, duration:)
      raise Invalid, "invalid lifetime" unless duration.between?(1, MAX_SECONDS)
      raise Invalid, "invalid parent" unless parent_pid > 1 && uid > 0
      @parent, @uid, @duration = parent_pid, uid, duration
      raise Invalid, "parent owner mismatch" unless File.stat("/proc/#{@parent}").uid == @uid
      @start = MixedGpuTelemetry.start_ticks(File.read("/proc/#{@parent}/stat"))
    end

    def parent_alive?
      File.stat("/proc/#{@parent}").uid == @uid &&
        MixedGpuTelemetry.start_ticks(File.read("/proc/#{@parent}/stat")) == @start
    rescue Errno::ENOENT, Errno::ESRCH
      false
    end

    def sample(sequence)
      attempts = []
      snapshot = nil
      # Re-read the entire snapshot, never combine old clients with new totals.
      # Two seconds leaves headroom under the consumer's three-second freshness gate.
      Timeout.timeout(2) do
        3.times do
          raise Invalid, "parent exited during sampling" unless parent_alive?
          snapshot = collect_once(sequence)
          begin
            MixedGpuTelemetry.validate_fresh!(snapshot,
              now: Process.clock_gettime(Process::CLOCK_MONOTONIC), previous_sequence: sequence - 1)
            return snapshot.merge("accounting_rechecks"=>attempts)
          rescue IncompleteOwnership
            attempts << {"monotonic"=>snapshot.fetch("monotonic"), "used"=>snapshot.fetch("used"),
                         "accounted"=>snapshot.fetch("clients").sum { |client| client.fetch("bytes") }}
          end
        end
      end
      # Return the rejected evidence for the consumer to log and refuse as before.
      snapshot.merge("accounting_rechecks"=>attempts)
    rescue Timeout::Error
      raise Invalid, "AMD accounting resample deadline exceeded"
    end

    def collect_once(sequence)
      Timeout.timeout(3) do
        sampled_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        clients = {}
        descriptors = 0
        Dir.glob('/proc/[0-9]*').each do |process|
          begin
            Dir.children("#{process}/fdinfo").each do |fd|
              descriptors += 1
              raise Invalid, "descriptor bound exceeded" if descriptors > 20_000
              row = MixedGpuTelemetry.parse_client(File.read("#{process}/fdinfo/#{fd}", 65_536))
              next unless row
              # Shared handles must not be counted more than once. Retain all
              # holders so a shared client is never mistaken for solely ours.
              holder = {"pid"=>File.basename(process).to_i, "uid"=>File.stat(process).uid,
                        "exe"=>File.readlink("#{process}/exe"),
                        "start_ticks"=>MixedGpuTelemetry.start_ticks(File.read("#{process}/stat"))}
              existing = clients[row.fetch("id")]
              if existing
                existing["holders"] |= [holder]
              else
                clients[row.fetch("id")] = row.merge("holders"=>[holder])
              end
            end
          rescue Errno::ENOENT, Errno::ESRCH
            next
          end
        end
        device = "/sys/bus/pci/devices/#{PCI}"
        raise Invalid, "wrong AMD identity" unless File.read("#{device}/vendor").strip == "0x1002" && File.read("#{device}/device").strip == "0x73bf"
        {"state"=>"sample", "sequence"=>sequence, "monotonic"=>sampled_at,
         "pci"=>PCI, "total"=>Integer(File.read("#{device}/mem_info_vram_total")),
         "used"=>Integer(File.read("#{device}/mem_info_vram_used")), "clients"=>clients.values}
      end
    end

    def run(output: $stdout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @duration
      sequence = 0
      while parent_alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        output.puts(JSON.generate(sample(sequence += 1)))
        output.flush
        sleep 0.5
      end
      output.puts(JSON.generate("state"=>"complete", "reason"=>parent_alive? ? "timeout" : "parent_exited"))
      output.flush
    end
  end
end
