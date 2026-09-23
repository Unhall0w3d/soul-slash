# frozen_string_literal: true

require "digest"
require "json"
require_relative "voice_transcription_service"

module SoulCore
  # Isolated qualification adapter for the staged RX 6900 XT whisper.cpp build.
  # The coordinator owns GPU admission and restoration; this adapter only runs
  # one bounded CLI invocation after that authority has granted the block.
  class AmdVoiceTranscriptionService < VoiceTranscriptionService
    CANDIDATE_RELEASE = "whisper-v1.9.1-vulkan-rx6900xt-20260905"
    CANDIDATE_MODEL = "ggml-large-v3-turbo.bin"
    CANDIDATE_MODEL_BYTES = 1_624_555_275
    CANDIDATE_MODEL_SHA256 = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    CANDIDATE_BINARY = "whisper-cli"
    CANDIDATE_BINARY_SHA256 = "551c5df9f0f86eadc091ef87afa7941703f2a2e27ee9a988492249d089025a5e"
    CANDIDATE_VULKAN_LIBRARY = "libggml-vulkan.so.0.15.1"
    CANDIDATE_VULKAN_LIBRARY_SHA256 = "5bf24ff73444dbf162d2f0c64ded3fd63848942898bfe6b062b240977cd2af78"
    CANDIDATE_GPU_NAME = "AMD Radeon RX 6900 XT"
    CANDIDATE_WHISPER_LIBRARY = "libwhisper.so.1.9.1"
    CANDIDATE_WHISPER_LIBRARY_SHA256 = "979550ffa7d5bda6dbebdb0f9fa141acdd8fe3abdb821a28a50a8ac8332f046f"

    def initialize(candidate_directory:, coordinator:, **base_options)
      unless candidate_directory.is_a?(String) && candidate_directory.start_with?("/")
        raise ArgumentError, "candidate_directory must be an explicit absolute path"
      end
      raise ArgumentError, "coordinator is required" unless coordinator

      @candidate_directory = candidate_directory
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
      items << "Vulkan candidate directory is missing" unless regular_directory?(@candidate_directory)
      items << "Vulkan candidate bin directory is missing or unsafe" unless regular_directory?(bin_directory)
      items << "Vulkan candidate library is missing" unless regular_file?(vulkan_library_path)
      items << "GPU-required Whisper library is missing" unless regular_file?(whisper_library_path)
      if regular_file?(whisper_library_path)
        items << "GPU-required Whisper library digest does not match" unless Digest::SHA256.file(whisper_library_path).hexdigest == CANDIDATE_WHISPER_LIBRARY_SHA256
        items << "Whisper loader link does not select the GPU-required build" unless resolved_library("libwhisper.so.1") == whisper_library_path
      end

      if regular_file?(binary_path)
        items << "Vulkan candidate binary digest does not match" unless Digest::SHA256.file(binary_path).hexdigest == CANDIDATE_BINARY_SHA256
      end
      if regular_file?(vulkan_library_path)
        items << "Vulkan candidate library digest does not match" unless Digest::SHA256.file(vulkan_library_path).hexdigest == CANDIDATE_VULKAN_LIBRARY_SHA256
      end
      items
    end

    def runtime_receipt
      receipt = {
        "name" => "whisper.cpp-vulkan",
        "release" => CANDIDATE_RELEASE,
        "model" => CANDIDATE_MODEL,
        "cpu_only" => false,
        "vulkan" => true,
        "gpu" => CANDIDATE_GPU_NAME,
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
        "--device", "0", "--no-flash-attn", "--output-json-full", "--output-file", output_base
      ]

      value, receipt = @coordinator.run do
        result = @runner.run(
          command,
          env: {
            "VK_DRIVER_FILES" => "/usr/share/vulkan/icd.d/radeon_icd.json",
            "VK_ICD_FILENAMES" => nil,
            "GGML_VK_VISIBLE_DEVICES" => "0",
            "VK_LOADER_LAYERS_DISABLE" => "~implicit~",
            "LD_LIBRARY_PATH" => File.join(@candidate_directory, "bin")
          },
          chdir: File.dirname(path),
          timeout_seconds: TRANSCRIPTION_TIMEOUT_SECONDS,
          max_output_bytes: MAX_COMMAND_OUTPUT_BYTES
        )
        unless result.success? && !result.truncated
          raise ArgumentError, "Vulkan speech recognition #{result.status}"
        end
        unless vulkan_execution_proof?(result.stderr)
          raise ArgumentError, "Vulkan speech recognition did not prove Vulkan0 on #{CANDIDATE_GPU_NAME}"
        end

        output = "#{output_base}.json"
        unless File.file?(output) && !File.symlink?(output) && File.size(output).between?(1, MAX_TRANSCRIPT_BYTES)
          raise ArgumentError, "Vulkan speech recognition output is missing"
        end
        JSON.parse(File.binread(output, MAX_TRANSCRIPT_BYTES))
      end

      unless receipt.is_a?(Hash) && receipt["restored"] == true
        raise ArgumentError, "Vulkan speech recognition handoff was not restored"
      end
      @last_handoff_receipt = receipt
      value
    rescue StandardError => error
      raise ArgumentError, "Vulkan speech recognition handoff failed: #{error.message}"
    end

    def binary_path
      File.join(@candidate_directory, "bin", CANDIDATE_BINARY)
    end

    def model_path
      File.join(@candidate_directory, CANDIDATE_MODEL)
    end

    def vulkan_library_path
      File.join(bin_directory, CANDIDATE_VULKAN_LIBRARY)
    end

    def whisper_library_path
      File.join(bin_directory, CANDIDATE_WHISPER_LIBRARY)
    end

    def resolved_library(name)
      File.realpath(File.join(bin_directory, name))
    rescue SystemCallError
      nil
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

    def vulkan_execution_proof?(stderr)
      text = stderr.to_s
      text.include?(CANDIDATE_GPU_NAME) && text.match?(/using\s+Vulkan0\s+backend/i)
    end
  end
end
