# frozen_string_literal: true

require_relative "model_runtime_lease_store"
require_relative "roster_chat_adapter"

module SoulCore
  # Foreground ownership only. A trusted driver supplies bounded start, fresh
  # admission/identity evidence, transport and stop/reap/release verification.
  # Drivers are host capabilities, never model- or HTTP-client-selected values.
  class RosterRuntimeOwner
    class Unavailable < StandardError; end
    attr_reader :binding

    def initialize(leases:, driver:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, isolated_models: [])
      raise ArgumentError, "lease store required" unless leases.instance_of?(ModelRuntimeLeaseStore)
      unless isolated_models.is_a?(Array) && isolated_models.uniq == isolated_models &&
             (isolated_models - RosterChatAdapter::ISOLATED_MODELS).empty?
        raise ArgumentError, "unknown isolated candidate"
      end
      expected_models = RosterChatAdapter::MODELS + isolated_models
      @leases, @driver, @clock = leases, driver, clock
      @binding = JSON.parse(JSON.generate(driver.binding))
      unless @binding.keys.sort == expected_models.sort && @binding.values.all? { |v|
        v.is_a?(Hash) && v.keys.sort == %w[artifact_sha256 launch_sha256 server_sha256] &&
          v.values.all? { |digest| digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/) }
      }
        raise ArgumentError, "immutable artifact/build/launch roster required"
      end
      @binding.each_value { |v| v.each_value(&:freeze); v.freeze }
      @binding.freeze
      @mutex = Mutex.new
    end

    def with_runtime(adapter:, request_id:, conversation_id:, deadline:, cancel:)
      locked = @mutex.try_lock
      raise Unavailable, "runtime owner busy" unless locked
      check!(deadline, cancel)
      raise Unavailable, "model absent from owned roster" unless adapter.instance_of?(RosterChatAdapter) && binding.key?(adapter.model)
      raise Unavailable, "runtime binding drift" unless @driver.binding == binding
      lease = @leases.acquire_quiescent(provider_id: "local.roster", model_id: adapter.model,
        request_id: request_id, conversation_id: conversation_id,
        resource_group: "amd-vulkan-generation", ttl_seconds: 660)
      entered = false
      @leases.with_control_lock do
        entries = @leases.leases_for_quiescent_admission_unlocked
        raise Unavailable, "ownership changed" unless entries == [lease]
        check!(deadline, cancel)
        # Cleanup is required even when start raises after partially spawning.
        entered = true
        begin
          @driver.start(adapter: adapter, ownership_id: lease.fetch("lease_id"), deadline: deadline, cancel: cancel)
          admission = lambda do
            check!(deadline, cancel)
            evidence = @driver.observe(ownership_id: lease.fetch("lease_id"), deadline: deadline)
            expected = binding.fetch(adapter.model)
            age = evidence.is_a?(Hash) && evidence["captured_at"].is_a?(Numeric) ? @clock.call - evidence["captured_at"] : -1
            unless evidence.is_a?(Hash) && evidence["ownership_id"] == lease["lease_id"] &&
                   evidence["model"] == adapter.model && evidence["identity"] == expected &&
                   evidence["admitted"] == true && evidence["pid"].is_a?(Integer) && evidence["pid"].positive? &&
                   evidence["process_start"].is_a?(String) && !evidence["process_start"].empty? && age.between?(0, 2)
              raise Unavailable, "runtime identity or resource admission failed"
            end
            identity = evidence.slice("pid", "process_start", "ownership_id", "model", "identity")
            raise Unavailable, "runtime process changed" if @identity && @identity != identity
            @identity = identity
            true
          end
          admission.call
          value = yield(@driver, admission, JSON.parse(JSON.generate(@identity)))
          admission.call
        ensure
          # Deadline/cancellation cannot skip teardown. A separate bounded cleanup
          # window is mandatory; ambiguous cleanup keeps the durable lease.
          clean = @driver.stop_and_verify(ownership_id: lease.fetch("lease_id"), deadline: @clock.call + 30)
          raise Unavailable, "cleanup unverified; lease retained" unless clean == true
          @leases.release(lease.fetch("lease_id"))
          lease = nil
        end
        value
      end
    ensure
      @leases.release(lease["lease_id"]) if lease && !entered
      @identity = nil if locked
      @mutex.unlock if locked
    end

    private

    def check!(deadline, cancel)
      unless deadline.is_a?(Numeric) && deadline.finite? && (@clock.call < deadline) && deadline - @clock.call <= 180 && !cancel.call
        raise Unavailable, "canceled or request deadline invalid/exhausted"
      end
    end
  end
end
