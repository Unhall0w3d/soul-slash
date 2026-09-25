# frozen_string_literal: true

require_relative "configuration_resolver"
require_relative "amd_voice_transcription_service"
require_relative "amd_whisper_runtime_handoff"
require_relative "cuda_voice_transcription_service"
require_relative "cuda_whisper_runtime_handoff"

module SoulCore
  # User-facing transcription defaults to AMD. An explicit session setting
  # selects the qualified CUDA handoff; CPU never becomes an implicit fallback.
  class RoutedVoiceTranscriptionService
    attr_reader :backend

    def initialize(root: Dir.pwd, process_env: ENV, coordinator: nil, adapter: nil, **options)
      requested = process_env.to_h["SOUL_WHISPER_GPU_BACKEND"].to_s.strip.downcase
      @backend = requested.empty? ? "amd" : requested
      @route_error = "unsupported Whisper GPU backend" unless %w[amd cuda].include?(@backend)
      return if @route_error

      environment = ConfigurationResolver.new(root: root, process_env: process_env).tap(&:resolve).effective_environment
      if @backend == "cuda"
        @coordinator = coordinator || CudaWhisperRuntimeHandoff.new(root: root, env: environment)
        @adapter = adapter || CudaVoiceTranscriptionService.new(
          root: root, coordinator: @coordinator, gpu_uuid: WhisperRuntimeHandoff::GPU_UUID,
          candidate_directory: File.join(root, "Soul/runtime/qualification", CudaVoiceTranscriptionService::CANDIDATE_RELEASE), **options
        )
      else
        @coordinator = coordinator || AmdWhisperRuntimeHandoff.new(root: root, env: environment)
        @adapter = adapter || AmdVoiceTranscriptionService.new(
          root: root, coordinator: @coordinator,
          candidate_directory: File.join(root, "Soul/runtime/qualification", AmdVoiceTranscriptionService::CANDIDATE_RELEASE), **options
        )
      end
    end

    def status
      return blocked(@route_error) if @route_error
      problem = @coordinator.status_blocker
      problem ? blocked(problem) : @adapter.status
    end

    def transcribe(audio_bytes:, content_type:)
      return blocked(@route_error) if @route_error
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
