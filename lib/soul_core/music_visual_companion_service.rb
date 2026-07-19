# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "bounded_command_runner"
require_relative "music_project_store"

module SoulCore
  class MusicVisualCompanionService
    IMPORT_CONFIRMATION = "BIND_VISUAL_COMPANION"
    LOOP_CONFIRMATION = "RENDER_VISUAL_LOOP"
    FINAL_CONFIRMATION = "RENDER_VISUAL_COMPANION"
    VISUAL_ID = /\Avisual_[a-f0-9]{16}\z/
    SOURCE_ID = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    LOOP_SECONDS = 12
    WIDTH = 1280
    HEIGHT = 720
    FPS = 30
    COMMAND_TIMEOUT = 600
    MAX_RECORD_BYTES = 128 * 1024

    def initialize(root: Dir.pwd, project_store: nil, runner: BoundedCommandRunner.new, source_root: File.join("assets", "music_visuals"), clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @store = project_store || MusicProjectStore.new(root: @root)
      @runner = runner
      @source_root = File.expand_path(source_root, @root)
      @clock = clock
      @ffmpeg = @runner.which("ffmpeg")
      @ffprobe = @runner.which("ffprobe")
      raise MusicProjectStore::ValidationError, "visual source root must remain inside the repository" unless within?(@source_root, @root)
    end

    def available_sources(project_id:, candidate_id:)
      validate_binding!(project_id, candidate_id)
      return [] unless File.directory?(@source_root) && !File.symlink?(@source_root)

      Dir.children(@source_root).grep(/\.json\z/).sort.filter_map do |name|
        source = read_source(File.basename(name, ".json"))
        source.slice("asset_id", "label", "provider", "rights_status", "prompt_summary") if source["project_id"] == project_id && source["candidate_id"] == candidate_id
      rescue MusicProjectStore::ValidationError, MusicProjectStore::IntegrityError
        nil
      end
    end

    def inventory(project_id:, candidate_id:)
      validate_binding!(project_id, candidate_id)
      root = visuals_root(project_id, create: false)
      return [] unless root
      Dir.children(root).grep(VISUAL_ID).sort.filter_map do |visual_id|
        record = read_visual(project_id, candidate_id, visual_id)
        record if record["candidate_id"] == candidate_id
      rescue MusicProjectStore::ValidationError, MusicProjectStore::IntegrityError
        nil
      end.sort_by { |record| record.fetch("created_at") }.reverse
    end

    def import_preview(project_id:, candidate_id:, asset_id:)
      scope = import_scope(project_id, candidate_id, asset_id)
      existing = existing_visual(scope)
      return outcome("complete", true, "this visual companion is already bound", data: { "visual" => existing, "idempotent_replay" => true }) if existing
      outcome("blocked_for_human_review", true, "exact visual source confirmation required", data: gate(IMPORT_CONFIRMATION, scope))
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def import_execute(project_id:, candidate_id:, asset_id:, confirmation:, expected_digest:)
      return missing_gate unless confirmation.to_s.length.positive? && expected_digest.to_s.length.positive?
      scope = import_scope(project_id, candidate_id, asset_id)
      return gate_mismatch("exact visual source confirmation did not match") unless confirmation == IMPORT_CONFIRMATION
      return gate_mismatch("visual source changed; preview again") unless secure_compare(expected_digest, digest(scope))
      existing = existing_visual(scope)
      return outcome("complete", true, "this visual companion is already bound", data: { "visual" => existing, "idempotent_replay" => true }) if existing

      visual_id = scope.fetch("visual_id")
      root = visuals_root(project_id, create: true)
      target = File.join(root, visual_id)
      raise MusicProjectStore::IntegrityError, "visual destination already exists" if File.exist?(target) || File.symlink?(target)
      staging = File.join(root, ".#{visual_id}.partial-#{SecureRandom.hex(4)}")
      Dir.mkdir(staging, 0o700)
      source = source_image(read_source(asset_id))
      FileUtils.cp(source, File.join(staging, "base.png"), preserve: false)
      File.chmod(0o600, File.join(staging, "base.png"))
      record = scope.merge(
        "schema_version" => "soul.music.visual.v1", "lifecycle_state" => "blocked_for_human_review",
        "stage" => "base_bound", "created_at" => @clock.call.iso8601, "updated_at" => @clock.call.iso8601,
        "render_profile" => render_profile, "artifacts" => { "base" => artifact("base.png", staging) },
        "human_review_required" => true
      )
      write_json(File.join(staging, "visual.json"), record)
      File.rename(staging, target)
      outcome("blocked_for_human_review", true, "visual source bound; loop review required", data: { "visual" => record }, mutation: "music_visual_bound")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    def loop_preview(project_id:, candidate_id:, visual_id:)
      record = read_visual(project_id, candidate_id, visual_id)
      return outcome("complete", true, "visual loop already exists", data: { "visual" => record, "idempotent_replay" => true }) if record.dig("artifacts", "loop")
      scope = loop_scope(record)
      outcome("blocked_for_human_review", true, "exact visual loop render confirmation required", data: gate(LOOP_CONFIRMATION, scope))
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def loop_execute(project_id:, candidate_id:, visual_id:, confirmation:, expected_digest:, progress: nil)
      return missing_gate unless confirmation.to_s.length.positive? && expected_digest.to_s.length.positive?
      record = read_visual(project_id, candidate_id, visual_id)
      return outcome("complete", true, "visual loop already exists", data: { "visual" => record, "idempotent_replay" => true }) if record.dig("artifacts", "loop")
      scope = loop_scope(record)
      return gate_mismatch("exact visual loop confirmation did not match") unless confirmation == LOOP_CONFIRMATION
      return gate_mismatch("visual loop scope changed; preview again") unless secure_compare(expected_digest, digest(scope))
      progress&.call({ "stage" => "visual_loop", "message" => "Rendering bounded localized water motion with a locked camera" })
      directory = visual_path(project_id, visual_id)
      output = File.join(directory, ".loop.partial.mp4")
      render_loop(File.join(directory, "base.png"), output)
      File.rename(output, File.join(directory, "loop.mp4"))
      record["artifacts"]["loop"] = artifact("loop.mp4", directory).merge("duration_seconds" => LOOP_SECONDS, "width" => WIDTH, "height" => HEIGHT, "fps" => FPS, "motion_profile" => "localized_water_locked_camera", "frame_change_expected" => true)
      record["stage"] = "loop_ready"
      record["updated_at"] = @clock.call.iso8601
      replace_json(File.join(directory, "visual.json"), record)
      outcome("blocked_for_human_review", true, "locked-camera water loop rendered; full-preview review required", data: { "visual" => record }, mutation: "music_visual_loop_created")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_f(output) if defined?(output) && output
    end

    def final_preview(project_id:, candidate_id:, visual_id:)
      record = read_visual(project_id, candidate_id, visual_id)
      return outcome("complete", true, "visual companion preview already exists", data: { "visual" => record, "idempotent_replay" => true }) if record.dig("artifacts", "preview")
      scope = final_scope(record)
      outcome("blocked_for_human_review", true, "exact three-minute visual render confirmation required", data: gate(FINAL_CONFIRMATION, scope))
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def final_execute(project_id:, candidate_id:, visual_id:, confirmation:, expected_digest:, progress: nil)
      return missing_gate unless confirmation.to_s.length.positive? && expected_digest.to_s.length.positive?
      record = read_visual(project_id, candidate_id, visual_id)
      return outcome("complete", true, "visual companion preview already exists", data: { "visual" => record, "idempotent_replay" => true }) if record.dig("artifacts", "preview")
      scope = final_scope(record)
      return gate_mismatch("exact visual companion confirmation did not match") unless confirmation == FINAL_CONFIRMATION
      return gate_mismatch("visual companion scope changed; preview again") unless secure_compare(expected_digest, digest(scope))
      directory = visual_path(project_id, visual_id)
      audio = @store.candidate_artifact_path(project_id, candidate_id, "flac")
      duration = audio_duration(audio)
      progress&.call({ "stage" => "visual_companion", "message" => "Repeating the approved locked-camera water loop and binding the exact lossless candidate" })
      output = File.join(directory, ".preview.partial.mp4")
      render_final(File.join(directory, "loop.mp4"), audio, output, duration)
      File.rename(output, File.join(directory, "preview.mp4"))
      record["artifacts"]["preview"] = artifact("preview.mp4", directory).merge("duration_seconds" => duration, "width" => WIDTH, "height" => HEIGHT, "fps" => FPS)
      record["stage"] = "preview_ready"
      record["updated_at"] = @clock.call.iso8601
      replace_json(File.join(directory, "visual.json"), record)
      outcome("blocked_for_human_review", true, "three-minute visual companion ready for human review", data: { "visual" => record }, mutation: "music_visual_preview_created")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_f(output) if defined?(output) && output
    end

    def artifact_path(project_id:, candidate_id:, visual_id:, artifact:)
      record = read_visual(project_id, candidate_id, visual_id)
      filename = { "base" => "base.png", "loop" => "loop.mp4", "preview" => "preview.mp4" }[artifact.to_s]
      raise MusicProjectStore::ValidationError, "visual artifact is invalid" unless filename && record.dig("artifacts", artifact.to_s)
      path = File.join(visual_path(project_id, visual_id), filename)
      raise MusicProjectStore::IntegrityError, "visual artifact is missing" unless File.file?(path) && !File.symlink?(path)
      expected = record.dig("artifacts", artifact.to_s, "sha256")
      raise MusicProjectStore::IntegrityError, "visual artifact digest changed" unless secure_compare(expected, Digest::SHA256.file(path).hexdigest)
      path
    end

    private

    def import_scope(project_id, candidate_id, asset_id)
      project, candidate, audio = validate_binding!(project_id, candidate_id)
      source = read_source(asset_id)
      raise MusicProjectStore::ValidationError, "visual source does not belong to this exact candidate" unless source["project_id"] == project_id && source["candidate_id"] == candidate_id
      image = source_image(source)
      base = {
        "operation" => "bind_music_visual_source", "project_id" => project.fetch("project_id"), "candidate_id" => candidate.fetch("candidate_id"),
        "candidate_audio_sha256" => Digest::SHA256.file(audio).hexdigest, "asset_id" => source.fetch("asset_id"),
        "source_manifest_sha256" => Digest::SHA256.file(File.join(@source_root, "#{asset_id}.json")).hexdigest,
        "source_image_sha256" => Digest::SHA256.file(image).hexdigest, "provider" => source.fetch("provider"),
        "rights_status" => source.fetch("rights_status"), "render_profile_id" => render_profile.fetch("profile_id"), "external_publication" => false
      }
      base.merge("visual_id" => "visual_#{digest(base)[0, 16]}")
    end

    def loop_scope(record)
      raise MusicProjectStore::ValidationError, "visual source is not ready" unless record["stage"] == "base_bound"
      {
        "operation" => "render_music_visual_loop", "project_id" => record.fetch("project_id"), "candidate_id" => record.fetch("candidate_id"),
        "visual_id" => record.fetch("visual_id"), "base_sha256" => record.dig("artifacts", "base", "sha256"),
        "profile" => render_profile, "timeout_seconds" => COMMAND_TIMEOUT, "automatic_retry" => false
      }
    end

    def final_scope(record)
      raise MusicProjectStore::ValidationError, "review the rendered loop before creating the full preview" unless record["stage"] == "loop_ready"
      {
        "operation" => "render_music_visual_companion", "project_id" => record.fetch("project_id"), "candidate_id" => record.fetch("candidate_id"),
        "visual_id" => record.fetch("visual_id"), "loop_sha256" => record.dig("artifacts", "loop", "sha256"),
        "candidate_audio_sha256" => record.fetch("candidate_audio_sha256"), "intro_fade_seconds" => 2,
        "outro_fade_seconds" => 4, "output" => "H.264/AAC MP4", "external_publication" => false
      }
    end

    def render_loop(input, output)
      require_tools!
      frames = LOOP_SECONDS * FPS
      filter = "[0:v]scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=increase,crop=#{WIDTH}:#{HEIGHT}:x=(in_w-out_w)/2:y=(in_h-out_h)/2,split=2[scene][water_src];" \
               "[water_src]crop=#{WIDTH}:270:0:450[water];" \
               "nullsrc=s=#{WIDTH}x270:r=#{FPS}:d=#{LOOP_SECONDS},geq=lum='128+3*sin(2*PI*(Y/H+N/#{frames}))':cb=128:cr=128[xmap];" \
               "nullsrc=s=#{WIDTH}x270:r=#{FPS}:d=#{LOOP_SECONDS},geq=lum='128+2*sin(2*PI*(2*X/W+N/#{frames}))':cb=128:cr=128[ymap];" \
               "[water][xmap][ymap]displace=edge=mirror[water_moved];[scene][water_moved]overlay=0:450,format=yuv420p[v]"
      command = [@ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error", "-loop", "1", "-framerate", FPS.to_s, "-i", input, "-t", LOOP_SECONDS.to_s, "-filter_complex", filter, "-map", "[v]", "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-g", frames.to_s, "-keyint_min", frames.to_s, "-sc_threshold", "0", "-movflags", "+faststart", output]
      run_media!(command, output, "visual loop")
    end

    def render_final(loop_path, audio, output, duration)
      fade_start = [duration - 4.0, 0].max.round(3)
      filter = "[0:v]trim=duration=#{duration},setpts=PTS-STARTPTS,fade=t=in:st=0:d=2,fade=t=out:st=#{fade_start}:d=4,format=yuv420p[v]"
      command = [@ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error", "-stream_loop", "-1", "-i", loop_path, "-i", audio, "-t", duration.to_s, "-filter_complex", filter, "-map", "[v]", "-map", "1:a:0", "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", output]
      run_media!(command, output, "visual companion")
    end

    def audio_duration(path)
      require_tools!
      result = @runner.run(@ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", path, timeout_seconds: 15, max_output_bytes: 4096)
      value = Float(result.stdout.to_s.strip)
      raise MusicProjectStore::IntegrityError, "candidate audio duration is invalid" unless result.success? && value.between?(1, 600)
      value.round(3)
    rescue ArgumentError
      raise MusicProjectStore::IntegrityError, "candidate audio duration is invalid"
    end

    def run_media!(command, output, label)
      result = @runner.run(command, timeout_seconds: COMMAND_TIMEOUT, max_output_bytes: 128 * 1024)
      raise MusicProjectStore::IntegrityError, "#{label} failed safely: #{result.status}" unless result.success? && File.file?(output) && File.size(output).positive?
      File.chmod(0o600, output)
    end

    def validate_binding!(project_id, candidate_id)
      project = @store.read(project_id)
      audio = @store.candidate_artifact_path(project_id, candidate_id, "flac")
      candidate_path = File.join(File.dirname(audio), "candidate.json")
      candidate = JSON.parse(File.binread(candidate_path, MAX_RECORD_BYTES))
      raise MusicProjectStore::IntegrityError, "music candidate identity is invalid" unless candidate["schema_version"] == "soul.music.generation.v1" && candidate["project_id"] == project_id && candidate["candidate_id"] == candidate_id
      expected = candidate.dig("artifacts", "flac", "sha256")
      raise MusicProjectStore::IntegrityError, "candidate audio digest changed" unless secure_compare(expected, Digest::SHA256.file(audio).hexdigest)
      [project, candidate, audio]
    rescue JSON::ParserError, Errno::ENOENT => error
      raise MusicProjectStore::IntegrityError, "invalid music candidate: #{error.class}"
    end

    def read_source(asset_id)
      id = asset_id.to_s
      raise MusicProjectStore::ValidationError, "visual source ID is invalid" unless id.match?(SOURCE_ID)
      path = File.join(@source_root, "#{id}.json")
      raise MusicProjectStore::ValidationError, "visual source does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_RECORD_BYTES)
      source = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      required = %w[schema_version asset_id label image project_id candidate_id provider rights_status generated_at prompt_summary animation_intent]
      raise MusicProjectStore::IntegrityError, "visual source record is invalid" unless source.keys.sort == required.sort && source["schema_version"] == "soul.music.visual_source.v1" && source["asset_id"] == id
      source
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid visual source record: #{error.class}"
    end

    def source_image(source)
      name = source.fetch("image")
      raise MusicProjectStore::IntegrityError, "visual source image name is invalid" unless name == "#{source.fetch('asset_id')}.png"
      path = File.join(@source_root, name)
      raise MusicProjectStore::IntegrityError, "visual source image is invalid" unless File.file?(path) && !File.symlink?(path) && File.size(path).positive?
      path
    end

    def read_visual(project_id, candidate_id, visual_id)
      raise MusicProjectStore::ValidationError, "visual ID is invalid" unless visual_id.to_s.match?(VISUAL_ID)
      path = File.join(visual_path(project_id, visual_id), "visual.json")
      raise MusicProjectStore::ValidationError, "visual companion does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_RECORD_BYTES)
      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      raise MusicProjectStore::IntegrityError, "visual companion identity is invalid" unless record["schema_version"] == "soul.music.visual.v1" && record["project_id"] == project_id && record["candidate_id"] == candidate_id && record["visual_id"] == visual_id
      record
    rescue JSON::ParserError => error
      raise MusicProjectStore::IntegrityError, "invalid visual companion: #{error.class}"
    end

    def existing_visual(scope)
      path = File.join(visual_path(scope.fetch("project_id"), scope.fetch("visual_id")), "visual.json")
      return nil unless File.exist?(path)
      read_visual(scope.fetch("project_id"), scope.fetch("candidate_id"), scope.fetch("visual_id"))
    end

    def visuals_root(project_id, create:)
      project = @store.read(project_id)
      path = File.join(@store.project_path(project.fetch("project_id")), "visuals")
      return nil unless create || File.exist?(path) || File.symlink?(path)
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        raise MusicProjectStore::IntegrityError, "visual companion root is invalid" unless stat.directory? && !stat.symlink?
      else
        Dir.mkdir(path, 0o700)
      end
      path
    end

    def visual_path(project_id, visual_id)
      File.join(visuals_root(project_id, create: false) || File.join(@store.project_path(project_id), "visuals"), visual_id)
    end

    def artifact(name, directory)
      path = File.join(directory, name)
      { "path" => name, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
    end

    def render_profile
      { "profile_id" => "localized-water-locked-camera-v2", "loop_seconds" => LOOP_SECONDS, "width" => WIDTH, "height" => HEIGHT, "fps" => FPS, "renderer" => "ffmpeg/libx264", "model_inference" => false, "resource_lane" => "cpu-foreground" }
    end

    def require_tools!
      raise MusicProjectStore::ValidationError, "ffmpeg and ffprobe are required for visual companions" unless @ffmpeg && @ffprobe
    end

    def gate(phrase, scope) = { "confirmation_phrase" => phrase, "expected_digest" => digest(scope), "preview_scope" => scope }
    def missing_gate = outcome("awaiting_input", false, "confirmation and expected_digest are required")
    def gate_mismatch(reason) = outcome("blocked_for_human_review", false, reason)
    def write_json(path, value) = File.write(path, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
    def replace_json(path, value)
      temporary = "#{path}.tmp-#{SecureRandom.hex(4)}"
      File.write(temporary, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def within?(path, parent) = File.expand_path(path) == File.expand_path(parent) || File.expand_path(path).start_with?(File.expand_path(parent) + File::SEPARATOR)
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
