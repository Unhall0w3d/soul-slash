# frozen_string_literal: true

require_relative "bounded_command_runner"

module SoulCore
  # DRM observations are admission evidence, not an OS-wide GPU reservation.
  # Desktop graphics may coexist; large foreign allocations are never evicted.
  class AmdWhisperDevice
    class AllocationUnsettled < ArgumentError; end
    PCI = "0000:0a:00.0"
    GIB = 1024**3
    DESKTOP_BINARIES = %w[/usr/bin/Hyprland /usr/bin/quickshell].freeze
    VULKAN_ENV = {"VK_DRIVER_FILES"=>"/usr/share/vulkan/icd.d/radeon_icd.json", "VK_ICD_FILENAMES"=>nil,
                  "GGML_VK_VISIBLE_DEVICES"=>"0", "VK_LOADER_LAYERS_DISABLE"=>"~implicit~"}.freeze

    def initialize(runner: BoundedCommandRunner.new)
      @runner = runner
    end

    def verify_vulkan!
      result = @runner.run("vulkaninfo", "--summary", env: VULKAN_ENV, timeout_seconds: 8, max_output_bytes: 32768)
      text = result.stdout
      valid = result.success? && !result.truncated && text.scan(/^GPU\d+:$/) == ["GPU0:"] &&
        text.match?(/deviceUUID\s*=\s*00000000-0a00-0000-0000-000000000000\s*$/) &&
        text.match?(/deviceName\s*=\s*AMD Radeon RX 6900 XT \(RADV NAVI21\)/)
      raise ArgumentError, "Vulkan0 identity does not match the reviewed RX 6900 XT" unless valid
    end

    def snapshot(services: [])
      total, used = read_device
      raise ArgumentError, "AMD VRAM telemetry is invalid" unless total >= 15 * GIB && used.between?(0, total)
      first = clients(services)
      sleep(0.1)
      second = clients(services)
      # Read global usage after the client scan, not before process teardown.
      # Driver accounting can settle slightly later than the CLI's exit.
      total, used = read_device
      raise ArgumentError, "AMD VRAM telemetry is invalid" unless total >= 15 * GIB && used.between?(0, total)
      second.each do |id, row|
        previous = first[id]
        if row["owner"] && (!previous || row["compute"] != previous["compute"])
          raise ArgumentError, "managed AMD model is computing; refusing release"
        end
        next if row["owner"] || row["desktop"]
        raise ArgumentError, "foreign AMD allocation is present" if row["bytes"] >= 512 * 1024**2
        if (!previous && row["compute"].positive?) || (previous && row["compute"] - previous["compute"] > 10_000_000)
          raise ArgumentError, "foreign AMD compute is active"
        end
      end
      allocations = Hash.new(0)
      second.each_value { |row| allocations[row["owner"]] += row["bytes"] if row["owner"] }
      # Some system processes hide fdinfo. Reconcile visible unique DRM clients
      # with global VRAM; unexplained large allocations prevent admission.
      accounted = second.values.sum { |row| row["bytes"] }
      raise AllocationUnsettled, "AMD memory ownership is incomplete" if used > accounted + 256 * 1024**2
      {"pci"=>PCI, "total"=>total, "used"=>used, "free"=>total-used, "allocations"=>allocations}
    rescue SystemCallError => error
      raise ArgumentError, "AMD ownership telemetry unavailable: #{error.class}"
    end

    private

    def read_device
      device = "/sys/bus/pci/devices/#{PCI}"
      raise ArgumentError, "reviewed RX 6900 XT is unavailable" unless File.read("#{device}/vendor").strip == "0x1002" && File.read("#{device}/device").strip == "0x73bf"
      [Integer(File.read("#{device}/mem_info_vram_total").strip, 10), Integer(File.read("#{device}/mem_info_vram_used").strip, 10)]
    end

    def clients(services)
      clients = {}
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      descriptors = 0
      Dir.glob("/proc/[0-9]*").each do |process|
        begin
          raise ArgumentError, "AMD ownership scan exceeded its bound" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          group = File.read("#{process}/cgroup")
          owner = services.find { |service| File.stat(process).uid == Process.uid && group.lines.any? { |line| line.strip.end_with?("/#{service}") } }
          Dir.children("#{process}/fdinfo").each do |fd|
            descriptors += 1
            raise ArgumentError, "AMD descriptor scan exceeded its bound" if descriptors > 20_000 || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            info = File.read("#{process}/fdinfo/#{fd}")
            next unless info.match?(/^drm-pdev:\s+#{Regexp.escape(PCI)}$/)
            desktop = DESKTOP_BINARIES.include?(File.readlink("#{process}/exe"))
            id = info[/^drm-client-id:\s+(\d+)/, 1]
            raise ArgumentError, "AMD client telemetry is incomplete" unless id
            next if clients[id]
            match = info.match(/^drm-resident-vram:\s+(\d+) (KiB|MiB|GiB)$/)
            raise ArgumentError, "AMD allocation telemetry is incomplete" unless match
            bytes = match[1].to_i * {"KiB"=>1024, "MiB"=>1024**2, "GiB"=>GIB}.fetch(match[2])
            # DRM engine counters are cumulative. Compare their deltas instead
            # of mistaking past browser/compositor activity for a current job.
            compute = info.scan(/^drm-engine-compute[^:]*:\s+(\d+) ns$/).flatten.sum(&:to_i)
            clients[id] = {"owner"=>owner, "desktop"=>desktop, "bytes"=>bytes, "compute"=>compute}
          end
        rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
          # Exited or protected processes are covered by global VRAM reconciliation.
          next
        end
      end
      clients
    end
  end
end
