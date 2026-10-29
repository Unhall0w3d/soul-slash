# frozen_string_literal: true

module SoulCore
  # Foreign NVIDIA clients are not evidence of an unreleased Soul runtime.
  # Only the AMD visual provider is qualified for this independent-device path.
  module CreativeWorkloadAdmission
    GIB = 1024**3
    VISUAL_LAUNCH_FREE = 10 * GIB
    VISUAL_RUNTIME_FREE = 2 * GIB
    FOREIGN_LIMIT = 7 * GIB

    # Conservative existing visual envelope, not a weight-size estimate. The
    # pre-launch budget includes the working set and reserve; resident work
    # checks only remaining headroom. Unknown app names are not resource usage.
    # admission:nil is release verification, which allocates nothing itself.
    def self.amd_visual!(sample, owned_pid: nil, admission: nil)
      total, used = sample.values_at('total', 'used')
      unless total.is_a?(Integer) && total.positive? && used.is_a?(Integer) && used.between?(0, total)
        raise ArgumentError, 'invalid AMD memory accounting'
      end
      unless admission.nil?
        required = admission ? VISUAL_LAUNCH_FREE : VISUAL_RUNTIME_FREE
        raise ArgumentError, 'AMD headroom bound' if total - used < required
      end
      foreign_bytes = 0
      sample.fetch('clients').each do |client|
        bytes, holders = client.values_at('bytes', 'holders')
        unless bytes.is_a?(Integer) && bytes >= 0 && holders.is_a?(Array) && !holders.empty? &&
            holders.all? { |h| h.is_a?(Hash) && h['pid'].is_a?(Integer) && h['pid'].positive? &&
              h['uid'].is_a?(Integer) && h['uid'] >= 0 && h['exe'].is_a?(String) && !h['exe'].empty? }
          raise ArgumentError, 'incomplete AMD ownership'
        end
        owned = owned_pid && holders.all? { |h| h['pid'] == owned_pid && h['uid'] == Process.uid }
        next if owned
        foreign_bytes += bytes
        # Preserve detection of leftover/competing model or renderer processes.
        # Mixed holders never inherit an owned-PID exemption.
        if holders.any? { |h| %w[llama-server sd-cli].include?(File.basename(h['exe'].delete_suffix(' (deleted)'))) }
          raise ArgumentError, 'model or renderer still owns AMD'
        end
      end
      raise ArgumentError, 'desktop aggregate AMD allocation bound' if foreign_bytes >= FOREIGN_LIMIT
      true
    end

    def self.nvidia_environment!(sample, runtime_paths:, desktop_pids: [], executable: ->(pid) { File.readlink("/proc/#{pid}/exe") })
      raise ArgumentError, 'unexpected NVIDIA device' unless sample.fetch('name') == 'NVIDIA GeForce GTX 1070'
      temperature = sample.fetch('temperature_c')
      raise ArgumentError, 'invalid NVIDIA temperature' unless temperature.is_a?(Numeric) && temperature.finite? && temperature.between?(0, 150)
      raise ArgumentError, 'NVIDIA 88 C cutoff' unless temperature < 88
      ram = sample.fetch('ram_available_kib')
      raise ArgumentError, 'RAM below 4 GiB' unless ram.is_a?(Integer) && ram >= 4 * 1024**2
      raise ArgumentError, 'runtime identities missing' if runtime_paths.empty?
      sample.fetch('compute_pids').each do |pid|
        raise ArgumentError, 'invalid GPU process identity' unless pid.is_a?(Integer) && pid.positive?
        begin
          path = executable.call(pid).delete_suffix(' (deleted)')
        rescue Errno::EACCES
          # KWin can be nondumpable. Only the caller's existing qualified,
          # identity-checked <=64MiB compositor baseline may use this fallback.
          raise unless desktop_pids.include?(pid)
          next
        end
        raise ArgumentError, 'Soul runtime still on NVIDIA' if runtime_paths.include?(path)
      end
      # This path does not allocate NVIDIA memory. The AMD renderer's stricter
      # 8 GiB RAM, VRAM reserves and paging checks still run before/during work.
      true
    end
  end
end
