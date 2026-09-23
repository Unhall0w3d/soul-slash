# frozen_string_literal: true

require "digest"
require "json"
require_relative "voice_transcription_service"

module SoulCore
  # Isolated qualification adapter for the staged GTX 1070 whisper.cpp build.
  # The coordinator owns GPU admission and restoration; this adapter only runs
  # one bounded CLI invocation after that authority has granted the block.
  class CudaVoiceTranscriptionService < VoiceTranscriptionService
    CANDIDATE_RELEASE = "whisper-v1.9.1-cuda-sm61-20260905"
    CANDIDATE_MODEL = "ggml-large-v3-turbo.bin"
    CANDIDATE_MODEL_BYTES = 1_624_555_275
    CANDIDATE_MODEL_SHA256 = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    CANDIDATE_BINARY = "whisper-cli"
    CANDIDATE_BINARY_SHA256 = "5d0dac2d0f041210f1f552f1136c101d802d63671fee073433087cfb420076e0"
    CANDIDATE_CUDA_LIBRARY = "libggml-cuda.so.0.15.1"
    CANDIDATE_CUDA_LIBRARY_SHA256 = "ad924bed0d4256029c385fd2607fceab189ad6c31ad8aadb3ef902ca773a8888"
    CANDIDATE_GPU_NAME = "NVIDIA GeForce GTX 1070"

    def initialize(candidate_directory:, gpu_uuid:, coordinator:, **base_options)
      unless candidate_directory.is_a?(String) && candidate_directory.start_with?("/")
        raise ArgumentError, "candidate_directory must be an explicit absolute path"
      end
      unless gpu_uuid.is_a?(String) && gpu_uuid.match?(/\AGPU-[a-fA-F0-9-]+\z/)
        raise ArgumentError, "gpu_uuid must be an explicit NVIDIA UUID"
      end
      raise ArgumentError, "coordinator is required" unless coordinator

      @candidate_directory = candidate_directory
      @gpu_uuid = gpu_uuid.to_s
      @coordinator = coordinator
      @last_handoff_receipt = nil
      super(**base_options)

      # The base manifest supplies the audio language and normalization
      # configuration. Recognition identity is replaced with the separately
      # staged candidate so CPU model files can never be used by this adapter.
      @model_name = CANDIDATE_MODEL
      @model = {
        "bytes" => CANDIDATE_MODEL_BYTES,
        "sha256" => CANDIDATE_MODEL_SHA256,
        "language" => "en"
      }
    end

    def transcribe(audio_bytes:, content_type:)
      @last_handoff_receipt = nil
      super
    end

    private

    def environment_blockers
      items = super
      items << "CUDA candidate directory is missing" unless regular_directory?(@candidate_directory)
      items << "CUDA candidate bin directory is missing or unsafe" unless regular_directory?(bin_directory)
      items << "CUDA candidate library is missing" unless regular_file?(cuda_library_path)

      if regular_file?(binary_path)
        items << "CUDA candidate binary digest does not match" unless Digest::SHA256.file(binary_path).hexdigest == CANDIDATE_BINARY_SHA256
      end
      if regular_file?(cuda_library_path)
        items << "CUDA candidate library digest does not match" unless Digest::SHA256.file(cuda_library_path).hexdigest == CANDIDATE_CUDA_LIBRARY_SHA256
      end
      items
    end

    def runtime_receipt
      receipt = {
        "name" => "whisper.cpp-cuda",
        "release" => CANDIDATE_RELEASE,
        "model" => CANDIDATE_MODEL,
        "cpu_only" => false,
        "cuda" => true,
        "gpu_uuid" => @gpu_uuid,
        "device" => 0,
        "threads" => thread_count,
        "resident_after_completion" => false
      }
      receipt["handoff"] = @last_handoff_receipt if @last_handoff_receipt
      receipt
    end

    def transcribe_file(path, output_base)
      command = [
        binary_path, "--model", model_path, "--file", path,
        "--threads", thread_count.to_s, "--language", @model.fetch("language"),
        "--device", "0", "--no-flash-attn", "--output-json-full",
        "--output-file", output_base
      ]

      value, receipt = @coordinator.run do
        result = @runner.run(
          command,
          env: {
            "CUDA_VISIBLE_DEVICES" => @gpu_uuid,
            "LD_LIBRARY_PATH" => File.join(@candidate_directory, "bin")
          },
          chdir: File.dirname(path),
          timeout_seconds: TRANSCRIPTION_TIMEOUT_SECONDS,
          max_output_bytes: MAX_COMMAND_OUTPUT_BYTES
        )
        unless result.success? && !result.truncated
          raise ArgumentError, "CUDA speech recognition #{result.status}"
        end
        unless cuda_execution_proof?(result.stderr)
          raise ArgumentError, "CUDA speech recognition did not prove CUDA0 on #{CANDIDATE_GPU_NAME}"
        end

        output = "#{output_base}.json"
        unless File.file?(output) && !File.symlink?(output) && File.size(output).between?(1, MAX_TRANSCRIPT_BYTES)
          raise ArgumentError, "CUDA speech recognition output is missing"
        end
        JSON.parse(File.binread(output, MAX_TRANSCRIPT_BYTES))
      end

      unless receipt.is_a?(Hash) && receipt["restored"] == true
        raise ArgumentError, "CUDA speech recognition handoff was not restored"
      end
      @last_handoff_receipt = receipt
      value
    rescue StandardError => error
      raise ArgumentError, "CUDA speech recognition handoff failed: #{error.message}"
    end

    def binary_path
      File.join(@candidate_directory, "bin", CANDIDATE_BINARY)
    end

    def model_path
      File.join(@candidate_directory, CANDIDATE_MODEL)
    end

    def cuda_library_path
      File.join(bin_directory, CANDIDATE_CUDA_LIBRARY)
    end

    def bin_directory
      File.join(@candidate_directory, "bin")
    end

    def regular_directory?(path)
      stat = File.lstat(path)
      stat.directory? && !stat.symlink?
    rescue SystemCallError
      false
    end

    def regular_file?(path)
      stat = File.lstat(path)
      stat.file? && !stat.symlink?
    rescue SystemCallError
      false
    end

    def cuda_execution_proof?(stderr)
      text = stderr.to_s
      text.include?(CANDIDATE_GPU_NAME) && text.match?(/using\s+CUDA0\s+backend/i)
    end
  end
end
