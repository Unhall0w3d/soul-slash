# frozen_string_literal: true

require_relative "configuration_resolver"
require_relative "amd_voice_transcription_service"
require_relative "amd_whisper_runtime_handoff"

module SoulCore
  # All user-facing transcription paths share this policy. CPU/CUDA adapters
  # remain available to explicit offline qualification, never as fallbacks.
  class RoutedVoiceTranscriptionService
    def initialize(root: Dir.pwd, process_env: ENV, coordinator: nil, adapter: nil, **options)
      environment = ConfigurationResolver.new(root: root, process_env: process_env).tap(&:resolve).effective_environment
      @coordinator = coordinator || AmdWhisperRuntimeHandoff.new(root: root, env: environment)
      @adapter = adapter || AmdVoiceTranscriptionService.new(
        root: root, coordinator: @coordinator,
        candidate_directory: File.join(root, "Soul/runtime/qualification", AmdVoiceTranscriptionService::CANDIDATE_RELEASE), **options
      )
    end

    def status
      problem = @coordinator.status_blocker
      problem ? blocked(problem) : @adapter.status
    end

    def transcribe(audio_bytes:, content_type:)
      problem = @coordinator.status_blocker
      return blocked(problem) if problem
      @adapter.transcribe(audio_bytes: audio_bytes, content_type: content_type)
    end

    private

    def blocked(message)
      {"ok"=>false, "lifecycle_state"=>"blocked_for_human_review", "reason"=>message,
       "data"=>{"message"=>message, "available"=>false, "cpu_fallback"=>false,
                 "source_audio_retained"=>false, "automatically_sent"=>false}, "mutation"=>"none"}
    end
  end
end
