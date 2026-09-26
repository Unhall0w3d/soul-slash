# frozen_string_literal: true

require "json"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"
require_relative "model_runtime_profile_registry"
require_relative "core_orchestration_service"

module SoulCore
  class ModelRuntimeSelectedStarter
    MAX_SELECTION_BYTES = 1024
    COMMAND_TIMEOUT_SECONDS = 12
    MAX_OUTPUT_BYTES = 16 * 1024
    NVIDIA_READY_SECONDS = 15
    NVIDIA_PLACEMENT_SECONDS = 30
    NVIDIA_POLL_SECONDS = 0.25
    NVIDIA_MIN_MODEL_MIB = 4500
    NVIDIA_GPU_UUID = /\AGPU-[a-fA-F0-9-]+\z/

    Result = Struct.new(:ok, :lifecycle_state, :message, :details, keyword_init: true) do
      def to_h
        { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "details" => details }
      end
    end

    def initialize(root:, env:, runner: BoundedCommandRunner.new, lease_store: nil, profile_registry: nil, systemctl_path: nil,
                   nvidia_smi_path: nil, nvidia_device_ready: nil,
                   monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
      @root = File.expand_path(root)
      @env = env.to_h
      @runner = runner
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @profile_registry = profile_registry || ModelRuntimeProfileRegistry.new(root: @root, env: @env)
      @systemctl_path = systemctl_path || @runner.which("systemctl")
      @nvidia_smi_path = nvidia_smi_path || @runner.which("nvidia-smi")
      @nvidia_device_ready = nvidia_device_ready || -> { %w[/dev/nvidia0 /dev/nvidiactl].all? { |path| File.chardev?(path) } }
      @monotonic_clock = monotonic_clock
      @sleeper = sleeper
    end

    def run
      return failed("systemctl is unavailable") unless executable?(@systemctl_path)

      configuration = @profile_registry.configuration
      @lease_store.with_control_lock do
        selected_id = selected_profile_id(configuration)
        profiles = configuration.fetch("profiles")
        core_id = CoreOrchestrationService.new(root: @root, env: @env)
          .persisted_selection(profiles: profiles).fetch("active_core_id")
        states = profiles.to_h { |profile| [profile.fetch("id"), service_state(profile.fetch("service"))] }
        return blocked("one or more model runtime service states are uncertain", selected_id, states) if states.value?("unknown")

        active_ids = states.select { |_id, state| state == "active" }.keys
        if core_id == "free"
          return blocked("Free Core is selected but a chat runtime is active; no automatic stop was attempted", selected_id, states) unless active_ids.empty?

          return complete("Free Core is selected; no chat runtime was started.", selected_id, states, started: false, core_id: core_id)
        end
        selected = profiles.find { |profile| profile.fetch("id") == selected_id }
        if active_ids == [selected_id]
          if nvidia_profile?(selected) && !nvidia_placement?(selected, nvidia_identity, wait: false)
            return blocked("selected NVIDIA runtime is active without verified GPU placement", selected_id, states)
          end
          return complete("Selected model runtime is already active; no startup mutation was needed.", selected_id, states, started: false, core_id: core_id)
        end
        unless active_ids.empty?
          return blocked("a non-selected or conflicting model runtime is already active", selected_id, states)
        end

        if nvidia_profile?(selected) && !executable?(@nvidia_smi_path)
          return failed("nvidia-smi is unavailable for selected NVIDIA startup", "selected_profile_id" => selected_id, "states" => states)
        end
        gpu_uuid = nvidia_profile?(selected) ? wait_for_nvidia_ready : nil
        if nvidia_profile?(selected) && !gpu_uuid
          return failed("selected NVIDIA GPU was not ready before startup deadline", "selected_profile_id" => selected_id, "states" => states)
        end
        started = run_systemctl("start", selected.fetch("service"))
        return failed("selected model runtime start command #{started.status}", "selected_profile_id" => selected_id, "states" => states, "command_exit_status" => started.exit_status) unless started.success?

        after = profiles.to_h { |profile| [profile.fetch("id"), service_state(profile.fetch("service"))] }
        return failed("selected model runtime did not become solely active", "selected_profile_id" => selected_id, "states" => after) unless after[selected_id] == "active" && after.count { |_id, state| state == "active" } == 1

        if gpu_uuid && !nvidia_placement?(selected, gpu_uuid, wait: true)
          stopped = run_systemctl("stop", selected.fetch("service"))
          stopped_state = service_state(selected.fetch("service"))
          return failed("selected NVIDIA runtime did not establish verified GPU placement; exact started unit cleanup #{stopped.success? && stopped_state == 'inactive' ? 'succeeded' : 'failed'}",
                        "selected_profile_id" => selected_id, "states" => after,
                        "cleanup_state" => stopped_state, "cleanup_command_status" => stopped.status,
                        "started" => true)
        end

        complete("Selected model runtime started.", selected_id, after, started: true, core_id: core_id)
      end
    rescue ModelRuntimeProfileRegistry::ConfigurationError, ModelRuntimeLeaseStore::IntegrityError, CoreOrchestrationService::IntegrityError => error
      blocked(error.message, nil, {})
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy", nil, {})
    rescue SystemCallError
      blocked("model runtime startup files could not be read safely", nil, {})
    end

    private

    def nvidia_profile?(profile)
      profile.fetch("id") == "nvidia-fallback" &&
        profile.fetch("service") == "llama-server.service" &&
        profile.fetch("accelerator", "").downcase.include?("nvidia")
    end

    def nvidia_identity
      return nil unless executable?(@nvidia_smi_path) && @nvidia_device_ready.call

      result = @runner.run(@nvidia_smi_path, "--id=0", "--query-gpu=uuid", "--format=csv,noheader",
                           timeout_seconds: 3, max_output_bytes: 1024)
      return nil unless result.success? && !result.truncated

      uuid = result.stdout.to_s.strip
      uuid if uuid.match?(NVIDIA_GPU_UUID) && !uuid.include?("\n")
    end

    def wait_for_nvidia_ready
      deadline = @monotonic_clock.call + NVIDIA_READY_SECONDS
      ((NVIDIA_READY_SECONDS / NVIDIA_POLL_SECONDS).ceil + 1).times do
        identity = nvidia_identity
        return identity if identity
        break if @monotonic_clock.call >= deadline

        @sleeper.call(NVIDIA_POLL_SECONDS)
      end
      nil
    end

    def nvidia_placement?(profile, gpu_uuid, wait:)
      return false unless gpu_uuid

      deadline = @monotonic_clock.call + (wait ? NVIDIA_PLACEMENT_SECONDS : 0)
      attempts = wait ? (NVIDIA_PLACEMENT_SECONDS / NVIDIA_POLL_SECONDS).ceil + 1 : 1
      attempts.times do
        return true if nvidia_allocation?(profile.fetch("service"), gpu_uuid)
        break if @monotonic_clock.call >= deadline

        @sleeper.call(NVIDIA_POLL_SECONDS)
      end
      false
    end

    def nvidia_allocation?(service, gpu_uuid)
      pid_result = run_systemctl("show", service, "--property=MainPID", "--value", "--no-pager")
      pid = pid_result.stdout.to_s.strip
      return false unless pid_result.success? && !pid_result.truncated && pid.match?(/\A[1-9][0-9]*\z/)

      result = @runner.run(@nvidia_smi_path, "--query-compute-apps=pid,gpu_uuid,used_gpu_memory", "--format=csv,noheader,nounits",
                           timeout_seconds: 3, max_output_bytes: MAX_OUTPUT_BYTES)
      return false unless result.success? && !result.truncated

      rows = result.stdout.to_s.lines.map { |line| line.strip.split(/\s*,\s*/) }
      return false unless rows.all? { |row| row.length == 3 && row[0].match?(/\A[1-9][0-9]*\z/) && row[1].match?(NVIDIA_GPU_UUID) && row[2].match?(/\A[0-9]+\z/) }

      matching = rows.select { |row| row[0] == pid && row[1] == gpu_uuid }
      matching.one? && matching.first[2].to_i >= NVIDIA_MIN_MODEL_MIB
    end

    def selected_profile_id(configuration)
      path = File.join(@root, ModelRuntimeLeaseStore::DEFAULT_DIRECTORY, "selected_profile.json")
      return configuration.fetch("default_profile") unless File.exist?(path) || File.symlink?(path)

      stat = File.lstat(path)
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection exceeds size limit" if stat.size > MAX_SELECTION_BYTES

      record = JSON.parse(File.binread(path, MAX_SELECTION_BYTES))
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid" unless record.is_a?(Hash)
      id = record["profile_id"].to_s
      valid = record.keys == ["profile_id"] && configuration.fetch("profiles").any? { |profile| profile.fetch("id") == id }
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid" unless valid

      id
    rescue JSON::ParserError
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid"
    end

    def service_state(service)
      loaded = run_systemctl("show", service, "--property=LoadState", "--value", "--no-pager")
      return "unknown" unless loaded.success? && loaded.stdout.to_s.strip == "loaded"

      active = run_systemctl("is-active", service)
      value = active.stdout.to_s.strip
      return "active" if active.success? && value == "active"
      return "inactive" if value == "inactive"

      "unknown"
    end

    def run_systemctl(*arguments)
      @runner.run(@systemctl_path, "--user", *arguments, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
    end

    def executable?(path)
      path && File.file?(path) && File.executable?(path) && !File.symlink?(path)
    end

    def complete(message, selected_id, states, started:, core_id:)
      Result.new(ok: true, lifecycle_state: "complete", message: message, details: {
        "selected_profile_id" => selected_id, "profile_states" => states, "started" => started, "active_core_id" => core_id,
        "automatic_stop" => false, "retries" => 0
      })
    end

    def blocked(message, selected_id, states)
      Result.new(ok: false, lifecycle_state: "blocked_for_human_review", message: message, details: {
        "selected_profile_id" => selected_id, "profile_states" => states, "started" => false
      })
    end

    def failed(message, details = {})
      Result.new(ok: false, lifecycle_state: "failed", message: message, details: details.merge("started" => details.fetch("started", false)))
    end
  end
end
