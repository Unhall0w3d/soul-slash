# frozen_string_literal: true

require "securerandom"
require_relative "amd_whisper_device"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"

module SoulCore
  # An opt-in lease for foreground external work; it cannot reserve the GPU
  # against games or other programs that do not participate in Soul's protocol.
  class ExternalAmdWorkloadGate
    RESOURCE_GROUP = "amd-vulkan-generation"
    MAX_SECONDS = 3_600
    MAX_OUTPUT_BYTES = 8 * 1024

    def initialize(root: Dir.pwd, device: AmdWhisperDevice.new,
                   leases: ModelRuntimeLeaseStore.new(root: root), runner: BoundedCommandRunner.new)
      @device = device
      @leases = leases
      @runner = runner
    end

    def status(min_free_bytes: 0)
      @device.verify_vulkan!
      sample = @device.snapshot(services: [])
      { "ok" => sample.fetch("free") >= min_free_bytes,
        "advisory_only" => true, "gpu" => sample.fetch("pci"),
        "free_bytes" => sample.fetch("free"), "minimum_free_bytes" => min_free_bytes,
        "message" => "A point-in-time observation is not an OS-wide reservation." }
    rescue ArgumentError => error
      { "ok" => false, "advisory_only" => true, "message" => error.message }
    end

    def run(command:, timeout_seconds:, min_free_bytes:)
      raise ArgumentError, "command is required" unless command.is_a?(Array) && !command.empty? && command.all? { |arg| arg.is_a?(String) && !arg.empty? }
      timeout = Integer(timeout_seconds)
      raise ArgumentError, "timeout must be between 1 and #{MAX_SECONDS} seconds" unless timeout.between?(1, MAX_SECONDS)
      minimum = Integer(min_free_bytes)
      raise ArgumentError, "minimum free bytes must be nonnegative" if minimum.negative?

      @device.verify_vulkan!
      initial = @device.snapshot(services: [])
      raise ModelRuntimeLeaseStore::ResourceBusy, "AMD free VRAM is below the requested minimum" if initial.fetch("free") < minimum
      lease = @leases.acquire_exclusive(
        provider_id: "external.codex.amd", model_id: "foreground-workload",
        request_id: "external-#{SecureRandom.hex(8)}", resource_group: RESOURCE_GROUP,
        ttl_seconds: timeout + 60
      )
      sample = @device.snapshot(services: [])
      raise ModelRuntimeLeaseStore::ResourceBusy, "AMD free VRAM is below the requested minimum" if sample.fetch("free") < minimum

      result = @runner.run(*command, timeout_seconds: timeout, max_output_bytes: MAX_OUTPUT_BYTES)
      { "ok" => result.success?, "status" => result.status, "exit_status" => result.exit_status,
        "output_truncated" => result.truncated, "output_omitted" => true,
        "message" => "The foreground child has exited and its Soul resource lease was released." }
    rescue ModelRuntimeLeaseStore::ResourceBusy, AmdWhisperDevice::AllocationUnsettled, ArgumentError => error
      { "ok" => false, "status" => "blocked", "message" => error.message }
    ensure
      @leases.release(lease["lease_id"]) if defined?(lease) && lease
    end
  end
end
