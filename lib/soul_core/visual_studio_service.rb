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
    EDIT_CONFIRMATION = "GENERATE_VISUAL_EDIT"
    DELETE_CANDIDATE_CONFIRMATION = "DELETE_VISUAL_CANDIDATE"
    DELETE_PROJECT_CONFIRMATION = "DELETE_VISUAL_PROJECT"
    PROMOTION_CONFIRMATION = "BIND_VISUAL_COMPANION"
    MAX_PROJECTS = 500
    MAX_RECORD_BYTES = 128 * 1024
    TIMEOUT_SECONDS = 900

    def initialize(root: Dir.pwd, visual_root: nil, runtime_root: nil, manifest_path: nil, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) }, core_status: nil, music_visual_companion: nil)
      @root = File.expand_path(root)
      @visual_root = File.expand_path(visual_root || File.join(@root, "Soul", "visual", "projects"))
      @runtime_root = File.expand_path(runtime_root || File.join(Dir.home, ".local", "share", "soul", "visual"))
      @manifest_path = File.expand_path(manifest_path || File.join(@root, "config", "visual_studio_models.json"))
      @runner = runner
      @clock = clock
      @id_generator = id_generator
      @core_status = core_status
      @music_visual_companion = music_visual_companion
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

    def update(project_id:, attributes:)
      current = read_project(project_id)
      data = stringify_keys(attributes)
      raise ArgumentError, "visual project fields are invalid" unless data.keys.sort == CREATE_FIELDS.sort
      validate_project_inputs!(data)
      revisions = File.join(project_dir(project_id), "revisions")
      FileUtils.mkdir_p(revisions, mode: 0o700)
      old_digest = digest(current)
      archive = File.join(revisions, "#{current.fetch('updated_at').gsub(/[^0-9]/, '')}-#{old_digest[0, 12]}.json")
      write_json(archive, current) unless File.exist?(archive)
      revised = current.merge(data).merge("seed" => Integer(data.fetch("seed")), "updated_at" => @clock.call.iso8601, "revision_parent_digest" => old_digest)
      replace_json(File.join(project_dir(project_id), "project.json"), revised)
      outcome("complete", true, "visual brief revised; existing candidates remain immutable", data: { "project" => project_with_candidates(revised) }, mutation: "visual_project_revised")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    end

    def record_review(project_id:, candidate_id:, review:)
      candidate = read_candidate(project_id, candidate_id)
      data = stringify_keys(review)
      raise ArgumentError, "visual review fields are invalid" unless data.keys.sort == %w[disposition notes rating].sort
      rating = Integer(data.fetch("rating"))
      raise ArgumentError, "rating must be 1..5" unless (1..5).cover?(rating)
      raise ArgumentError, "visual disposition must be keep or revise" unless %w[keep revise].include?(data.fetch("disposition"))
      notes = data.fetch("notes")
      raise ArgumentError, "review notes must be valid text under 8000 characters" unless notes.is_a?(String) && notes.valid_encoding? && notes.length <= 8_000
      record = data.merge("schema_version" => "soul.visual.review.v1", "project_id" => project_id, "candidate_id" => candidate.fetch("candidate_id"), "rating" => rating, "reviewed_at" => @clock.call.iso8601)
      path = File.join(candidate_dir(project_id, candidate_id), "review.json")
      if File.exist?(path)
        history = File.join(candidate_dir(project_id, candidate_id), "review-history")
        FileUtils.mkdir_p(history, mode: 0o700)
        previous = File.binread(path, MAX_RECORD_BYTES)
        FileUtils.mv(path, File.join(history, "#{Digest::SHA256.hexdigest(previous)[0, 16]}.json"))
      end
      write_json(path, record)
      outcome("complete", true, "visual review recorded", data: { "review" => record }, mutation: "visual_review_recorded")
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
      render_candidate(project: project, candidate_id: candidate_id, scope: scope, resource: resource, prompt: project.fetch("prompt"), seed: project.fetch("seed"), source_path: nil, kind: "text_to_image", progress: progress)
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    def edit_preview(project_id:, source_candidate_id:, instruction:, seed:)
      project = read_project(project_id)
      source = read_candidate(project_id, source_candidate_id)
      edit_instruction = validate_edit_instruction!(instruction)
      edit_seed = validate_seed!(seed)
      resource = resources.fetch("data")
      return outcome("blocked_for_human_review", false, "Visual runtime or exact model files are not ready", data: resource) unless resource["ready"]
      candidate_id = "visual_candidate_#{@id_generator.call}"
      scope = edit_scope(project, source, candidate_id, edit_instruction, edit_seed, resource.fetch("profile_id"))
      outcome("blocked_for_human_review", true, "exact image-guided edit requires approval", data: scope.merge("expected_digest" => digest(scope), "confirmation_phrase" => EDIT_CONFIRMATION))
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def edit_execute(project_id:, source_candidate_id:, candidate_id:, instruction:, seed:, confirmation:, expected_digest:, progress: nil)
      project = read_project(project_id)
      source = read_candidate(project_id, source_candidate_id)
      raise ArgumentError, "candidate_id is invalid" unless candidate_id.to_s.match?(CANDIDATE_ID)
      edit_instruction = validate_edit_instruction!(instruction)
      edit_seed = validate_seed!(seed)
      resource = resources.fetch("data")
      scope = edit_scope(project, source, candidate_id, edit_instruction, edit_seed, resource.fetch("profile_id"))
      raise "exact visual edit approval did not match" unless confirmation == EDIT_CONFIRMATION && secure_compare(expected_digest, digest(scope))
      raise "Visual runtime or exact model files are not ready" unless resource["ready"]
      render_candidate(project: project, candidate_id: candidate_id, scope: scope, resource: resource, prompt: edit_instruction, seed: edit_seed, source_path: artifact_path(project_id: project_id, candidate_id: source_candidate_id), kind: "image_edit", progress: progress)
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    end

    def candidate_delete_preview(project_id:, candidate_id:)
      candidate = read_candidate(project_id, candidate_id)
      path = candidate_dir(project_id, candidate_id)
      scope = { "operation" => "delete_visual_candidate", "project_id" => project_id, "candidate_id" => candidate_id, "candidate_digest" => digest(candidate), "archive_digest" => directory_digest(path), "bytes" => directory_bytes(path) }
      outcome("blocked_for_human_review", true, "exact visual candidate deletion requires approval", data: scope.merge("expected_digest" => digest(scope), "confirmation_phrase" => DELETE_CANDIDATE_CONFIRMATION))
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    end

    def candidate_delete_execute(project_id:, candidate_id:, confirmation:, expected_digest:)
      preview = candidate_delete_preview(project_id: project_id, candidate_id: candidate_id)
      scope = preview.fetch("data").reject { |key, _| %w[expected_digest confirmation_phrase].include?(key) }
      raise "exact visual candidate deletion did not match" unless confirmation == DELETE_CANDIDATE_CONFIRMATION && secure_compare(expected_digest, digest(scope))
      path = candidate_dir(project_id, candidate_id)
      FileUtils.rm_rf(path)
      outcome("complete", true, "visual candidate permanently deleted", data: scope, mutation: "visual_candidate_deleted")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def project_delete_preview(project_id:)
      project = read_project(project_id)
      path = project_dir(project_id)
      scope = { "operation" => "delete_visual_project", "project_id" => project_id, "project_digest" => digest(project), "archive_digest" => directory_digest(path), "candidate_count" => project_with_candidates(project).fetch("candidates").length, "bytes" => directory_bytes(path) }
      outcome("blocked_for_human_review", true, "exact visual project deletion requires approval", data: scope.merge("expected_digest" => digest(scope), "confirmation_phrase" => DELETE_PROJECT_CONFIRMATION))
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    end

    def project_delete_execute(project_id:, confirmation:, expected_digest:)
      preview = project_delete_preview(project_id: project_id)
      scope = preview.fetch("data").reject { |key, _| %w[expected_digest confirmation_phrase].include?(key) }
      raise "exact visual project deletion did not match" unless confirmation == DELETE_PROJECT_CONFIRMATION && secure_compare(expected_digest, digest(scope))
      path = project_dir(project_id)
      FileUtils.rm_rf(path)
      outcome("complete", true, "visual project permanently deleted", data: scope, mutation: "visual_project_deleted")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def promotion_preview(project_id:, candidate_id:, music_project_id:, music_candidate_id:)
      companion = require_music_companion!
      project = read_project(project_id)
      read_candidate(project_id, candidate_id)
      companion.generated_import_preview(project_id: music_project_id, candidate_id: music_candidate_id, source_project_id: project_id, source_candidate_id: candidate_id, source_path: artifact_path(project_id: project_id, candidate_id: candidate_id), prompt_summary: project.fetch("prompt"))
    end

    def promotion_execute(project_id:, candidate_id:, music_project_id:, music_candidate_id:, confirmation:, expected_digest:)
      companion = require_music_companion!
      project = read_project(project_id)
      read_candidate(project_id, candidate_id)
      companion.generated_import_execute(project_id: music_project_id, candidate_id: music_candidate_id, source_project_id: project_id, source_candidate_id: candidate_id, source_path: artifact_path(project_id: project_id, candidate_id: candidate_id), prompt_summary: project.fetch("prompt"), confirmation: confirmation, expected_digest: expected_digest)
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

    def command(project, output, prompt:, seed:, source_path: nil)
      profile = read_manifest.fetch("profiles").values.first
      files = profile.fetch("files").to_h { |file| [file.fetch("role"), model_path(file)] }
      width, height = dimensions(project)
      command = [runtime_binary, "--diffusion-model", files.fetch("diffusion_model"), "--vae", files.fetch("vae"), "--llm", files.fetch("text_encoder"), "-p", prompt, "-n", project.fetch("negative_prompt"), "--cfg-scale", profile.fetch("cfg_scale").to_s, "--steps", profile.fetch("steps").to_s, "--seed", seed.to_s, "-W", width.to_s, "-H", height.to_s, "--offload-to-cpu", "--diffusion-fa"]
      command.concat(["-r", source_path]) if source_path
      command.concat(["-o", output])
    end

    def render_candidate(project:, candidate_id:, scope:, resource:, prompt:, seed:, source_path:, kind:, progress:)
      target = candidate_dir(project.fetch("project_id"), candidate_id)
      raise "visual candidate already exists" if File.exist?(target) || File.symlink?(target)
      staging = "#{target}.partial-#{SecureRandom.hex(4)}"
      Dir.mkdir(staging, 0o700)
      output = File.join(staging, "image.png")
      input = project.slice(*CREATE_FIELDS).merge(
        "profile_id" => resource.fetch("profile_id"), "generation_kind" => kind,
        "effective_prompt" => prompt, "effective_seed" => seed
      )
      if source_path
        input["source_candidate_id"] = scope.fetch("source_candidate_id")
        input["source_image_sha256"] = scope.fetch("source_image_sha256")
      end
      write_json(File.join(staging, "input.json"), input)
      progress&.call("stage" => "rendering", "message" => kind == "image_edit" ? "FLUX.2 Klein is shaping an image-guided revision." : "FLUX.2 Klein is shaping one local still.")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = @runner.run(command(project, output, prompt: prompt, seed: seed, source_path: source_path), timeout_seconds: TIMEOUT_SECONDS, env: { "VK_LOADER_DEBUG" => "none" }, max_output_bytes: 512 * 1024)
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
      File.write(File.join(staging, "generation.log"), (result.stdout.to_s + result.stderr.to_s).byteslice(0, 512 * 1024), mode: "wb", perm: 0o600)
      raise "visual renderer failed safely" unless result.success? && valid_png?(output)
      receipt = scope.merge(
        "schema_version" => "soul.visual.candidate.v1", "generation_kind" => kind,
        "lifecycle_state" => "blocked_for_human_review", "created_at" => @clock.call.iso8601,
        "elapsed_seconds" => elapsed, "image_sha256" => Digest::SHA256.file(output).hexdigest,
        "human_review_required" => true
      )
      write_json(File.join(staging, "candidate.json"), receipt)
      File.rename(staging, target)
      progress&.call("stage" => "complete", "message" => "Visual draft awaits your review.")
      outcome("blocked_for_human_review", true, "visual draft generated; human review required", data: { "candidate" => receipt }, mutation: "visual_candidate_generated")
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    def read_project(id)
      raise ArgumentError, "project_id is invalid" unless id.to_s.match?(PROJECT_ID)
      path = File.join(project_dir(id), "project.json")
      raise ArgumentError, "visual project does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
      JSON.parse(File.binread(path, MAX_RECORD_BYTES))
    end

    def read_candidate(project_id, candidate_id)
      read_project(project_id)
      raise ArgumentError, "candidate_id is invalid" unless candidate_id.to_s.match?(CANDIDATE_ID)
      path = File.join(candidate_dir(project_id, candidate_id), "candidate.json")
      raise ArgumentError, "visual candidate does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      raise ArgumentError, "visual candidate identity does not match" unless record["project_id"] == project_id && record["candidate_id"] == candidate_id
      record
    rescue JSON::ParserError
      raise ArgumentError, "visual candidate record is invalid"
    end

    def project_with_candidates(project)
      root = File.join(project_dir(project.fetch("project_id")), "generations")
      candidates = safe_children(root).grep(CANDIDATE_ID).filter_map do |id|
        path = File.join(root, id, "candidate.json")
        if File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
          candidate = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
          review_path = File.join(root, id, "review.json")
          candidate["review"] = JSON.parse(File.binread(review_path, MAX_RECORD_BYTES)) if File.file?(review_path) && !File.symlink?(review_path) && File.size(review_path) <= MAX_RECORD_BYTES
          candidate
        end
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
    def candidate_dir(project_id, candidate_id) = File.join(project_dir(project_id), "generations", candidate_id.to_s)
    def safe_children(path) = File.directory?(path) && !File.symlink?(path) ? Dir.children(path) : []

    def edit_scope(project, source, candidate_id, instruction, seed, profile_id)
      source_path = artifact_path(project_id: project.fetch("project_id"), candidate_id: source.fetch("candidate_id"))
      {
        "operation" => "visual_image_edit", "project_id" => project.fetch("project_id"),
        "source_candidate_id" => source.fetch("candidate_id"), "source_image_sha256" => Digest::SHA256.file(source_path).hexdigest,
        "candidate_id" => candidate_id, "project_digest" => digest(project), "instruction" => instruction,
        "seed" => seed, "profile_id" => profile_id, "width" => dimensions(project).first, "height" => dimensions(project).last
      }
    end

    def validate_edit_instruction!(value)
      instruction = value.to_s.strip
      raise ArgumentError, "edit instruction is required and must be at most 8000 characters" unless instruction.length.between?(1, 8_000)
      instruction
    end

    def validate_seed!(value)
      seed = Integer(value)
      raise ArgumentError, "seed must be 0..2147483647" unless (0..2_147_483_647).cover?(seed)
      seed
    rescue TypeError, ArgumentError
      raise ArgumentError, "seed must be an integer from 0..2147483647"
    end

    def directory_bytes(path)
      raise ArgumentError, "visual archive target is invalid" unless File.directory?(path) && !File.symlink?(path) && within?(File.expand_path(path), @visual_root)
      Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).sum { |entry| File.file?(entry) && !File.symlink?(entry) ? File.size(entry) : 0 }
    end

    def directory_digest(path)
      raise ArgumentError, "visual archive target is invalid" unless File.directory?(path) && !File.symlink?(path) && within?(File.expand_path(path), @visual_root)
      entries = Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).select { |entry| File.file?(entry) && !File.symlink?(entry) }.sort.map do |entry|
        [entry.delete_prefix(path + File::SEPARATOR), File.size(entry), Digest::SHA256.file(entry).hexdigest]
      end
      digest(entries)
    end

    def require_music_companion!
      raise ArgumentError, "Music visual companion integration is unavailable" unless @music_visual_companion
      @music_visual_companion
    end

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

    def replace_json(path, value)
      temporary = "#{path}.tmp-#{SecureRandom.hex(4)}"
      File.write(temporary, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.exist?(temporary)
    end

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
