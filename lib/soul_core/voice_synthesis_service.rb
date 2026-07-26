# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "bounded_command_runner"
require_relative "model_runtime_control_service"
require_relative "model_runtime_lease_store"

module SoulCore
  class VoiceSynthesisService
    MAX_TEXT_CHARACTERS = 2_000
    MAX_TEXT_BYTES = 8 * 1024
    MAX_AUDIO_BYTES = 20 * 1024 * 1024
    SYNTHESIS_TIMEOUT_SECONDS = 120
    EXPRESSIVE_MAX_TEXT_CHARACTERS = 600
    EXPRESSIVE_TIMEOUT_SECONDS = 240
    MAX_COMMAND_OUTPUT_BYTES = 128 * 1024
    REFERENCE_TEXT = "Good evening, Operator. The path is clear. I am present, attentive, and ready to proceed.".freeze

    def initialize(
      root: Dir.pwd,
      runtime_root: ENV.fetch("SOUL_VOICE_SYNTHESIS_ROOT", File.join(Dir.home, ".local", "share", "soul", "voice", "runtime")),
      manifest_path: ENV.fetch("SOUL_VOICE_SYNTHESIS_MANIFEST", File.expand_path("../../config/voice_synthesis_models.json", __dir__)),
      voice_name: ENV["SOUL_VOICE_SYNTHESIS_VOICE"],
      speed: ENV["SOUL_VOICE_SYNTHESIS_SPEED"],
      expressive_root: ENV.fetch("SOUL_VOICE_EXPRESSIVE_ROOT", File.join(Dir.home, ".local", "share", "soul", "voice", "expressive")),
      expressive_manifest_path: ENV.fetch("SOUL_VOICE_EXPRESSIVE_MANIFEST", File.expand_path("../../config/voice_expressive_models.json", __dir__)),
      model_runtime_control: nil,
      lease_store: nil,
      process_env: ENV,
      runner: BoundedCommandRunner.new
    )
      @root = File.expand_path(root)
      @runtime_root = File.expand_path(runtime_root)
      @manifest_path = File.expand_path(manifest_path)
      @runner = runner
      @expressive_root = File.expand_path(expressive_root)
      @expressive_manifest_path = File.expand_path(expressive_manifest_path)
      @expressive_manifest = load_expressive_manifest
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @model_runtime_control = model_runtime_control || ModelRuntimeControlService.new(root: @root, env: process_env, lease_store: @lease_store)
      @manifest = load_manifest
      @runtime = @manifest.fetch("runtime")
      defaults = @manifest.fetch("defaults")
      @voice_name = voice_name.to_s.empty? ? defaults.fetch("voice") : voice_name.to_s
      raise ArgumentError, "unknown synthesis voice #{@voice_name}" unless @manifest.fetch("voices").key?(@voice_name)
      @speed = speed.to_s.empty? ? Float(defaults.fetch("speed")) : Float(speed)
      raise ArgumentError, "synthesis speed must be between 0.7 and 2.0" unless @speed.between?(0.7, 2.0)
      @synthesis_lock = Mutex.new
    end

    def status
      blockers = environment_blockers
      outcome(
        blockers.empty? ? "complete" : "blocked_for_human_review",
        blockers.empty?,
        blockers.empty? ? "bounded local speech synthesis is ready" : blockers.join("; "),
        data: {
          "available" => blockers.empty?,
          "runtime" => runtime_receipt,
          "voices" => @manifest.fetch("voices").keys,
          "max_text_characters" => MAX_TEXT_CHARACTERS,
          "resident_after_completion" => false,
          "automatic_playback" => false,
          "setup_hint" => "make voice-synthesis-plan",
          "qualities" => {
            "responsive" => { "available" => blockers.empty?, "engine" => @runtime.fetch("name"), "device" => "CPU" },
            "expressive" => expressive_status
          }
        }
      )
    end

    def synthesize(text:, voice_name: nil, quality: "responsive", on_progress: nil)
      selected_quality = quality.to_s
      return failure("awaiting_input", "requested voice quality is unavailable") unless %w[responsive expressive].include?(selected_quality)
      selected_voice = voice_name.to_s.empty? ? @voice_name : voice_name.to_s
      return failure("awaiting_input", "requested synthesis voice is unavailable") unless @manifest.fetch("voices").key?(selected_voice)
      normalized = normalize_text(text)
      return failure("awaiting_input", "this message does not contain eligible spoken prose") if normalized.empty?
      maximum = selected_quality == "expressive" ? EXPRESSIVE_MAX_TEXT_CHARACTERS : MAX_TEXT_CHARACTERS
      return failure("awaiting_input", "spoken text exceeds #{maximum} characters") if normalized.length > maximum
      return failure("awaiting_input", "spoken text exceeds #{MAX_TEXT_BYTES} bytes") if normalized.bytesize > MAX_TEXT_BYTES

      blockers = selected_quality == "expressive" ? expressive_environment_blockers : environment_blockers
      return failure("blocked_for_human_review", blockers.join("; ")) unless blockers.empty?
      return failure("awaiting_input", "Soul is already preparing speech; stop or wait for the active request") unless @synthesis_lock.try_lock

      temporary = Dir.mktmpdir("soul-speech-")
      File.chmod(0o700, temporary)
      input = File.join(temporary, "speech.txt")
      output = File.join(temporary, "speech.wav")
      File.binwrite(input, normalized, mode: "wx", perm: 0o600)
      device = "cpu"
      runtime_receipt = nil
      if selected_quality == "expressive"
        progress(on_progress, "preparing_reference", "Preparing a private voice reference for this request.")
        reference_text = File.join(temporary, "reference.txt")
        reference_audio = File.join(temporary, "reference.wav")
        File.binwrite(reference_text, REFERENCE_TEXT, mode: "wx", perm: 0o600)
        run_responsive!(input: reference_text, output: reference_audio, voice: selected_voice)
        progress(on_progress, "coordinating_resources", "Checking the active Core before expressive rendering.")
        device, runtime_receipt = run_expressive_coordinated!(
          input: input, reference_audio: reference_audio, output: output, on_progress: on_progress
        )
      else
        progress(on_progress, "rendering_voice", "Rendering the responsive local voice.")
        run_responsive!(input: input, output: output, voice: selected_voice)
      end
      validate_audio!(output)
      audio = File.binread(output, MAX_AUDIO_BYTES)
      {
        "lifecycle_state" => "complete",
        "ok" => true,
        "message" => "speech is ready",
        "audio" => audio,
        "content_type" => "audio/wav",
        "voice" => selected_voice,
        "quality" => selected_quality,
        "device" => device,
        "runtime_receipt" => runtime_receipt,
        "retained" => false
      }
    rescue ModelRuntimeControlService::TemporaryReleaseError => error
      failure(error.lifecycle_state, "expressive speech stopped safely: #{error.message}")
    rescue SystemCallError, ArgumentError => error
      failure("failed", "speech synthesis failed safely: #{error.message}")
    ensure
      FileUtils.remove_entry_secure(temporary) if defined?(temporary) && temporary && File.directory?(temporary)
      @synthesis_lock.unlock if @synthesis_lock.owned?
    end

    private

    def run_responsive!(input:, output:, voice:)
      result = @runner.run(
        python_path, runner_path, "--model-dir", model_dir, "--input", input, "--output", output,
        "--voice", voice, "--language", @manifest.dig("defaults", "language"),
        "--steps", @manifest.dig("defaults", "steps").to_s, "--speed", @speed.to_s,
        timeout_seconds: SYNTHESIS_TIMEOUT_SECONDS, max_output_bytes: MAX_COMMAND_OUTPUT_BYTES
      )
      raise ArgumentError, "timed out and was stopped" if result.status == "timeout"
      raise ArgumentError, "speech synthesis #{result.status}" unless result.success?
    end

    def run_expressive_coordinated!(input:, reference_audio:, output:, on_progress:)
      observation = @model_runtime_control.status
      active_id = observation.dig("data", "active_profile_id")
      active = observation.dig("data", "profiles")&.find { |profile| profile["id"] == active_id }
      if active && active.fetch("accelerator", "").to_s.downcase.include?("nvidia")
        progress(on_progress, "resource_handoff", "Evaluating a guarded NVIDIA chat-engine handoff.")
        begin
          value, receipt = @model_runtime_control.with_temporary_release(profile_id: active_id, on_progress: on_progress) do
            run_expressive!(input: input, reference_audio: reference_audio, output: output, device: "cuda", on_progress: on_progress)
            "cuda"
          end
          return [value, receipt]
        rescue ModelRuntimeControlService::TemporaryReleaseError => error
          raise if error.receipt["restored"] == false

          progress(on_progress, "cpu_fallback", "The NVIDIA chat engine cannot be interrupted; rendering expressive speech on CPU.")
          run_expressive!(input: input, reference_audio: reference_audio, output: output, device: "cpu", on_progress: on_progress)
          return ["cpu", { "nvidia_preserved" => true, "reason" => error.message }]
        end
      end

      lease = nil
      begin
        if nvidia_available?
          lease = @lease_store.acquire_exclusive(
            provider_id: "voice-expressive", model_id: "chatterbox-original",
            request_id: "voice-#{Process.pid}-#{Thread.current.object_id}",
            resource_group: "nvidia-specialist", ttl_seconds: EXPRESSIVE_TIMEOUT_SECONDS + 60
          )
          run_expressive!(input: input, reference_audio: reference_audio, output: output, device: "cuda", on_progress: on_progress)
          ["cuda", nil]
        else
          progress(on_progress, "cpu_fallback", "NVIDIA is unavailable; rendering expressive speech on CPU.")
          run_expressive!(input: input, reference_audio: reference_audio, output: output, device: "cpu", on_progress: on_progress)
          ["cpu", nil]
        end
      rescue ModelRuntimeLeaseStore::ResourceBusy, ModelRuntimeLeaseStore::LockUnavailable
        progress(on_progress, "cpu_fallback", "NVIDIA is occupied; rendering expressive speech on CPU without interrupting active work.")
        run_expressive!(input: input, reference_audio: reference_audio, output: output, device: "cpu", on_progress: on_progress)
        ["cpu", nil]
      ensure
        @lease_store.release(lease && lease["lease_id"])
      end
    end

    def run_expressive!(input:, reference_audio:, output:, device:, on_progress:)
      progress(on_progress, "rendering_voice", "Rendering expressive speech on #{device == 'cuda' ? 'NVIDIA' : 'CPU'}.")
      result = @runner.run(
        expressive_python_path, expressive_runner_path,
        "--model-dir", expressive_model_dir, "--input", input, "--reference", reference_audio,
        "--output", output, "--device", device, "--seed", "20260724",
        "--exaggeration", @expressive_manifest.dig("defaults", "exaggeration").to_s,
        "--cfg", @expressive_manifest.dig("defaults", "cfg_weight").to_s,
        timeout_seconds: EXPRESSIVE_TIMEOUT_SECONDS, max_output_bytes: MAX_COMMAND_OUTPUT_BYTES
      )
      raise ArgumentError, "expressive synthesis timed out and was stopped" if result.status == "timeout"
      raise ArgumentError, "expressive synthesis #{result.status}" unless result.success?
    end

    def nvidia_available?
      result = @runner.run("nvidia-smi", "--query-gpu=name", "--format=csv,noheader", timeout_seconds: 5, max_output_bytes: 4096)
      result.success? && !result.stdout.to_s.strip.empty?
    rescue StandardError
      false
    end

    def progress(callback, stage, message)
      callback&.call("stage" => stage, "message" => message)
    rescue StandardError
      nil
    end

    def normalize_text(value)
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
      text = text.gsub(/```.*?```/m, " ")
      text = text.gsub(/`[^`\n]+`/, " ")
      text = text.gsub(%r{https?://\S+}, " ")
      text = text.gsub(/^\s{0,3}\#{1,6}\s+/, "")
      text = text.gsub(/^\s*[-*+]\s+/, "")
      text = text.gsub(/[*_~>|]/, "")
      text.gsub(/\s+/, " ").strip
    end

    def validate_audio!(path)
      stat = File.lstat(path)
      raise ArgumentError, "speech output is invalid" unless stat.file? && !stat.symlink?
      raise ArgumentError, "speech output is empty" unless stat.size.between?(44, MAX_AUDIO_BYTES)
      header = File.binread(path, 12)
      raise ArgumentError, "speech output is not a WAV file" unless header.start_with?("RIFF") && header.byteslice(8, 4) == "WAVE"
    end

    def environment_blockers
      items = []
      items << "isolated synthesis Python is missing" unless File.executable?(python_path)
      items << "one-shot synthesis runner is missing" unless File.file?(runner_path) && !File.symlink?(runner_path)
      @manifest.fetch("assets").each do |relative, expected|
        path = File.join(model_dir, relative)
        unless File.file?(path) && !File.symlink?(path)
          items << "pinned synthesis asset is missing: #{relative}"
          next
        end
        items << "synthesis asset digest does not match: #{relative}" unless Digest::SHA256.file(path).hexdigest == expected
      end
      items
    end

    def expressive_environment_blockers
      items = environment_blockers
      items << "isolated expressive Python is missing" unless File.executable?(expressive_python_path)
      items << "one-shot expressive runner is missing" unless File.file?(expressive_runner_path) && !File.symlink?(expressive_runner_path)
      @expressive_manifest.fetch("assets").each do |relative, receipt|
        path = File.join(expressive_model_dir, relative)
        unless File.file?(path) && !File.symlink?(path)
          items << "pinned expressive asset is missing: #{relative}"
          next
        end
        items << "expressive asset size does not match: #{relative}" unless File.size(path) == receipt.fetch("bytes")
        items << "expressive asset digest does not match: #{relative}" unless Digest::SHA256.file(path).hexdigest == receipt.fetch("sha256")
      end
      items
    end

    def expressive_status
      blockers = expressive_environment_blockers
      {
        "available" => blockers.empty?,
        "engine" => @expressive_manifest.dig("runtime", "name"),
        "variant" => @expressive_manifest.dig("runtime", "variant"),
        "devices" => %w[NVIDIA CPU],
        "max_text_characters" => EXPRESSIVE_MAX_TEXT_CHARACTERS,
        "blockers" => blockers
      }
    end

    def runtime_receipt
      {
        "name" => @runtime.fetch("name"),
        "release" => @runtime.fetch("release"),
        "package_version" => @runtime.fetch("package_version"),
        "model_revision" => @runtime.fetch("revision"),
        "voice" => @voice_name,
        "speed" => @speed,
        "cpu_only" => @runtime.fetch("cpu_only"),
        "resident_after_completion" => false
      }
    end

    def failure(state, message)
      { "lifecycle_state" => state, "ok" => false, "message" => message, "audio" => nil }
    end

    def outcome(state, ok, message, data: {})
      {
        "schema_version" => "soul.application.v1",
        "request_id" => "speech-#{Process.pid}-#{Thread.current.object_id}",
        "timestamp" => Time.now.utc.iso8601,
        "lifecycle_state" => state,
        "mutation" => "none",
        "ok" => ok,
        "data" => data.merge("message" => message),
        "errors" => ok ? [] : [{ "code" => "voice_synthesis", "message" => message }]
      }
    end

    def python_path = File.join(@runtime_root, ".venv", "bin", "python")
    def model_dir = File.join(@runtime_root, "supertonic-3")
    def runner_path = File.join(@root, "scripts", "soul-voice-synthesis-runner.py")
    def expressive_python_path = File.join(@expressive_root, ".venv", "bin", "python")
    def expressive_model_dir = File.join(@expressive_root, "chatterbox-original")
    def expressive_runner_path = File.join(@root, "scripts", "soul-voice-expressive-runner.py")

    def load_manifest
      stat = File.lstat(@manifest_path)
      raise ArgumentError, "synthesis manifest must be a regular file" unless stat.file? && !stat.symlink?
      raise ArgumentError, "synthesis manifest is too large" unless stat.size.between?(1, 256 * 1024)
      value = JSON.parse(File.binread(@manifest_path, 256 * 1024))
      raise ArgumentError, "unsupported synthesis manifest" unless value["schema_version"] == "soul.voice_synthesis.models.v1"
      value
    rescue Errno::ENOENT
      raise ArgumentError, "synthesis manifest is missing"
    end

    def load_expressive_manifest
      stat = File.lstat(@expressive_manifest_path)
      raise ArgumentError, "expressive synthesis manifest must be a regular file" unless stat.file? && !stat.symlink?
      value = JSON.parse(File.binread(@expressive_manifest_path, 256 * 1024))
      raise ArgumentError, "unsupported expressive synthesis manifest" unless value["schema_version"] == "soul.voice_expressive.models.v1"
      value
    rescue Errno::ENOENT
      raise ArgumentError, "expressive synthesis manifest is missing"
    end
  end
end
