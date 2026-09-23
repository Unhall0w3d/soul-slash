# frozen_string_literal: true

require_relative "whisper_runtime_handoff"
require_relative "core_orchestration_service"
require_relative "amd_whisper_device"

module SoulCore
  # Reuses the foreground admission loop and pending-journal protection. NVIDIA
  # release/placement methods are deliberately not used by this transaction.
  class AmdWhisperRuntimeHandoff < WhisperRuntimeHandoff
    def initialize(root:, env:, control: nil, runner: BoundedCommandRunner.new,
                   device: AmdWhisperDevice.new, selection: nil, **timing)
      super(root: root, env: env, control: control, runner: runner, **timing)
      @env, @device = env.to_h, device
      @selection = selection || CoreOrchestrationService.new(root: root, env: env, runtime_control: @control)
    end

    def policy_blocker(before)
      selected = @selection.persisted_selection(profiles: before.fetch("profiles"))["active_core_id"]
      return "Free Core disables transcription; select a chat Core first" if selected == "free"
      return "Select a known chat Core before transcription" unless %w[daily amd-free music dev].include?(selected)
      return "Selected Core has no single active chat runtime" unless before["active_profile_count"] == 1 && !before["profile_conflict"]
      nil
    rescue StandardError => error
      "Core selection cannot be verified: #{error.message}"
    end

    def status_blocker
      result = @control.status
      return result["reason"] || "Model runtime status unavailable" unless result["ok"]
      policy_blocker(result.fetch("data"))
    end

    private

    def admissible?(before)
      problem = policy_blocker(before)
      raise Error, problem if problem
      super
    end

    def targets(before)
      rows = before.fetch("profiles").select { |p| p["service_state"] == "active" && p.fetch("accelerator").match?(/AMD/i) }
      raise Error, "AMD chat runtime is not supported by the Ollama handoff" unless rows.all? { |p| p["runtime"] == "ollama_openai" }
      dev_state = @control.send(:observe_service_state, DevModelRuntimeCoordinator::UNIT_NAME)
      raise Busy, "Dev runtime state is uncertain" unless %w[active inactive].include?(dev_state)
      if dev_state == "active" && rows.none? { |p| p["service"] == DevModelRuntimeCoordinator::UNIT_NAME }
        rows << {"id"=>"dev", "service"=>DevModelRuntimeCoordinator::UNIT_NAME,
                 "endpoint"=>@env.fetch("SOUL_DEV_MODEL_ENDPOINT", DevModelRuntimeCoordinator::DEFAULT_ENDPOINT) + "/v1"}
      end
      rows.each do |row|
        uri = URI(row.fetch("endpoint"))
        raise Error, "AMD runtime must be a managed loopback endpoint" unless uri.scheme == "http" && %w[127.0.0.1 localhost ::1].include?(uri.host) && uri.path == "/v1" && !uri.userinfo && !uri.query && !uri.fragment
      end
      rows.map { |row| row.merge("pinned_residency"=>row["service"] == DevModelRuntimeCoordinator::UNIT_NAME && @selection.persisted_selection(profiles: before.fetch("profiles"))["active_core_id"] == "dev") }
    end

    def resident_models(target)
      raw = @control.send(:bounded_http_get, URI(target.fetch("endpoint").sub(%r{/v1$}, "/api/ps")))
      raise Error, "AMD resident model inventory unavailable" unless raw.is_a?(Hash) && raw[:status] == 200
      models = JSON.parse(raw.fetch(:body)).fetch("models")
      raise Error, "AMD model inventory is invalid" unless models.is_a?(Array) && models.length <= 4
      models.map do |m|
        row = m.slice("name", "digest", "size_vram", "context_length", "expires_at")
        valid = row["name"].is_a?(String) && row["name"].match?(%r{\A[A-Za-z0-9][A-Za-z0-9_.:/-]{0,119}\z}) &&
          row["digest"].to_s.match?(/\A[a-f0-9]{64}\z/) && row["size_vram"].is_a?(Integer) && row["size_vram"].positive? &&
          row["context_length"].is_a?(Integer) && row["context_length"].between?(1, 1_048_576)
        raise Error, "AMD model identity, GPU residency or context is unverified" unless valid
        Time.iso8601(row.fetch("expires_at"))
        row
      end
    end

    def transaction(before)
      # Selection is checked again while holding the same lock as Core changes.
      problem = policy_blocker(before)
      raise Error, problem if problem
      @device.verify_vulkan!
      borrowed = targets(before).map { |target| target.merge("models"=>resident_models(target)) }
      services = borrowed.map { |t| t.fetch("service") }
      initial = @device.snapshot(services: services)
      borrowed.each do |target|
        expected = target.fetch("models").sum { |m| m.fetch("size_vram") }
        actual = initial.fetch("allocations").fetch(target.fetch("service"), 0)
        raise Error, "AMD model is not placed on the reviewed device" if expected.positive? && actual < expected * 0.85
      end
      raise Error, "insufficient AMD memory for turbo" if borrowed.empty? && initial.fetch("free") < 5 * AmdWhisperDevice::GIB
      receipt = {"schema_version"=>"soul.whisper_amd_transaction.v1", "pid"=>Process.pid,
                 "started_at"=>Time.now.utc.iso8601, "pci"=>AmdWhisperDevice::PCI, "prior_runtimes"=>borrowed}
      File.open(@pending, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.generate(receipt)); f.flush; f.fsync }
      sync_directory
      attempted = []
      baseline = nil
      value = work_error = recovery_error = nil
      timings = {}
      begin
        started = @clock.call
        borrowed.each do |target|
          attempted << target
          stopped = @control.send(:service_command, "stop", target)
          raise Error, "AMD model stop was not verified" unless stopped.success? && @control.send(:observe_service_state, target.fetch("service")) == "inactive"
        end
        baseline = released_snapshot(services)
        timings["release_ms"] = ((@clock.call-started)*1000).round
        started = @clock.call
        value = yield
        timings["recognition_ms"] = ((@clock.call-started)*1000).round
      rescue Exception => error
        work_error = error
      ensure
        begin
          started = @clock.call
          if baseline
            clean = released_snapshot(services)
            raise Error, "AMD allocation remains after Whisper; refusing overlap" if clean.fetch("used") > baseline.fetch("used") + 256 * 1024**2
          end
          errors = []
          attempted.each do |target|
            begin
              restore(target, services: services)
            rescue StandardError => error
              errors << "#{target.fetch('service')}: #{error.message}"
            end
          end
          raise Error, errors.join("; ") unless errors.empty?
          after = @device.snapshot(services: services)
          borrowed.each do |target|
            prior = initial.fetch("allocations").fetch(target.fetch("service"), 0)
            raise Error, "AMD placement was not restored" if after.fetch("allocations").fetch(target.fetch("service"), 0) < prior * 0.85
          end
          File.unlink(@pending)
          sync_directory
          timings["recovery_ms"] = ((@clock.call-started)*1000).round
        rescue StandardError => error
          recovery_error = error
        end
      end
      raise Error, "AMD recovery incomplete; pending receipt retained: #{recovery_error.message}" if recovery_error
      raise work_error if work_error
      [value, receipt.merge("restored"=>true, "timings"=>timings)]
    end

    def released_snapshot(services)
      deadline = @clock.call + 5
      51.times do
        begin
          snapshot = @device.snapshot(services: services)
          clear = services.all? { |s| snapshot.fetch("allocations").fetch(s, 0).zero? }
          return snapshot if clear && snapshot.fetch("free") >= 5 * AmdWhisperDevice::GIB
        rescue AmdWhisperDevice::AllocationUnsettled
          # Incomplete accounting never grants admission; allow only the
          # existing cleanup deadline for driver teardown to settle.
        end
        raise Error, "AMD allocation did not clear or memory is insufficient" if @clock.call >= deadline
        @sleeper.call(0.1)
      end
      raise Error, "AMD cleanup attempt limit exceeded"
    end

    def restore(target, services:)
      state = @control.send(:observe_service_state, target.fetch("service"))
      if state == "inactive"
        snapshot = @device.snapshot(services: services)
        required = target.fetch("models").sum { |model| model.fetch("size_vram") }
        raise Error, "insufficient AMD memory for restoration" if snapshot.fetch("free") < required + 256 * 1024**2
        raise Error, "old AMD allocation remains during recovery" unless snapshot.fetch("allocations").fetch(target.fetch("service"), 0).zero?
        problem = @control.send(:restore_temporary_profile, target.merge("runtime"=>"ollama_openai", "api_model"=>target.fetch("models").first&.fetch("name", nil).to_s))
        raise Error, problem if problem
      elsif state != "active"
        raise Error, "AMD service state is uncertain during recovery"
      end
      current = resident_models(target)
      target.fetch("models").each do |model|
        next if current.any? { |m| same_model?(m, model) }
        expires = Time.iso8601(model.fetch("expires_at"))
        payload = {"model"=>model.fetch("name"), "prompt"=>"", "stream"=>false,
                   "keep_alive"=>target["pinned_residency"] ? -1 : [(expires - Time.now).ceil, 60].max,
                   "options"=>{"num_ctx"=>model.fetch("context_length"), "num_predict"=>1}}
        result = @runner.run("curl", "--silent", "--show-error", "--fail", "--max-time", "90",
                             "--noproxy", "*", "--header", "Content-Type: application/json",
                             "--data-binary", JSON.generate(payload), target.fetch("endpoint").sub(%r{/v1$}, "/api/generate"),
                             timeout_seconds: 95, max_output_bytes: 16384)
        raise Error, "AMD model reload failed" unless result.success? && !result.truncated
      end
      current = resident_models(target)
      raise Error, "AMD model identity/context/residency was not restored" unless current.length == target.fetch("models").length && target.fetch("models").all? { |model| current.any? { |m| same_model?(m, model) } }
    end

    def same_model?(current, prior)
      current.values_at("name", "digest", "context_length") == prior.values_at("name", "digest", "context_length") && current.fetch("size_vram") >= prior.fetch("size_vram") * 0.9
    end

    def sync_directory
      File.open(File.dirname(@pending), File::RDONLY) { |f| f.fsync }
    end
  end
end
