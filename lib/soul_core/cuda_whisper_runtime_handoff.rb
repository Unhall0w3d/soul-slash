# frozen_string_literal: true

require_relative "whisper_runtime_handoff"
require_relative "core_orchestration_service"

module SoulCore
  # Applies the same selected-Core gate to the qualified NVIDIA handoff.
  # The parent owns the GPU lock, pending receipt, bounded release, and restore.
  class CudaWhisperRuntimeHandoff < WhisperRuntimeHandoff
    def initialize(root:, env:, control: nil, selection: nil, **options)
      super(root: root, env: env, control: control, **options)
      @selection = selection || CoreOrchestrationService.new(root: root, env: env, runtime_control: @control)
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

    def policy_blocker(before)
      selected = @selection.persisted_selection(profiles: before.fetch("profiles"))["active_core_id"]
      return "Free Core disables transcription; select a chat Core first" if selected == "free"
      return "Select a known chat Core before transcription" unless %w[daily amd-free music dev].include?(selected)
      return "Selected Core has no single active chat runtime" unless before["active_profile_count"] == 1 && !before["profile_conflict"]
      nil
    rescue StandardError => error
      "Core selection cannot be verified: #{error.message}"
    end
  end
end
