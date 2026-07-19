# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "bounded_command_runner"

module SoulCore
  class VisualStudioService
    PROJECT_ID = /\Avisual_project_[a-f0-9]{16}\z/
    CANDIDATE_ID = /\Avisual_candidate_[a-f0-9]{16}\z/
    CREATE_FIELDS = %w[title intent prompt negative_prompt aspect_ratio seed].freeze
    ASPECTS = { "landscape" => [1024, 576], "square" => [768, 768], "portrait" => [576, 1024] }.freeze
    CONFIRMATION = "GENERATE_VISUAL_DRAFT"
    MAX_PROJECTS = 500
    MAX_RECORD_BYTES = 128 * 1024
    TIMEOUT_SECONDS = 900

    def initialize(root: Dir.pwd, visual_root: nil, runtime_root: nil, manifest_path: nil, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) }, core_status: nil)
      @root = File.expand_path(root)
      @visual_root = File.expand_path(visual_root || File.join(@root, "Soul", "visual", "projects"))
      @runtime_root = File.expand_path(runtime_root || File.join(Dir.home, ".local", "share", "soul", "visual"))
      @manifest_path = File.expand_path(manifest_path || File.join(@root, "config", "visual_studio_models.json"))
      @runner = runner
      @clock = clock
      @id_generator = id_generator
      @core_status = core_status
      raise ArgumentError, "visual project root must remain inside the repository" unless within?(@visual_root, @root)
    end

    def resources
      manifest = read_manifest
      profile_id, profile = manifest.fetch("profiles").first
      binary = runtime_binary
      missing = profile.fetch("files").reject { |file| verified_file?(model_path(file), file) }
      core = visual_core_status
      ready = executable?(binary) && missing.empty? && core.fetch("allowed")
      outcome("complete", true, "visual resources inspected", data: {
        "profile_id" => profile_id, "profile" => profile.fetch("label"), "accelerator" => profile.fetch("accelerator"),
        "runtime_ready" => executable?(binary), "models_ready" => missing.empty?, "ready" => ready,
        "missing_roles" => missing.map { |file| file.fetch("role") }, "core" => core, "motion" => manifest.fetch("motion_candidates")
      })
    rescue KeyError, JSON::ParserError, SystemCallError => error
      outcome("failed", false, "visual resource manifest failed safely: #{error.class}")
    end

    def list(limit: 100)
      prepare_root!
      records = safe_children(@visual_root).grep(PROJECT_ID).filter_map { |id| read_project(id) rescue nil }
      outcome("complete", true, "visual projects listed", data: { "projects" => records.sort_by { |item| item.fetch("created_at") }.reverse.first([[Integer(limit), 1].max, 200].min) })
    end

    def create(attributes)
      data = stringify_keys(attributes)
      raise ArgumentError, "visual project fields are invalid" unless data.keys.sort == CREATE_FIELDS.sort
      validate_project_inputs!(data)
      prepare_root!
      raise "visual project limit exceeded" if safe_children(@visual_root).grep(PROJECT_ID).length >= MAX_PROJECTS
      project_id = "visual_project_#{@id_generator.call}"
      raise "generated visual project ID is invalid" unless project_id.match?(PROJECT_ID)
      directory = project_dir(project_id)
      raise "visual project ID collision" if File.exist?(directory) || File.symlink?(directory)
      Dir.mkdir(directory, 0o700)
      Dir.mkdir(File.join(directory, "generations"), 0o700)
      now = @clock.call.iso8601
      record = data.merge("schema_version" => "soul.visual.project.v1", "project_id" => project_id, "seed" => Integer(data.fetch("seed")), "created_at" => now, "updated_at" => now)
      write_json(File.join(directory, "project.json"), record)
      outcome("complete", true, "visual project created", data: { "project" => project_with_candidates(record) }, mutation: "visual_project_created")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    end

    def inspect(project_id:)
      project = read_project(project_id)
      outcome("complete", true, "visual project inspected", data: { "project" => project_with_candidates(project) })
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    end

    def generation_preview(project_id:)
      project = read_project(project_id)
      resource = resources.dig("data") || {}
      return outcome("blocked_for_human_review", false, "Visual runtime or exact model files are not ready", data: resource) unless resource["ready"]
      candidate_id = "visual_candidate_#{@id_generator.call}"
      scope = { "operation" => "visual_generation", "project_id" => project.fetch("project_id"), "candidate_id" => candidate_id, "project_digest" => digest(project), "profile_id" => resource.fetch("profile_id"), "width" => dimensions(project).first, "height" => dimensions(project).last }
      outcome("blocked_for_human_review", true, "exact local visual generation requires approval", data: scope.merge("expected_digest" => digest(scope), "confirmation_phrase" => CONFIRMATION))
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def generation_execute(project_id:, candidate_id:, confirmation:, expected_digest:, progress: nil)
      project = read_project(project_id)
      raise ArgumentError, "candidate_id is invalid" unless candidate_id.to_s.match?(CANDIDATE_ID)
      resource = resources.fetch("data")
      scope = { "operation" => "visual_generation", "project_id" => project.fetch("project_id"), "candidate_id" => candidate_id, "project_digest" => digest(project), "profile_id" => resource.fetch("profile_id"), "width" => dimensions(project).first, "height" => dimensions(project).last }
      raise "exact visual approval did not match" unless confirmation == CONFIRMATION && secure_compare(expected_digest, digest(scope))
      raise "Visual runtime or exact model files are not ready" unless resource["ready"]
      target = File.join(project_dir(project_id), "generations", candidate_id)
      raise "visual candidate already exists" if File.exist?(target) || File.symlink?(target)
      staging = "#{target}.partial-#{SecureRandom.hex(4)}"
      Dir.mkdir(staging, 0o700)
      output = File.join(staging, "image.png")
      input = project.slice(*CREATE_FIELDS).merge("profile_id" => resource.fetch("profile_id"))
      write_json(File.join(staging, "input.json"), input)
      progress&.call("stage" => "rendering", "message" => "FLUX.2 Klein is shaping one local still.")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = @runner.run(command(project, output), timeout_seconds: TIMEOUT_SECONDS, env: { "VK_LOADER_DEBUG" => "none" }, max_output_bytes: 512 * 1024)
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
      File.write(File.join(staging, "generation.log"), (result.stdout.to_s + result.stderr.to_s).byteslice(0, 512 * 1024), mode: "wb", perm: 0o600)
      raise "visual renderer failed safely" unless result.success? && valid_png?(output)
      receipt = scope.merge("schema_version" => "soul.visual.candidate.v1", "lifecycle_state" => "blocked_for_human_review", "created_at" => @clock.call.iso8601, "elapsed_seconds" => elapsed, "image_sha256" => Digest::SHA256.file(output).hexdigest, "human_review_required" => true)
      write_json(File.join(staging, "candidate.json"), receipt)
      File.rename(staging, target)
      progress&.call("stage" => "complete", "message" => "Visual draft awaits your review.")
      outcome("blocked_for_human_review", true, "visual draft generated; human review required", data: { "candidate" => receipt }, mutation: "visual_candidate_generated")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    def artifact_path(project_id:, candidate_id:)
      read_project(project_id)
      raise ArgumentError, "candidate_id is invalid" unless candidate_id.to_s.match?(CANDIDATE_ID)
      path = File.join(project_dir(project_id), "generations", candidate_id, "image.png")
      raise ArgumentError, "visual artifact does not exist" unless File.file?(path) && !File.symlink?(path) && valid_png?(path)
      path
    end

    private

    def runtime_binary = File.join(@runtime_root, "stable-diffusion.cpp", "bin", "sd-cli")
    def models_dir = File.join(@runtime_root, "models")
    def model_path(file) = File.join(models_dir, file.fetch("filename"))
    def executable?(path) = File.file?(path) && !File.symlink?(path) && File.executable?(path)
    def read_manifest = JSON.parse(File.binread(@manifest_path, MAX_RECORD_BYTES))
    def dimensions(project) = ASPECTS.fetch(project.fetch("aspect_ratio"))

    def visual_core_status
      return { "allowed" => true, "core_id" => "unmanaged", "reason" => "standalone bounded invocation" } unless @core_status
      envelope = @core_status.call
      data = envelope.fetch("data", {})
      core_id = data["active_core_id"] || data["selected_core_id"]
      allowed = %w[amd-free music].include?(core_id) && data["active_profile_id"] != "amd-gemma"
      { "allowed" => allowed, "core_id" => core_id, "reason" => allowed ? "AMD is assigned to foreground creative work" : "Activate AMD-Free Core or Music Core before visual generation" }
    rescue StandardError
      { "allowed" => false, "core_id" => "unknown", "reason" => "Core state could not be verified safely" }
    end

    def command(project, output)
      profile = read_manifest.fetch("profiles").values.first
      files = profile.fetch("files").to_h { |file| [file.fetch("role"), model_path(file)] }
      width, height = dimensions(project)
      [runtime_binary, "--diffusion-model", files.fetch("diffusion_model"), "--vae", files.fetch("vae"), "--llm", files.fetch("text_encoder"), "-p", project.fetch("prompt"), "-n", project.fetch("negative_prompt"), "--cfg-scale", profile.fetch("cfg_scale").to_s, "--steps", profile.fetch("steps").to_s, "--seed", project.fetch("seed").to_s, "-W", width.to_s, "-H", height.to_s, "--offload-to-cpu", "--diffusion-fa", "-o", output]
    end

    def read_project(id)
      raise ArgumentError, "project_id is invalid" unless id.to_s.match?(PROJECT_ID)
      path = File.join(project_dir(id), "project.json")
      raise ArgumentError, "visual project does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
      JSON.parse(File.binread(path, MAX_RECORD_BYTES))
    end

    def project_with_candidates(project)
      root = File.join(project_dir(project.fetch("project_id")), "generations")
      candidates = safe_children(root).grep(CANDIDATE_ID).filter_map do |id|
        path = File.join(root, id, "candidate.json")
        JSON.parse(File.binread(path, MAX_RECORD_BYTES)) if File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
      rescue JSON::ParserError
        nil
      end.sort_by { |item| item.fetch("created_at") }.reverse
      project.merge("candidates" => candidates)
    end

    def prepare_root!
      FileUtils.mkdir_p(@visual_root, mode: 0o700)
      raise "visual root must not be a symlink" if File.symlink?(@visual_root)
      File.chmod(0o700, @visual_root)
    end
    def project_dir(id) = File.join(@visual_root, id.to_s)
    def safe_children(path) = File.directory?(path) && !File.symlink?(path) ? Dir.children(path) : []

    def validate_project_inputs!(data)
      %w[title intent prompt negative_prompt aspect_ratio].each { |key| raise ArgumentError, "#{key} must be valid text" unless data[key].is_a?(String) && data[key].valid_encoding? }
      raise ArgumentError, "title is required and must be at most 120 characters" unless data["title"].strip.length.between?(1, 120)
      raise ArgumentError, "intent is required and must be at most 2000 characters" unless data["intent"].strip.length.between?(1, 2_000)
      raise ArgumentError, "prompt is required and must be at most 8000 characters" unless data["prompt"].strip.length.between?(1, 8_000)
      raise ArgumentError, "negative_prompt exceeds 2000 characters" if data["negative_prompt"].length > 2_000
      raise ArgumentError, "aspect_ratio is invalid" unless ASPECTS.key?(data["aspect_ratio"])
      seed = Integer(data["seed"])
      raise ArgumentError, "seed must be 0..2147483647" unless (0..2_147_483_647).cover?(seed)
    rescue TypeError
      raise ArgumentError, "seed must be an integer"
    end

    def verified_file?(path, record)
      File.file?(path) && !File.symlink?(path) && File.size(path) == record.fetch("bytes") && Digest::SHA256.file(path).hexdigest == record.fetch("sha256")
    rescue SystemCallError
      false
    end
    def valid_png?(path) = File.file?(path) && !File.symlink?(path) && File.size(path) > 1024 && File.binread(path, 8) == "\x89PNG\r\n\x1a\n".b
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.bytesize && left.to_s.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    def within?(path, root) = path == root || path.start_with?(root + File::SEPARATOR)
    def stringify_keys(value) = value.to_h.each_with_object({}) { |(key, child), memo| memo[key.to_s] = child }

    def write_json(path, value)
      temporary = "#{path}.tmp-#{SecureRandom.hex(4)}"
      File.write(temporary, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.exist?(temporary)
    end

    def outcome(state, ok, message, data: {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => state, "message" => message, "data" => data, "mutation" => mutation }
    end
  end
end
