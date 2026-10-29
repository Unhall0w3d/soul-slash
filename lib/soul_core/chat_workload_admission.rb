# frozen_string_literal: true
require_relative 'creative_workload_admission'

module SoulCore
  # Per-device budgets are the existing qualified envelope, not pooled VRAM.
  # Runtime identity, complete AMD telemetry, RAM/paging and thermal monitoring
  # remain owned by the service driver and its qualified launch path.
  module ChatWorkloadAdmission
    def self.amd!(sample, owned_pid: nil)
      CreativeWorkloadAdmission.amd_visual!(sample, owned_pid: owned_pid)
    end

    def self.nvidia!(sample, expected_pid:, admission:, cutoff_c:)
      raise ArgumentError, 'unsupported thermal policy' unless [80, 88].include?(cutoff_c)
      raise ArgumentError, 'unexpected NVIDIA device' unless sample.fetch('name') == 'NVIDIA GeForce GTX 1070'
      temperature = sample.fetch('temperature_c')
      unless temperature.is_a?(Numeric) && temperature.finite? && temperature.between?(0, 150)
        raise ArgumentError, 'invalid NVIDIA temperature'
      end
      raise ArgumentError, 'NVIDIA thermal cutoff' if temperature >= cutoff_c
      free, used = sample.values_at('free_mib', 'used_mib')
      unless [free, used].all? { |v| v.is_a?(Integer) && v.between?(0, 8192) } && (free + used).between?(1, 8192)
        raise ArgumentError, 'invalid NVIDIA memory accounting'
      end
      raise ArgumentError, 'NVIDIA headroom bound' if free < (admission ? 6656 : 1024)
      ram = sample.fetch('ram_available_kib')
      raise ArgumentError, 'RAM below 8 GiB' unless ram.is_a?(Integer) && ram >= 8 * 1024**2
      processes, pids = sample.values_at('processes', 'compute_pids')
      unless processes.is_a?(Array) && pids.is_a?(Array) && pids.uniq == pids &&
          processes.map { |p| p.fetch('pid') }.sort == pids.sort
        raise ArgumentError, 'incomplete NVIDIA ownership'
      end
      processes.each do |process|
        unless process['pid'].is_a?(Integer) && process['pid'].positive? &&
            process['uid'].is_a?(Integer) && process['uid'] >= 0 &&
            process['start_ticks'].is_a?(Integer) && process['start_ticks'].positive? &&
            process['used_mib'].is_a?(Integer) && process['used_mib'].between?(0, 8192) &&
            %w[comm argv0].all? { |key| process[key].is_a?(String) && !process[key].empty? }
          raise ArgumentError, 'invalid NVIDIA process identity'
        end
        if process['pid'] == expected_pid
          raise ArgumentError, 'owned NVIDIA UID changed' unless process['uid'] == Process.uid
          next
        end
        if %w[comm argv0].any? { |key| %w[llama-server sd-cli ollama].include?(File.basename(process[key].delete_suffix(' (deleted)'))) }
          raise ArgumentError, 'foreign model or renderer on NVIDIA'
        end
      end
      true
    end
  end
end
