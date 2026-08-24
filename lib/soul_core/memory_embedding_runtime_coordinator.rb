# frozen_string_literal: true

require_relative "bounded_command_runner"

module SoulCore
  # Reconciles the reviewed embedding endpoint with the selected Core. The
  # model itself remains demand-loaded by Ollama and semantic retrieval always
  # retains its lexical failure path.
  class MemoryEmbeddingRuntimeCoordinator
    UNIT_NAME = "soul-memory-embedding.service"
    COMMAND_TIMEOUT_SECONDS = 12
    MAX_OUTPUT_BYTES = 8 * 1024

    def initialize(runner: BoundedCommandRunner.new, systemctl_path: nil)
      @runner = runner
      @systemctl_path = systemctl_path || @runner.which("systemctl")
    end

    def status
      state = service_state
      ok = %w[active inactive].include?(state)
      lifecycle = state == "unavailable" ? "blocked_for_human_review" : (ok ? "complete" : "failed")
      message = ok ? "Embedding runtime state collected." : "Embedding runtime unit is not installed exactly."
      message = "Embedding runtime state is unavailable." if state == "unknown"
      outcome(ok, lifecycle, message,
              "service" => UNIT_NAME, "service_state" => state, "endpoint_active" => state == "active",
              "context_length" => 1_024, "model_load_policy" => "demand_with_5m_idle_eviction")
    end

    def reconcile(core_id:)
      core = core_id.to_s
      return outcome(false, "blocked_for_human_review", "Known Core is required.") unless %w[daily amd-free music free dev].include?(core)

      state = service_state
      return outcome(false, "blocked_for_human_review", "Embedding runtime unit is not installed exactly.") if state == "unavailable"
      return outcome(false, "failed", "Embedding runtime state is unavailable.") if state == "unknown"

      wanted = core != "free"
      return outcome(true, "complete", "Embedding runtime already matches the selected Core.",
                     "service_state" => state, "changed" => false, "core_id" => core) if wanted == (state == "active")

      action = wanted ? "start" : "stop"
      result = run_systemctl(action, UNIT_NAME)
      return outcome(false, "failed", "Embedding runtime #{action} failed safely.", "command_status" => result.status) unless result.success?

      after = service_state
      expected = wanted ? "active" : "inactive"
      return outcome(false, "failed", "Embedding runtime did not reach #{expected} state.", "service_state" => after) unless after == expected

      outcome(true, "complete", "Embedding runtime reconciled with #{core} Core.",
              "service_state" => after, "changed" => true, "core_id" => core,
              "mutation" => wanted ? "embedding_endpoint_started" : "embedding_endpoint_stopped")
    end

    private

    def service_state
      return "unknown" unless @systemctl_path && File.file?(@systemctl_path) && File.executable?(@systemctl_path) && !File.symlink?(@systemctl_path)

      loaded = run_systemctl("show", UNIT_NAME, "--property=LoadState", "--value", "--no-pager")
      return "unknown" unless loaded.success?
      return "unavailable" unless loaded.stdout.to_s.strip == "loaded"

      active = run_systemctl("is-active", UNIT_NAME)
      value = active.stdout.to_s.strip
      return "active" if active.success? && value == "active"
      return "inactive" if value == "inactive"

      "unknown"
    end

    def run_systemctl(*arguments)
      @runner.run(@systemctl_path, "--user", *arguments, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
    end

    def outcome(ok, lifecycle_state, message, data = {})
      { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "data" => data,
        "mutation" => data.fetch("mutation", "none") }
    end
  end
end
