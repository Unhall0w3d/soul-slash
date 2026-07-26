# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "bounded_command_runner"

module SoulCore
  class VoiceTranscriptionService
    MAX_UPLOAD_BYTES = 8 * 1024 * 1024
    MAX_DURATION_SECONDS = 60.0
    MIN_DURATION_SECONDS = 0.15
    PROBE_TIMEOUT_SECONDS = 10
    NORMALIZE_TIMEOUT_SECONDS = 30
    TRANSCRIPTION_TIMEOUT_SECONDS = 180
    MAX_COMMAND_OUTPUT_BYTES = 256 * 1024
    MAX_TRANSCRIPT_BYTES = 512 * 1024

    CONTENT_TYPES = {
      "audio/webm" => ".webm",
      "audio/mp4" => ".m4a",
      "audio/ogg" => ".ogg",
      "audio/wav" => ".wav",
      "audio/x-wav" => ".wav"
    }.freeze

    def initialize(
      root: Dir.pwd,
      music_root: ENV.fetch("SOUL_MUSIC_ROOT", File.join(Dir.home, ".local", "share", "soul", "music")),
      manifest_path: ENV.fetch("SOUL_TRANSCRIPTION_MANIFEST", File.expand_path("../../config/music_transcription_models.json", __dir__)),
      model_name: ENV["SOUL_TRANSCRIPTION_MODEL"],
      runner: BoundedCommandRunner.new
    )
      @root = File.expand_path(root)
      @music_root = File.expand_path(music_root)
      @manifest_path = File.expand_path(manifest_path)
      @runner = runner
      @manifest = load_manifest
      @runtime = @manifest.fetch("runtime")
      @model_name = model_name.to_s.empty? ? @manifest.fetch("models").keys.first : model_name
      @model = @manifest.fetch("models").fetch(@model_name)
      @install_dir = File.join(@music_root, "transcription", @runtime.fetch("release"))
    end

    def status
      blockers = environment_blockers
      outcome(
        blockers.empty? ? "complete" : "blocked_for_human_review",
        blockers.empty?,
        blockers.empty? ? "bounded local microphone transcription is ready" : blockers.join("; "),
        data: {
          "available" => blockers.empty?,
          "runtime" => runtime_receipt,
          "accepted_content_types" => CONTENT_TYPES.keys,
          "max_upload_bytes" => MAX_UPLOAD_BYTES,
          "max_duration_seconds" => MAX_DURATION_SECONDS,
          "setup_hint" => "make voice-transcription-plan"
        }
      )
    end

    def transcribe(audio_bytes:, content_type:)
      media_type = content_type.to_s.split(";", 2).first.to_s.strip.downcase
      extension = CONTENT_TYPES[media_type]
      return outcome("awaiting_input", false, "recording type is unsupported") unless extension
      return outcome("awaiting_input", false, "recording is empty") if audio_bytes.to_s.empty?
      return outcome("awaiting_input", false, "recording exceeds #{MAX_UPLOAD_BYTES} bytes") if audio_bytes.bytesize > MAX_UPLOAD_BYTES

      blockers = environment_blockers
      return outcome("blocked_for_human_review", false, blockers.join("; "), data: { "setup_hint" => "make voice-transcription-plan" }) unless blockers.empty?

      temporary = Dir.mktmpdir("soul-voice-")
      File.chmod(0o700, temporary)
      source = File.join(temporary, "source#{extension}")
      normalized = File.join(temporary, "normalized.wav")
      output_base = File.join(temporary, "transcript")
      File.binwrite(source, audio_bytes, mode: "wx", perm: 0o600)

      # Browser MediaRecorder WebM output commonly omits a finite container
      # duration even though its Opus packets are valid. Normalize under an
      # explicit ceiling first, then validate the reliable PCM WAV duration.
      normalize(source, normalized)
      duration = probe_duration(normalized)
      unless duration.between?(MIN_DURATION_SECONDS, MAX_DURATION_SECONDS)
        return outcome("awaiting_input", false, "recording duration must be between #{MIN_DURATION_SECONDS} and #{MAX_DURATION_SECONDS.to_i} seconds")
      end

      whisper = transcribe_file(normalized, output_base)
      transcript = transcript_text(whisper)
      return outcome("awaiting_input", false, "no speech was detected; nothing was added to the composer") if transcript.empty?

      outcome("complete", true, "transcription is ready for Operator review", data: {
        "transcript" => transcript,
        "duration_seconds" => duration.round(2),
        "language" => @model.fetch("language"),
        "runtime" => runtime_receipt,
        "source_audio_retained" => false,
        "normalized_audio_retained" => false,
        "automatically_sent" => false
      })
    rescue JSON::ParserError, KeyError, SystemCallError, ArgumentError => error
      outcome("failed", false, "microphone transcription failed safely: #{error.message}")
    ensure
      FileUtils.remove_entry_secure(temporary) if defined?(temporary) && temporary && File.directory?(temporary)
    end

    private

    def probe_duration(path)
      result = @runner.run(
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", path,
        timeout_seconds: PROBE_TIMEOUT_SECONDS,
        max_output_bytes: 4096
      )
      raise ArgumentError, "recording container could not be inspected" unless result.success?

      duration = Float(result.stdout.to_s.strip)
      raise ArgumentError, "recording duration is invalid" unless duration.finite?

      duration
    rescue ArgumentError
      raise ArgumentError, "recording duration is invalid"
    end

    def normalize(source, destination)
      result = @runner.run(
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", source, "-t", (MAX_DURATION_SECONDS + 0.25).to_s,
        "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", destination,
        timeout_seconds: NORMALIZE_TIMEOUT_SECONDS,
        max_output_bytes: MAX_COMMAND_OUTPUT_BYTES
      )
      raise ArgumentError, "recording normalization #{result.status}" unless result.success?
      raise ArgumentError, "normalized recording is missing" unless File.file?(destination) && !File.symlink?(destination) && File.size(destination).positive?
    end

    def transcribe_file(path, output_base)
      command = [
        binary_path, "--model", model_path, "--file", path,
        "--threads", thread_count.to_s, "--language", @model.fetch("language"),
        "--no-gpu", "--output-json-full", "--output-file", output_base, "--no-prints"
      ]
      result = @runner.run(
        command,
        env: { "LD_LIBRARY_PATH" => @install_dir },
        chdir: File.dirname(path),
        timeout_seconds: TRANSCRIPTION_TIMEOUT_SECONDS,
        max_output_bytes: MAX_COMMAND_OUTPUT_BYTES
      )
      raise ArgumentError, "speech recognition #{result.status}" unless result.success?

      output = "#{output_base}.json"
      unless File.file?(output) && !File.symlink?(output) && File.size(output).between?(1, MAX_TRANSCRIPT_BYTES)
        raise ArgumentError, "speech recognition output is missing"
      end
      JSON.parse(File.binread(output, MAX_TRANSCRIPT_BYTES))
    end

    def transcript_text(value)
      Array(value["transcription"]).filter_map do |segment|
        text = segment["text"].to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").strip
        text unless text.empty?
      end.join(" ").gsub(/\s+/, " ").strip
    end

    def environment_blockers
      items = []
      items << "ffprobe is unavailable" unless @runner.which("ffprobe")
      items << "ffmpeg is unavailable" unless @runner.which("ffmpeg")
      items << "pinned whisper.cpp binary is missing" unless File.executable?(binary_path) && !File.symlink?(binary_path)
      items << "pinned transcription model is missing" unless File.file?(model_path) && !File.symlink?(model_path)
      if items.empty?
        items << "transcription model byte count does not match" unless File.size(model_path) == @model.fetch("bytes")
        items << "transcription model digest does not match" unless Digest::SHA256.file(model_path).hexdigest == @model.fetch("sha256")
      end
      items
    end

    def runtime_receipt
      {
        "name" => @runtime.fetch("name"),
        "release" => @runtime.fetch("release"),
        "model" => @model_name,
        "cpu_only" => true,
        "threads" => thread_count,
        "resident_after_completion" => false
      }
    end

    def binary_path = File.join(@install_dir, @runtime.fetch("binary"))
    def model_path = File.join(@install_dir, @model_name)
    def thread_count = [[Etc.nprocessors / 2, 1].max, 8].min

    def load_manifest
      stat = File.lstat(@manifest_path)
      raise ArgumentError, "transcription manifest must be a regular file" unless stat.file? && !stat.symlink?
      raise ArgumentError, "transcription manifest is too large" unless stat.size.between?(1, 256 * 1024)

      value = JSON.parse(File.binread(@manifest_path, 256 * 1024))
      raise ArgumentError, "unsupported transcription manifest" unless value["schema_version"] == "soul.music_transcription.models.v1"
      value
    rescue Errno::ENOENT
      raise ArgumentError, "transcription manifest is missing"
    end

    def outcome(state, ok, message, data: {})
      {
        "schema_version" => "soul.application.v1",
        "request_id" => "voice-#{Process.pid}-#{Thread.current.object_id}",
        "timestamp" => Time.now.utc.iso8601,
        "lifecycle_state" => state,
        "mutation" => "none",
        "ok" => ok,
        "data" => data.merge("message" => message),
        "errors" => ok ? [] : [{ "code" => "voice_transcription", "message" => message }]
      }
    end
  end
end
