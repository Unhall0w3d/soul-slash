# frozen_string_literal: true

require_relative "config"
require_relative "../model_runtime_lease_store"

module SoulCore
  module ContinuityLab
    class AdmissionDenied < Error; end

    class AdmissionGate
      FIELDS = %w[active_slots captured_at core dedicated_window model_file pending_transition profile_id service_active].freeze

      def initialize(lease_store:, snapshot_provider:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     lock_wait_seconds: 0, sleeper: ->(seconds) { sleep(seconds) }, on_contention: ->(_event) {})
        raise ValidationError, "expected runtime lease store" unless lease_store.instance_of?(ModelRuntimeLeaseStore)
        unless lock_wait_seconds.is_a?(Numeric) && lock_wait_seconds.finite? && lock_wait_seconds.between?(0, 5)
          raise ValidationError, "invalid admission lock wait"
        end
        @lease_store, @snapshot_provider, @clock = lease_store, snapshot_provider, clock
        @lock_wait, @sleeper, @on_contention = lock_wait_seconds, sleeper, on_contention
      end

      # The provider is trusted host code, never model-selected. A snapshot and
      # cooperative lock cannot exclude an uncoordinated direct endpoint client.
      def with_window
        deadline = @clock.call + @lock_wait
        attempts = 0
        loop do
          entered = false
          attempts += 1
          begin
            return @lease_store.with_control_lock do
              # Once this boundary is crossed, no exception may replay admission
              # checks or the caller's block (which can have generated a response).
              entered = true
              raise AdmissionDenied, "retained model leases require a quiet window" unless @lease_store.leases_for_quiescent_admission_unlocked.empty?
              validate_snapshot!(@snapshot_provider.call)
              yield
            end
          rescue ModelRuntimeLeaseStore::LockUnavailable
            raise if entered
            remaining = deadline - @clock.call
            retryable = @lock_wait.positive? && remaining.positive? && attempts < 21
            @on_contention.call({ "attempt" => attempts, "retry" => retryable })
            raise unless retryable
            @sleeper.call([0.25, remaining].min)
            raise AdmissionDenied, "admission lock wait exhausted" if @clock.call >= deadline
          end
        end
      rescue ModelRuntimeLeaseStore::LockUnavailable, ModelRuntimeLeaseStore::IntegrityError => error
        raise AdmissionDenied, "model admission unavailable: #{error.class}"
      end

      def validate_snapshot!(snapshot)
        unless snapshot.is_a?(Hash) && snapshot.keys.sort == FIELDS &&
               snapshot["captured_at"].is_a?(Numeric) && snapshot["captured_at"].finite? &&
               %w[amd-free dev music].include?(snapshot["core"]) &&
               snapshot["profile_id"] == "nvidia-fallback" && snapshot["model_file"] == "Qwen3-8B-Q4_K_M.gguf" &&
               snapshot["service_active"] == true && snapshot["pending_transition"] == false &&
               snapshot["dedicated_window"] == true && snapshot["active_slots"].is_a?(Integer) && snapshot["active_slots"].zero?
          raise AdmissionDenied, "missing or unsuitable model/Core/window evidence"
        end
        age = @clock.call - snapshot["captured_at"]
        raise AdmissionDenied, "stale or future admission evidence" unless age.finite? && age.between?(0, 2)
        true
      end
    end
  end
end
