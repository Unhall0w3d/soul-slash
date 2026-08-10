# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "blender_audio_analyzer"
require_relative "blender_scene_manifest"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"
require_relative "music_project_store"

module SoulCore
  class BlenderSceneService
    SCENE_ID = /\Ablender_scene_[a-f0-9]{16}\z/
    VISUAL_PROJECT_ID = /\Avisual_project_[a-f0-9]{16}\z/
    TEMPLATE_IDS = %w[abstract liminal architectural audio_reactive bioluminescent_grove].freeze
    BAR_COUNTS = [8, 12].freeze
    QUALITY = {
      "review" => { "width" => 1_280, "height" => 720 },
      "production" => { "width" => 1_920, "height" => 1_080 }
    }.freeze
    CONFIRMATION = "GENERATE_BLENDER_SCENE"
    REVISION_CONFIRMATION = "GENERATE_BLENDER_REVISION"
    DELETE_CONFIRMATION = "DELETE_BLENDER_SCENE"
    PROMOTION_CONFIRMATION = "BIND_VISUAL_COMPANION"
    RESOURCE_GROUP = "amd-vulkan-generation"
    TIMEOUT_SECONDS = 1_800
    MAX_RECORD_BYTES = 256 * 1024

    def initialize(root: Dir.pwd, visual_root: nil, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) }, music_store: nil, analyzer: nil, lease_store: nil, music_visual_companion: nil)
      @root = File.expand_path(root)
      @visual_root = File.expand_path(visual_root || File.join(@root, "Soul", "visual", "projects"))
      @runner = runner
      @clock = clock
      @id_generator = id_generator
      @music_store = music_store || MusicProjectStore.new(root: @root)
      @analyzer = analyzer || BlenderAudioAnalyzer.new(runner: @runner)
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @music_visual_companion = music_visual_companion
      @blender = @runner.which("blender")
      @ffmpeg = @runner.which("ffmpeg")
      @ffprobe = @runner.which("ffprobe")
      @template_path = File.join(@root, "config", "blender_scene_templates.json")
      @adapter_path = File.join(@root, "scripts", "blender", "soul_scene_adapter.py")
      @render_path = File.join(@root, "scripts", "blender", "soul_scene_render.py")
      raise ArgumentError, "Blender scene archive must remain inside the repository" unless within?(@visual_root, @root)
    end

    def resources
      catalog = template_catalog
      tools_ready = [@blender, @ffmpeg, @ffprobe].all? { |path| path && File.file?(path) && File.executable?(path) && !File.symlink?(path) }
      scripts_ready = [@adapter_path, @render_path].all? { |path| File.file?(path) && !File.symlink?(path) }
      version_result = tools_ready ? @runner.run([@blender, "--version"], timeout_seconds: 30, max_output_bytes: 16 * 1024) : nil
      blender_version = version_result&.success? ? version_result.stdout.to_s.lines.first.to_s.strip : nil
      ready = tools_ready && scripts_ready && version_result&.success?
      outcome("complete", true, "Blender scene resources inspected", data: {
        "ready" => ready,
        "blender" => @blender,
        "blender_version" => blender_version,
        "ffmpeg" => @ffmpeg,
        "ffprobe" => @ffprobe,
        "templates" => catalog.fetch("templates").keys,
        "bars" => BAR_COUNTS,
        "quality_profiles" => QUALITY,
        "resource_group" => RESOURCE_GROUP,
        "foreground_only" => true,
        "automatic_retry" => false,
        "network_listener" => false,
        "persistent_service" => false
      })
    rescue StandardError => error
      outcome("failed", false, "Blender scene resource inspection failed safely: #{error.class}")
    end

    def templates
      entries = template_catalog.fetch("templates").map do |id, manifest|
        {
          "template_id" => id,
          "label" => id.split("_").map(&:capitalize).join(" "),
          "objects" => manifest.fetch("objects").length,
          "lights" => manifest.fetch("lights").length,
          "audio_reactive" => manifest.dig("audio_binding", "enabled") && manifest.dig("audio_binding", "tracks").any?
        }
      end
      outcome("complete", true, "Blender scene templates listed", data: { "templates" => entries })
    rescue StandardError => error
      outcome("failed", false, "Blender scene template catalog failed safely: #{error.class}")
    end

    def list(project_id:)
      read_visual_project(project_id)
      directory = scenes_root(project_id, create: false)
      records = if directory
        safe_children(directory).grep(SCENE_ID).filter_map do |id|
          record = read_scene(project_id, id)
          review_path = File.join(scene_dir(project_id, id), "review.json")
          record["review"] = JSON.parse(File.binread(review_path, MAX_RECORD_BYTES)) if File.file?(review_path) && !File.symlink?(review_path)
          record
        rescue StandardError
          nil
        end
      else
        []
      end
      outcome("complete", true, "Blender scene candidates listed", data: { "blender_scenes" => records.sort_by { |record| record.fetch("created_at") }.reverse })
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    end

    def preview(project_id:, music_project_id:, music_candidate_id:, template_id:, bars:, direction:, seed:, quality: "review", source_scene_id: nil)
      operation = source_scene_id ? "blender_scene_revision" : "blender_scene_generation"
      confirmation = source_scene_id ? REVISION_CONFIRMATION : CONFIRMATION
      plan = build_plan(
        operation: operation, project_id: project_id, music_project_id: music_project_id,
        music_candidate_id: music_candidate_id, template_id: template_id, bars: bars,
        direction: direction, seed: seed, quality: quality, source_scene_id: source_scene_id
      )
      outcome("blocked_for_human_review", true, "exact whole-bar Blender scene requires approval", data: plan.fetch("scope").merge(
        "expected_digest" => digest(plan.fetch("scope")), "confirmation_phrase" => confirmation,
        "manifest" => plan.fetch("manifest"), "audio_analysis_summary" => analysis_summary(plan.fetch("analysis"))
      ))
    rescue ArgumentError, MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def execute(project_id:, scene_id:, music_project_id:, music_candidate_id:, template_id:, bars:, direction:, seed:, quality: "review", source_scene_id: nil, confirmation:, expected_digest:, progress: nil)
      raise ArgumentError, "Blender scene candidate ID is invalid" unless scene_id.to_s.match?(SCENE_ID)
      operation = source_scene_id ? "blender_scene_revision" : "blender_scene_generation"
      phrase = source_scene_id ? REVISION_CONFIRMATION : CONFIRMATION
      plan = build_plan(
        operation: operation, project_id: project_id, music_project_id: music_project_id,
        music_candidate_id: music_candidate_id, template_id: template_id, bars: bars,
        direction: direction, seed: seed, quality: quality, source_scene_id: source_scene_id,
        scene_id: scene_id
      )
      scope = plan.fetch("scope")
      raise "exact Blender scene approval did not match" unless confirmation == phrase && secure_compare(expected_digest, digest(scope))
      raise "Blender scene resources are unavailable" unless resources.dig("data", "ready")

      lease = @lease_store.acquire_exclusive(
        provider_id: "blender-visual", model_id: "blender-5.2-eevee", request_id: scene_id,
        resource_group: RESOURCE_GROUP, conversation_id: project_id, ttl_seconds: TIMEOUT_SECONDS + 120
      )
      render_plan(plan, progress: progress)
    rescue ArgumentError, MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue ModelRuntimeLeaseStore::ResourceBusy => error
      outcome("blocked_for_human_review", false, "AMD generation resource is occupied: #{error.message}")
    rescue StandardError => error
      retain_failure(plan, error) if defined?(plan) && plan
      outcome("failed", false, "Blender scene failed safely: #{error.message}", data: resumable_summary(plan))
    ensure
      @lease_store.release(lease && lease["lease_id"])
    end

    def resume_preview(project_id:, scene_id:)
      staging = partial_scene_dir(project_id, scene_id)
      plan = read_partial_plan(staging, project_id, scene_id)
      missing = missing_frames(staging, plan.dig("analysis", "frame_count"))
      raise ArgumentError, "Blender scene has no missing frames" if missing.empty?
      scope = {
        "operation" => "resume_blender_scene", "project_id" => project_id, "scene_id" => scene_id,
        "manifest_sha256" => plan.fetch("manifest_sha256"), "audio_analysis_sha256" => plan.fetch("audio_analysis_sha256"),
        "missing_frames" => missing.length, "first_missing_frame" => missing.first,
        "last_missing_frame" => missing.last, "automatic_retry" => false
      }
      outcome("blocked_for_human_review", true, "exact retained Blender render may be resumed", data: scope.merge("expected_digest" => digest(scope), "confirmation_phrase" => CONFIRMATION))
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def resume_execute(project_id:, scene_id:, confirmation:, expected_digest:, progress: nil)
      preview = resume_preview(project_id: project_id, scene_id: scene_id)
      raise "retained Blender scene is not resumable" unless preview["ok"]
      scope = preview.fetch("data").reject { |key, _| %w[expected_digest confirmation_phrase].include?(key) }
      raise "exact Blender resume approval did not match" unless confirmation == CONFIRMATION && secure_compare(expected_digest, digest(scope))
      staging = partial_scene_dir(project_id, scene_id)
      plan = read_partial_plan(staging, project_id, scene_id)
      lease = @lease_store.acquire_exclusive(
        provider_id: "blender-visual", model_id: "blender-5.2-eevee", request_id: scene_id,
        resource_group: RESOURCE_GROUP, conversation_id: project_id, ttl_seconds: TIMEOUT_SECONDS + 120
      )
      render_plan(plan, progress: progress, resume: true)
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue ModelRuntimeLeaseStore::ResourceBusy => error
      outcome("blocked_for_human_review", false, "AMD generation resource is occupied: #{error.message}")
    rescue StandardError => error
      retain_failure(plan, error) if defined?(plan) && plan
      outcome("failed", false, "Blender scene resume failed safely: #{error.message}", data: resumable_summary(plan))
    ensure
      @lease_store.release(lease && lease["lease_id"])
    end

    def review(project_id:, scene_id:, review:)
      scene = read_scene(project_id, scene_id)
      data = stringify_keys(review)
      raise ArgumentError, "Blender review fields are invalid" unless data.keys.sort == %w[disposition notes rating].sort
      rating = Integer(data.fetch("rating"))
      raise ArgumentError, "rating must be 1..5" unless (1..5).cover?(rating)
      raise ArgumentError, "Blender disposition must be keep or revise" unless %w[keep revise].include?(data.fetch("disposition"))
      notes = data.fetch("notes").to_s
      raise ArgumentError, "review notes exceed 8000 characters" if notes.length > 8_000
      record = data.merge(
        "schema_version" => "soul.visual.blender_review.v1", "project_id" => project_id,
        "scene_id" => scene_id, "scene_sha256" => digest(scene), "rating" => rating,
        "reviewed_at" => @clock.call.iso8601
      )
      replace_json(File.join(scene_dir(project_id, scene_id), "review.json"), record)
      outcome("complete", true, "Blender scene review recorded", data: { "review" => record }, mutation: "blender_scene_reviewed")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, error.message)
    end

    def delete_preview(project_id:, scene_id:)
      scene = read_scene(project_id, scene_id)
      scope = {
        "operation" => "delete_blender_scene", "project_id" => project_id, "scene_id" => scene_id,
        "scene_record_sha256" => digest(scene), "archive_sha256" => directory_digest(scene_dir(project_id, scene_id))
      }
      outcome("blocked_for_human_review", true, "exact Blender scene deletion requires approval", data: scope.merge("expected_digest" => digest(scope), "confirmation_phrase" => DELETE_CONFIRMATION))
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    end

    def delete_execute(project_id:, scene_id:, confirmation:, expected_digest:)
      preview = delete_preview(project_id: project_id, scene_id: scene_id)
      scope = preview.fetch("data").reject { |key, _| %w[expected_digest confirmation_phrase].include?(key) }
      raise "exact Blender scene deletion did not match" unless confirmation == DELETE_CONFIRMATION && secure_compare(expected_digest, digest(scope))
      FileUtils.rm_rf(scene_dir(project_id, scene_id))
      outcome("complete", true, "Blender scene permanently deleted", data: scope, mutation: "blender_scene_deleted")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def promotion_preview(project_id:, scene_id:)
      companion = require_music_companion!
      scene = reviewed_scene!(project_id, scene_id)
      companion.generated_blender_import_preview(
        project_id: scene.fetch("music_project_id"), candidate_id: scene.fetch("music_candidate_id"),
        source_project_id: project_id, source_scene_id: scene_id,
        source_path: artifact_path(project_id: project_id, scene_id: scene_id, artifact: "preview"),
        prompt_summary: scene.fetch("direction"), source_receipt: scene
      )
    end

    def promotion_execute(project_id:, scene_id:, confirmation:, expected_digest:)
      companion = require_music_companion!
      scene = reviewed_scene!(project_id, scene_id)
      companion.generated_blender_import_execute(
        project_id: scene.fetch("music_project_id"), candidate_id: scene.fetch("music_candidate_id"),
        source_project_id: project_id, source_scene_id: scene_id,
        source_path: artifact_path(project_id: project_id, scene_id: scene_id, artifact: "preview"),
        prompt_summary: scene.fetch("direction"), source_receipt: scene,
        confirmation: confirmation, expected_digest: expected_digest
      )
    end

    def artifact_path(project_id:, scene_id:, artifact:)
      scene = read_scene(project_id, scene_id)
      metadata = scene.dig("artifacts", artifact.to_s)
      raise ArgumentError, "Blender scene artifact is invalid" unless metadata
      path = File.join(scene_dir(project_id, scene_id), metadata.fetch("path"))
      raise "Blender scene artifact is missing" unless File.file?(path) && !File.symlink?(path)
      raise "Blender scene artifact digest changed" unless secure_compare(metadata.fetch("sha256"), Digest::SHA256.file(path).hexdigest)
      path
    end

    private

    def build_plan(operation:, project_id:, music_project_id:, music_candidate_id:, template_id:, bars:, direction:, seed:, quality:, source_scene_id: nil, scene_id: nil)
      project = read_visual_project(project_id)
      template_id = template_id.to_s
      raise ArgumentError, "Blender template is invalid" unless TEMPLATE_IDS.include?(template_id)
      bars = Integer(bars)
      raise ArgumentError, "Blender loop must contain exactly 8 or 12 whole bars" unless BAR_COUNTS.include?(bars)
      seed = Integer(seed)
      raise ArgumentError, "Blender seed must be 0..2147483647" unless seed.between?(0, 2**31 - 1)
      quality = quality.to_s
      raise ArgumentError, "Blender quality profile is invalid" unless QUALITY.key?(quality)
      direction = direction.to_s.strip
      raise ArgumentError, "Blender scene direction must be 12..2000 characters" unless direction.length.between?(12, 2_000)
      source = source_scene_id ? reviewed_scene!(project_id, source_scene_id) : nil
      music_project = @music_store.read(music_project_id)
      music_input = @music_store.candidate_input(music_project_id, music_candidate_id)
      review = @music_store.read_review(music_project_id, music_candidate_id)
      raise ArgumentError, "music candidate must have a retained keep review" unless review && review["disposition"] == "keep"
      audio = @music_store.candidate_artifact_path(music_project_id, music_candidate_id, "flac")
      beats_per_bar = time_signature_numerator(music_input.fetch("timesignature"))
      template = deep_copy(template_catalog.fetch("templates").fetch(template_id))
      fps = Integer(template.dig("render", "fps"))
      analysis = @analyzer.analyze(path: audio, bpm: music_input.fetch("bpm"), beats_per_bar: beats_per_bar, bars: bars, fps: fps)
      scene_id ||= "blender_scene_#{@id_generator.call}"
      raise "generated Blender scene ID is invalid" unless scene_id.match?(SCENE_ID)
      manifest = materialize_manifest(template, project_id: project_id, scene_id: scene_id, music_candidate_id: music_candidate_id, seed: seed, quality: quality, analysis: analysis)
      parsed = BlenderSceneManifest.new(manifest)
      scope = {
        "operation" => operation, "visual_project_id" => project.fetch("project_id"), "visual_project_sha256" => digest(project),
        "scene_id" => scene_id, "source_scene_id" => source_scene_id,
        "music_project_id" => music_project.fetch("project_id"), "music_candidate_id" => music_candidate_id,
        "music_candidate_review_sha256" => digest(review), "music_audio_sha256" => Digest::SHA256.file(audio).hexdigest,
        "template_id" => template_id, "bars" => bars, "beats_per_bar" => beats_per_bar,
        "bpm" => Float(music_input.fetch("bpm")), "quality" => quality, "direction" => direction, "seed" => seed,
        "frame_count" => analysis.fetch("frame_count"), "fps" => fps,
        "nominal_duration_seconds" => analysis.fetch("nominal_duration_seconds"),
        "rendered_duration_seconds" => analysis.fetch("rendered_duration_seconds"),
        "manifest_sha256" => parsed.sha256, "audio_analysis_sha256" => digest(analysis),
        "resource_group" => RESOURCE_GROUP, "timeout_seconds" => TIMEOUT_SECONDS,
        "automatic_retry" => false, "external_publication" => false
      }.compact
      {
        "scope" => scope, "manifest" => parsed.to_h, "manifest_sha256" => parsed.sha256,
        "analysis" => analysis, "audio_analysis_sha256" => digest(analysis), "audio_path" => audio,
        "direction" => direction, "created_at" => @clock.call.iso8601
      }
    end

    def materialize_manifest(template, project_id:, scene_id:, music_candidate_id:, seed:, quality:, analysis:)
      template["identity"] = {
        "id" => scene_id, "project_id" => project_id,
        "revision" => "a2-#{scene_id.delete_prefix('blender_scene_')}", "music_candidate_id" => music_candidate_id
      }
      template["render"].merge!(QUALITY.fetch(quality))
      template["render"]["frame_start"] = 1
      template["render"]["frame_end"] = analysis.fetch("frame_count")
      template["render"]["seed"] = seed
      remap_template_animation!(template)
      expand_audio_bindings!(template, analysis)
      template["output"] = { "blend_name" => "scene.blend", "still_name" => "still.png", "still_frame" => 1, "retention" => "full_candidate" }
      template
    end

    def remap_template_animation!(manifest)
      frame_end = manifest.dig("render", "frame_end")
      manifest.fetch("animation").each_value do |channels|
        channels.each do |channel|
          old_start = channel.fetch("frames").first
          old_end = channel.fetch("frames").last
          channel["frames"] = channel.fetch("frames").map do |frame|
            old_end == old_start ? 1 : 1 + (((frame - old_start).to_f / (old_end - old_start)) * (frame_end - 1)).round
          end
          next if channel.fetch("property") == "rotation_euler"
          channel["values"][-1] = deep_copy(channel.fetch("values").first)
        end
      end
    end

    def expand_audio_bindings!(manifest, analysis)
      frames = analysis.fetch("curve_frames")
      manifest.dig("audio_binding", "tracks").each do |track|
        values = analysis.dig("curves", track.fetch("curve"))
        target_type = track.fetch("target_type")
        target_id = track.fetch("target_id")
        property = track.fetch("property")
        gain = Float(track.fetch("gain"))
        base = audio_property_base(manifest, target_type, target_id, property)
        expanded = values.map { |value| audio_property_value(property, base, value, gain) }
        section = { "object" => "objects", "material" => "materials", "camera" => "camera", "light" => "lights", "world" => "world" }.fetch(target_type)
        channels = manifest.fetch("animation").fetch(section)
        channels.reject! { |channel| channel["target_id"] == target_id && channel["property"] == property }
        channels << { "target_id" => target_id, "property" => property, "frames" => frames, "values" => expanded, "interpolation" => "LINEAR" }
      end
    end

    def audio_property_base(manifest, target_type, target_id, property)
      collection = case target_type
                   when "object" then manifest.fetch("objects")
                   when "material" then manifest.fetch("materials")
                   when "light" then manifest.fetch("lights")
                   when "camera" then [manifest.fetch("camera")]
                   when "world" then [manifest.fetch("world").merge("id" => "world")]
                   end
      collection.find { |entry| entry["id"] == target_id }.fetch(property)
    end

    def audio_property_value(property, base, envelope, gain)
      case property
      when "scale"
        base.map { |value| (value * (1.0 + envelope * gain)).round(6) }
      when "energy"
        (base * (1.0 + envelope * gain)).round(6)
      when "emission_strength", "metallic", "roughness", "lens"
        (base + envelope * gain).round(6)
      else
        base
      end
    end

    def render_plan(plan, progress:, resume: false)
      scope = plan.fetch("scope")
      project_id = scope.fetch("visual_project_id")
      scene_id = scope.fetch("scene_id")
      staging = partial_scene_dir(project_id, scene_id)
      target = scene_dir(project_id, scene_id)
      raise "Blender scene candidate already exists" if File.exist?(target) || File.symlink?(target)
      unless resume
        raise "Blender staging candidate already exists; use resume" if File.exist?(staging) || File.symlink?(staging)
        FileUtils.mkdir_p(File.join(staging, "frames"), mode: 0o700)
        write_json(File.join(staging, "scene.json"), plan.fetch("manifest"))
        write_json(File.join(staging, "audio-analysis.json"), plan.fetch("analysis"))
        write_json(File.join(staging, "plan.json"), serializable_plan(plan))
      end

      progress&.call({ "stage" => "blender_scene", "message" => resume ? "Resuming retained whole-bar frames" : "Constructing the trusted Blender scene" })
      unless File.file?(File.join(staging, "scene.blend"))
        run_command!(
          [@blender, "--background", "--python", @adapter_path, "--", "--manifest", File.join(staging, "scene.json"),
           "--blend-path", File.join(staging, "scene.blend"), "--still-path", File.join(staging, "still.png"), "--frame", "1"],
          "Blender scene construction", timeout: 180
        )
      end

      missing = missing_frames(staging, plan.dig("analysis", "frame_count"))
      progress&.call({ "stage" => "blender_frames", "message" => "Rendering #{missing.length} missing EEVEE frames" })
      contiguous_ranges(missing).each do |first, last|
        run_command!(
          [@blender, "--background", File.join(staging, "scene.blend"), "--python", @render_path, "--",
           "--frames-dir", File.join(staging, "frames"), "--frame-start", first.to_s, "--frame-end", last.to_s],
          "Blender frame render", timeout: TIMEOUT_SECONDS
        )
      end
      raise "Blender frame set is incomplete" unless missing_frames(staging, plan.dig("analysis", "frame_count")).empty?

      progress&.call({ "stage" => "blender_encode", "message" => "Encoding the reviewed whole-bar loop with exact candidate audio" })
      preview = File.join(staging, "preview.mp4")
      run_command!(
        [@ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error", "-framerate", scope.fetch("fps").to_s,
         "-i", File.join(staging, "frames", "frame_%04d.png"), "-i", plan.fetch("audio_path"),
         "-t", scope.fetch("rendered_duration_seconds").to_s, "-map", "0:v:0", "-map", "1:a:0",
         "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", preview],
        "Blender preview encoding", timeout: 600
      )

      record = scene_record(plan, staging)
      replace_json(File.join(staging, "candidate.json"), record)
      FileUtils.rm_f(File.join(staging, "failure.json"))
      File.rename(staging, target)
      outcome("blocked_for_human_review", true, "whole-bar Blender scene ready for human review", data: { "blender_scene" => record }, mutation: "blender_scene_generated")
    end

    def scene_record(plan, staging)
      scope = plan.fetch("scope")
      artifacts = {
        "manifest" => artifact("scene.json", File.join(staging, "scene.json")),
        "blend" => artifact("scene.blend", File.join(staging, "scene.blend")),
        "still" => artifact("still.png", File.join(staging, "still.png")),
        "audio_analysis" => artifact("audio-analysis.json", File.join(staging, "audio-analysis.json")),
        "preview" => artifact("preview.mp4", File.join(staging, "preview.mp4"))
      }
      {
        "schema_version" => "soul.visual.blender_scene.v1", "project_id" => scope.fetch("visual_project_id"),
        "scene_id" => scope.fetch("scene_id"), "source_scene_id" => scope["source_scene_id"],
        "music_project_id" => scope.fetch("music_project_id"), "music_candidate_id" => scope.fetch("music_candidate_id"),
        "template_id" => scope.fetch("template_id"), "direction" => scope.fetch("direction"), "quality" => scope.fetch("quality"),
        "bars" => scope.fetch("bars"), "beats_per_bar" => scope.fetch("beats_per_bar"), "bpm" => scope.fetch("bpm"),
        "fps" => scope.fetch("fps"), "frame_count" => scope.fetch("frame_count"),
        "duration_seconds" => scope.fetch("rendered_duration_seconds"), "width" => plan.dig("manifest", "render", "width"),
        "height" => plan.dig("manifest", "render", "height"), "manifest_sha256" => plan.fetch("manifest_sha256"),
        "audio_analysis_sha256" => plan.fetch("audio_analysis_sha256"), "music_audio_sha256" => scope.fetch("music_audio_sha256"),
        "loop_state_equal" => plan.dig("analysis", "loop_state_equal"), "lifecycle_state" => "blocked_for_human_review",
        "artifacts" => artifacts, "created_at" => plan.fetch("created_at"), "completed_at" => @clock.call.iso8601,
        "human_review_required" => true, "external_publication" => false
      }.compact
    end

    def reviewed_scene!(project_id, scene_id)
      scene = read_scene(project_id, scene_id)
      path = File.join(scene_dir(project_id, scene_id), "review.json")
      raise ArgumentError, "Blender scene requires a retained keep review" unless File.file?(path) && !File.symlink?(path)
      review = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      raise ArgumentError, "Blender scene requires a retained keep review" unless review["disposition"] == "keep"
      scene
    end

    def read_scene(project_id, scene_id)
      raise ArgumentError, "visual project ID is invalid" unless project_id.to_s.match?(VISUAL_PROJECT_ID)
      raise ArgumentError, "Blender scene candidate ID is invalid" unless scene_id.to_s.match?(SCENE_ID)
      path = File.join(scene_dir(project_id, scene_id), "candidate.json")
      raise ArgumentError, "Blender scene candidate does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_RECORD_BYTES)
      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      raise "Blender scene candidate identity is invalid" unless record["schema_version"] == "soul.visual.blender_scene.v1" && record["project_id"] == project_id && record["scene_id"] == scene_id
      record
    rescue JSON::ParserError => error
      raise "invalid Blender scene candidate: #{error.class}"
    end

    def read_visual_project(project_id)
      raise ArgumentError, "visual project ID is invalid" unless project_id.to_s.match?(VISUAL_PROJECT_ID)
      path = File.join(@visual_root, project_id, "project.json")
      raise ArgumentError, "visual project does not exist" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_RECORD_BYTES)
      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      raise "visual project identity is invalid" unless record["project_id"] == project_id
      record
    rescue JSON::ParserError => error
      raise "invalid visual project: #{error.class}"
    end

    def template_catalog
      raise "Blender scene template catalog is invalid" unless File.file?(@template_path) && !File.symlink?(@template_path)
      catalog = JSON.parse(File.binread(@template_path, MAX_RECORD_BYTES))
      raise "Blender scene template catalog schema is invalid" unless catalog["schema_version"] == "soul.blender.scene.templates.v1"
      raise "Blender scene template catalog is not closed" unless catalog.fetch("templates").keys.sort == TEMPLATE_IDS.sort
      catalog.fetch("templates").each_value { |manifest| BlenderSceneManifest.new(deep_copy(manifest)) }
      catalog
    end

    def time_signature_numerator(value)
      text = value.to_s.strip
      numerator = text.include?("/") ? text.split("/", 2).first : text
      Integer(numerator)
    rescue ArgumentError
      raise ArgumentError, "music candidate time signature is invalid"
    end

    def scenes_root(project_id, create:)
      project = read_visual_project(project_id)
      path = File.join(@visual_root, project.fetch("project_id"), "blender-scenes")
      return nil unless create || File.exist?(path)
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        raise "Blender scene archive root is invalid" unless stat.directory? && !stat.symlink?
      else
        Dir.mkdir(path, 0o700)
      end
      path
    end

    def scene_dir(project_id, scene_id)
      File.join(scenes_root(project_id, create: true), scene_id)
    end

    def partial_scene_dir(project_id, scene_id)
      raise ArgumentError, "Blender scene candidate ID is invalid" unless scene_id.to_s.match?(SCENE_ID)
      File.join(scenes_root(project_id, create: true), ".#{scene_id}.partial")
    end

    def read_partial_plan(staging, project_id, scene_id)
      raise ArgumentError, "retained Blender scene does not exist" unless File.directory?(staging) && !File.symlink?(staging)
      path = File.join(staging, "plan.json")
      raise ArgumentError, "retained Blender scene plan is invalid" unless File.file?(path) && !File.symlink?(path)
      plan = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      raise ArgumentError, "retained Blender scene identity changed" unless plan.dig("scope", "visual_project_id") == project_id && plan.dig("scope", "scene_id") == scene_id
      plan.merge("audio_path" => @music_store.candidate_artifact_path(plan.dig("scope", "music_project_id"), plan.dig("scope", "music_candidate_id"), "flac"))
    end

    def serializable_plan(plan)
      plan.reject { |key, _| key == "audio_path" }
    end

    def missing_frames(staging, frame_count)
      frames = File.join(staging, "frames")
      (1..Integer(frame_count)).reject { |frame| valid_frame?(File.join(frames, format("frame_%04d.png", frame))) }
    end

    def valid_frame?(path)
      File.file?(path) && !File.symlink?(path) && File.size(path).positive?
    end

    def contiguous_ranges(frames)
      return [] if frames.empty?
      ranges = []
      first = previous = frames.first
      frames.drop(1).each do |frame|
        if frame == previous + 1
          previous = frame
        else
          ranges << [first, previous]
          first = previous = frame
        end
      end
      ranges << [first, previous]
      raise "retained Blender frame set is too fragmented to resume safely" if ranges.length > 32
      ranges
    end

    def run_command!(command, label, timeout:)
      result = @runner.run(command, timeout_seconds: timeout, max_output_bytes: 256 * 1024, env: { "BLENDER_USER_CONFIG" => "/tmp/soul-blender-config" })
      raise "#{label} failed safely: #{result.status}: #{result.stderr.to_s.lines.last(4).join.strip}" unless result.success?
    end

    def retain_failure(plan, error)
      scope = plan.fetch("scope")
      staging = partial_scene_dir(scope.fetch("visual_project_id"), scope.fetch("scene_id"))
      return unless File.directory?(staging) && !File.symlink?(staging)
      replace_json(File.join(staging, "failure.json"), {
        "schema_version" => "soul.visual.blender_failure.v1", "scene_id" => scope.fetch("scene_id"),
        "manifest_sha256" => plan.fetch("manifest_sha256"), "error" => error.message.to_s.slice(0, 2_000),
        "retained_frames" => plan.dig("analysis", "frame_count") - missing_frames(staging, plan.dig("analysis", "frame_count")).length,
        "failed_at" => @clock.call.iso8601, "automatic_retry" => false
      })
    rescue StandardError
      nil
    end

    def resumable_summary(plan)
      return {} unless plan
      scope = plan.fetch("scope")
      staging = partial_scene_dir(scope.fetch("visual_project_id"), scope.fetch("scene_id"))
      return { "scene_id" => scope.fetch("scene_id"), "resumable" => false } unless File.directory?(staging)
      missing = missing_frames(staging, plan.dig("analysis", "frame_count"))
      { "scene_id" => scope.fetch("scene_id"), "resumable" => missing.any?, "retained_frames" => plan.dig("analysis", "frame_count") - missing.length, "missing_frames" => missing.length }
    rescue StandardError
      {}
    end

    def analysis_summary(analysis)
      analysis.slice("bpm", "beats_per_bar", "bars", "fps", "frame_count", "nominal_duration_seconds", "rendered_duration_seconds", "bar_frames", "loop_state_equal")
    end

    def require_music_companion!
      raise ArgumentError, "music visual companion service is unavailable" unless @music_visual_companion
      @music_visual_companion
    end

    def artifact(name, path)
      { "path" => name, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
    end

    def directory_digest(directory)
      entries = Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).reject { |path| File.directory?(path) }.sort
      digest(entries.map { |path| [path.delete_prefix("#{directory}/"), Digest::SHA256.file(path).hexdigest] })
    end

    def write_json(path, value)
      File.write(path, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
    end

    def replace_json(path, value)
      temporary = "#{path}.tmp-#{SecureRandom.hex(4)}"
      File.write(temporary, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def safe_children(path)
      Dir.children(path).sort
    rescue Errno::ENOENT
      []
    end

    def stringify_keys(value)
      value.to_h.transform_keys(&:to_s)
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |entry| canonicalize(entry) }
      else value
      end
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |result, (a, b)| result | (a ^ b) }.zero?
    end

    def within?(path, parent)
      expanded = File.expand_path(path)
      root = File.expand_path(parent)
      expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")
    end

    def outcome(lifecycle, ok, message, data: {}, mutation: "none")
      { "lifecycle" => lifecycle, "ok" => ok, "message" => message, "data" => data, "mutation" => mutation }
    end
  end
end
