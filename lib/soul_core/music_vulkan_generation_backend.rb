# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module SoulCore
  class MusicVulkanGenerationBackend
    MAX_LM_SEED = (2**32) - 1
    MAX_ENRICHED_BYTES = 2 * 1024 * 1024
    SUPPORTED_SCHEMA = "soul.music_vulkan.models.v1"

    Result = Struct.new(:status, :stdout, :stderr, :exit_status, :wav_path, :lm_attempts, :code_health, keyword_init: true) do
      def success? = status == "ok"
    end

    def initialize(music_root:, manifest:, runner:)
      @music_root = File.expand_path(music_root)
      @manifest = manifest
      @runner = runner
      raise ArgumentError, "unsupported production Vulkan music manifest" unless @manifest["schema_version"] == SUPPORTED_SCHEMA
      @runtime = @manifest.fetch("runtime")
      @models = @manifest.fetch("models")
      @profile = @manifest.fetch("profile")
      @install_dir = File.join(@music_root, "acestep-cpp", @runtime.fetch("revision"))
      @models_dir = File.join(@install_dir, "models")
    end

    def environment_blockers
      items = []
      items << "pinned ACE-Step Vulkan runtime is missing" unless File.directory?(@install_dir) && !File.symlink?(@install_dir)
      %w[ace-lm ace-synth].each { |name| items << "ACE-Step Vulkan binary #{name} is missing" unless File.executable?(binary(name)) && !File.symlink?(binary(name)) }
      %w[ffmpeg ffprobe systemctl].each { |tool| items << "required tool #{tool} is missing" unless @runner.which(tool) }
      items
    end

    def verify_checkpoints!
      validate_source!
      @models.fetch("files").each do |item|
        path = File.join(@models_dir, item.fetch("filename"))
        valid = File.file?(path) && !File.symlink?(path) && File.size(path) == Integer(item.fetch("bytes")) &&
          Digest::SHA256.file(path).hexdigest == item.fetch("sha256")
        raise "missing or invalid Vulkan checkpoint #{item.fetch('filename')}" unless valid
      end
      true
    end

    def model_profile
      {
        "source_revision" => @runtime.fetch("revision"),
        "model_revision" => @models.fetch("revision"),
        "profile_id" => @profile.fetch("id"),
        "label" => @profile.fetch("label"),
        "accelerator" => @profile.fetch("accelerator"),
        "quantization" => "Q8_0",
        "vae_chunk" => Integer(@profile.fetch("vae_chunk")),
        "lm_attempt_limit" => Integer(@profile.fetch("max_lm_attempts")),
        "inference_steps" => Integer(@profile.fetch("inference_steps")),
        "offload" => false
      }
    end

    def run(input:, staging:, execute:)
      request = input.except("language").merge(
        "vocal_language" => input.fetch("lyrics") == "[Instrumental]" ? "unknown" : input.fetch("language"),
        "lm_model" => "acestep-5Hz-lm-4B-Q8_0.gguf",
        "synth_model" => "acestep-v15-turbo-Q8_0.gguf",
        "output_format" => "wav16",
        "batch_size" => 1,
        "inference_steps" => Integer(@profile.fetch("inference_steps"))
      )
      env = { "GGML_VK_VISIBLE_DEVICES" => "0", "LD_LIBRARY_PATH" => runtime_library_path }
      attempts = []
      output = +""
      seed = Integer(input.fetch("lm_seed", input.fetch("seed", -1))) & MAX_LM_SEED
      selected = nil
      health = nil
      last = nil

      Integer(@profile.fetch("max_lm_attempts")).times do |index|
        number = index + 1
        attempt = File.join(staging, "lm-attempt-#{number}")
        Dir.mkdir(attempt, 0o700)
        request_path = File.join(attempt, "request.json")
        File.write(request_path, JSON.pretty_generate(request.merge("lm_seed" => seed)) + "\n", mode: "wx", perm: 0o600)
        last = execute.call([binary("ace-lm"), "--models", @models_dir, "--request", request_path], 900, env, attempt)
        output << last.stdout.to_s << last.stderr.to_s
        return failed(last, output, attempts) unless last.success?

        enriched = File.join(attempt, "request0.json")
        raise "ACE-Step LM did not produce exactly one bounded enriched request" unless File.file?(enriched) && !File.symlink?(enriched) && File.size(enriched).between?(1, MAX_ENRICHED_BYTES)
        document = JSON.parse(File.binread(enriched, MAX_ENRICHED_BYTES))
        health = audio_code_health(document.fetch("audio_codes"), Integer(input.fetch("duration")))
        attempts << { "attempt" => number, "lm_seed" => seed, "code_health" => health }
        unless health.fetch("degenerate")
          selected = File.join(staging, "selected-request.json")
          FileUtils.cp(enriched, selected, preserve: false)
          File.chmod(0o600, selected)
          break
        end
        seed = next_lm_seed(seed, input, number)
      end

      unless selected
        return Result.new(status: "blocked", stdout: output, stderr: "three consecutive LM audio-code plans degenerated; synthesis was not started", exit_status: nil, lm_attempts: attempts, code_health: health)
      end

      last = execute.call([binary("ace-synth"), "--models", @models_dir, "--vae-chunk", Integer(@profile.fetch("vae_chunk")).to_s, "--request", selected], Integer(input.fetch("duration")) + 900, env, staging)
      output << last.stdout.to_s << last.stderr.to_s
      return failed(last, output, attempts, health) unless last.success?
      wavs = Dir.glob(File.join(staging, "*.wav")).select { |path| File.file?(path) && !File.symlink?(path) && File.size(path).positive? }
      raise "ACE-Step Vulkan generation did not produce exactly one WAV" unless wavs.one?
      Result.new(status: "ok", stdout: output, stderr: "", exit_status: last.exit_status, wav_path: wavs.first, lm_attempts: attempts, code_health: health)
    rescue StandardError => error
      Result.new(status: "failed", stdout: output.to_s, stderr: error.message, exit_status: nil, lm_attempts: attempts || [], code_health: health)
    end

    private

    def failed(result, output, attempts, health = nil)
      Result.new(status: result.status, stdout: output, stderr: result.stderr.to_s, exit_status: result.exit_status, lm_attempts: attempts, code_health: health)
    end

    def binary(name) = File.join(@install_dir, "build", name)

    def runtime_library_path
      existing = ENV.fetch("LD_LIBRARY_PATH", "").split(File::PATH_SEPARATOR).reject(&:empty?)
      ([File.join(@install_dir, "build")] + existing).uniq.join(File::PATH_SEPARATOR)
    end

    def validate_source!
      revision = @runner.run("git", "rev-parse", "HEAD", timeout_seconds: 20, max_output_bytes: 1024, chdir: @install_dir)
      raise "ACE-Step Vulkan runtime revision does not match the production manifest" unless revision.success? && revision.stdout.to_s.strip == @runtime.fetch("revision")
    end

    def audio_code_health(value, duration)
      codes = value.to_s.split(",").map { |item| Integer(item, 10) }
      raise "LM audio-code plan is empty" if codes.empty?
      raise "LM audio-code plan contains an out-of-range token" unless codes.all? { |code| code.between?(0, 65_535) }
      unique = codes.uniq.length.fdiv(codes.length)
      adjacent = codes.each_cons(2).count { |left, right| left == right }.fdiv([codes.length - 1, 1].max)
      dominant = codes.tally.values.max.fdiv(codes.length)
      expected = (duration * 5.0).round
      delta = (codes.length - expected).abs.fdiv([expected, 1].max)
      {
        "degenerate" => (unique < 0.25 && adjacent > 0.50) || dominant > 0.60 || delta > 0.05,
        "code_count" => codes.length, "expected_code_count" => expected,
        "unique_ratio" => unique.round(4), "adjacent_repeat_ratio" => adjacent.round(4),
        "dominant_code_ratio" => dominant.round(4), "count_delta_ratio" => delta.round(4),
        "policy" => { "minimum_unique_ratio_when_high_repetition" => 0.25, "maximum_adjacent_repeat_ratio" => 0.50,
          "maximum_dominant_code_ratio" => 0.60, "maximum_count_delta_ratio" => 0.05 }
      }
    rescue ArgumentError
      raise "LM audio-code plan is malformed"
    end

    def next_lm_seed(current, input, attempt)
      digest = Digest::SHA256.hexdigest(JSON.generate(input))
      candidate = Digest::SHA256.hexdigest("#{current}:#{digest}:retry:#{attempt}")[0, 8].to_i(16)
      candidate == current ? ((candidate + 1) & MAX_LM_SEED) : candidate
    end
  end
end
