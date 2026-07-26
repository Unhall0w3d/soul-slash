# frozen_string_literal: true

require "base64"
require "fileutils"
require "tmpdir"
require_relative "bounded_command_runner"
require_relative "music_project_store"
require_relative "picture_understanding_service"
require_relative "visual_studio_service"

module SoulCore
  class ConversationCreativeArchiveService
    MAX_PROJECTS = 200
    MAX_CANDIDATES = 24
    MAX_LYRICS_BYTES = 12_000
    FRAME_TIMEOUT_SECONDS = 30

    def initialize(root: Dir.pwd, visual_studio: nil, music_store: nil, vision_client: nil, runner: nil)
      @root = File.expand_path(root)
      @visual_studio = visual_studio || VisualStudioService.new(root: @root)
      @music_store = music_store || MusicProjectStore.new(root: @root)
      @vision_client = vision_client || LocalVisionClient.new(root: @root)
      @runner = runner || BoundedCommandRunner.new
    end

    def inspect(message:)
      text = message.to_s.strip
      raise ArgumentError, "creative archive request is required" if text.empty?

      inventory = project_inventory
      matches = resolve_projects(text, inventory)
      return catalog_result(inventory, text) if matches.empty? && catalog_request?(text)
      return missing_result(text, inventory) if matches.empty?
      return ambiguous_result(matches) if matches.length > 1

      match = matches.first
      match.fetch("kind") == "visual" ? inspect_visual(match.fetch("project"), text) : inspect_music(match.fetch("project"))
    rescue ArgumentError => error
      result(false, "awaiting_input", error.message, {}, claims: [], not_collected: ["creative archive evidence"])
    rescue StandardError => error
      result(false, "failed", "creative archive inspection failed safely: #{error.class}", {}, claims: [], not_collected: ["creative archive evidence"])
    end

    private

    def project_inventory
      visual_outcome = @visual_studio.list(limit: MAX_PROJECTS)
      visuals = visual_outcome.dig("data", "projects") || []
      music = @music_store.list(limit: MAX_PROJECTS)
      {
        "visual" => visuals.map { |project| { "kind" => "visual", "project" => project } },
        "music" => music.map { |project| { "kind" => "music", "project" => project } }
      }
    end

    def resolve_projects(text, inventory)
      normalized_message = normalize(text)
      explicit_ids = text.scan(/(?:visual_project|music)_[a-f0-9]{16}/)
      records = inventory.values.flatten
      id_matches = records.select { |item| explicit_ids.include?(project_id(item)) }
      return id_matches unless id_matches.empty?

      kind = preferred_kind(text)
      records = inventory.fetch(kind) if kind
      title_matches = records.select do |item|
        title = normalize(item.dig("project", "title"))
        !title.empty? && normalized_message.include?(title)
      end
      longest = title_matches.map { |item| normalize(item.dig("project", "title")).length }.max
      longest ? title_matches.select { |item| normalize(item.dig("project", "title")).length == longest } : []
    end

    def preferred_kind(text)
      return "visual" if text.match?(/\b(?:visual|image|picture|scene|motion|video)\b/i)
      return "music" if text.match?(/\b(?:music|song|composition|audio)\b/i)

      nil
    end

    def catalog_request?(text)
      text.match?(/\b(?:list|show|what|which)\b.{0,50}\b(?:visual|music|creative|studio)\b.{0,30}\b(?:projects?|briefs?|compositions?)\b/i) &&
        !text.match?(/(?:visual_project|music)_[a-f0-9]{16}/)
    end

    def catalog_result(inventory, text)
      kind = preferred_kind(text)
      selected = kind ? inventory.fetch(kind) : inventory.values.flatten
      projects = selected.first(MAX_PROJECTS).map do |item|
        project = item.fetch("project")
        { "kind" => item.fetch("kind"), "project_id" => project_id(item), "title" => project["title"], "updated_at" => project["updated_at"] }
      end
      result(
        true, "complete", "creative projects listed",
        { "mode" => "catalog", "projects" => projects, "count" => projects.length },
        claims: ["Soul inspected #{projects.length} local #{kind || 'creative'} project records."],
        not_collected: []
      )
    end

    def inspect_visual(project, text)
      inspected = @visual_studio.inspect(project_id: project.fetch("project_id"))
      raise RuntimeError, inspected["reason"] unless inspected["ok"]

      record = inspected.dig("data", "project")
      data = {
        "mode" => "visual_project",
        "project" => compact_visual_project(record)
      }
      claims = [
        "Visual project #{record.fetch('title')} was resolved from Soul's local Visual Studio archive.",
        "The project has #{Array(record['candidates']).length} still candidates and #{Array(record['motions']).length} motion candidates."
      ]
      not_collected = []

      if visual_evidence_requested?(text)
        evidence = inspect_visual_evidence(record, text)
        data["visual_evidence"] = evidence
        claims << evidence.fetch("observation")
      else
        not_collected << "candidate pixels were not inspected because this request asked only for archive or brief context"
      end

      result(true, "complete", "visual project inspected", data, claims: claims, not_collected: not_collected)
    end

    def inspect_music(project)
      record = @music_store.read(project.fetch("project_id"))
      lyrics = record.fetch("lyrics").to_s
      lyrics_excerpt = lyrics.byteslice(0, MAX_LYRICS_BYTES).to_s
      data = {
        "mode" => "music_project",
        "project" => record.slice(
          "project_id", "title", "intent", "target_duration_seconds", "vocal_mode",
          "rights_status", "caption", "bpm", "keyscale", "timesignature", "language",
          "seed", "created_at", "updated_at"
        ).merge(
          "lyrics" => lyrics_excerpt,
          "lyrics_truncated" => lyrics.bytesize > lyrics_excerpt.bytesize
        )
      }
      result(
        true, "complete", "music project inspected", data,
        claims: ["Music project #{record.fetch('title')} was resolved from Soul's local Music Studio archive."],
        not_collected: ["audio content was not analyzed"]
      )
    end

    def inspect_visual_evidence(project, message)
      selected = select_visual_asset(project)
      raise ArgumentError, "visual project has no generated candidate to inspect" unless selected

      readiness = @vision_client.status
      raise ArgumentError, readiness.fetch("reason") unless readiness["ready"]

      if selected.fetch("kind") == "still"
        path = @visual_studio.artifact_path(
          project_id: project.fetch("project_id"), candidate_id: selected.fetch("candidate_id")
        )
      else
        path, temporary_directory = extract_motion_contact_sheet(project.fetch("project_id"), selected)
      end
      bytes = File.binread(path)
      prompt = visual_prompt(project, selected, message)
      observation = @vision_client.analyze(
        question: prompt,
        image_base64: Base64.strict_encode64(bytes),
        media_type: "image/png",
        timeout_seconds: PictureUnderstandingService::TIMEOUT_SECONDS
      )
      {
        "source_kind" => selected.fetch("kind"),
        "candidate_id" => selected.fetch("candidate_id"),
        "created_at" => selected["created_at"],
        "review" => selected["review"],
        "sample" => selected.fetch("kind") == "motion" ? "three chronological frames from the existing motion artifact" : "existing still candidate",
        "observation" => observation.fetch("content"),
        "provider_id" => observation.fetch("provider_id"),
        "model" => observation.fetch("model"),
        "latency_ms" => observation.fetch("latency_ms"),
        "authority" => "untrusted_evidence_only",
        "source_pixels_persisted_by_inspection" => false
      }
    ensure
      FileUtils.remove_entry_secure(temporary_directory) if defined?(temporary_directory) && temporary_directory && File.directory?(temporary_directory)
    end

    def select_visual_asset(project)
      stills = Array(project["candidates"]).map do |candidate|
        { "kind" => "still", "candidate_id" => candidate["candidate_id"], "created_at" => candidate["created_at"], "review" => candidate["review"] }
      end
      motions = Array(project["motions"]).map do |candidate|
        { "kind" => "motion", "candidate_id" => candidate["motion_candidate_id"], "created_at" => candidate["created_at"], "review" => candidate["review"], "duration_seconds" => candidate["duration_seconds"] }
      end
      (stills + motions).max_by { |candidate| [candidate["created_at"].to_s, candidate.fetch("candidate_id")] }
    end

    def extract_motion_contact_sheet(project_id, selected)
      completed = false
      ffmpeg = @runner.which("ffmpeg")
      raise ArgumentError, "ffmpeg is required to inspect an existing motion candidate" unless ffmpeg

      private_root = File.join(@root, "Soul", "private", "creative-inspection")
      FileUtils.mkdir_p(private_root, mode: 0o700)
      File.chmod(0o700, private_root)
      temp_directory = Dir.mktmpdir("frames-", private_root)
      File.chmod(0o700, temp_directory)
      output = File.join(temp_directory, "contact-sheet.png")
      source = @visual_studio.motion_artifact_path(project_id: project_id, motion_id: selected.fetch("candidate_id"))
      duration = Float(selected["duration_seconds"] || 4.0)
      duration = 4.0 unless duration.positive? && duration <= 60.0
      filter = "fps=3/#{duration},scale=416:-2,tile=3x1"
      command = @runner.run(
        ffmpeg, "-hide_banner", "-loglevel", "error", "-i", source,
        "-vf", filter, "-frames:v", "1", "-y", output,
        timeout_seconds: FRAME_TIMEOUT_SECONDS, max_output_bytes: 32 * 1024
      )
      raise RuntimeError, "motion frame extraction #{command.status}" unless command.success? && File.file?(output) && File.size(output).positive?

      completed = true
      [output, temp_directory]
    ensure
      FileUtils.remove_entry_secure(temp_directory) if !completed && defined?(temp_directory) && temp_directory && File.directory?(temp_directory)
    end

    def visual_prompt(project, selected, message)
      [
        "Operator request: #{message}",
        "Compare the selected existing candidate with its exact Visual Studio brief.",
        "Title: #{project['title']}",
        "Intent: #{project['intent']}",
        "Prompt: #{project['prompt']}",
        "Negative prompt: #{project['negative_prompt']}",
        "Aspect ratio: #{project['aspect_ratio']}",
        ("The supplied image is a three-frame chronological contact sheet from an existing motion candidate." if selected.fetch("kind") == "motion"),
        "Identify visible matches, absent requested elements, and contradictions. Do not infer invisible details or claim to have watched unsupplied frames."
      ].compact.join("\n")
    end

    def compact_visual_project(project)
      project.slice(
        "project_id", "title", "intent", "prompt", "negative_prompt",
        "aspect_ratio", "seed", "created_at", "updated_at"
      ).merge(
        "candidates" => Array(project["candidates"]).first(MAX_CANDIDATES).map { |item| compact_candidate(item, "candidate_id") },
        "motions" => Array(project["motions"]).first(MAX_CANDIDATES).map { |item| compact_candidate(item, "motion_candidate_id") }
      )
    end

    def compact_candidate(candidate, id_key)
      candidate.slice(id_key, "generation_kind", "instruction", "created_at", "duration_seconds", "width", "height", "fps", "review")
    end

    def visual_evidence_requested?(text)
      text.match?(/\b(?:compare|inspect|analy[sz]e|describe|review|evaluate|look at|see)\b/i) &&
        text.match?(/\b(?:image|picture|visual|candidate|render|thumbnail|video|motion|scene|brief)\b/i)
    end

    def missing_result(text, inventory)
      suggestions = inventory.values.flatten.map { |item| item.dig("project", "title") }.compact.select do |title|
        overlap = normalize(title).split & normalize(text).split
        overlap.length >= 2
      end.first(8)
      result(
        false, "awaiting_input", "no exact local creative project title was resolved",
        { "suggestions" => suggestions },
        claims: [], not_collected: ["creative project brief", "candidate artifacts"]
      )
    end

    def ambiguous_result(matches)
      choices = matches.first(12).map { |item| { "kind" => item.fetch("kind"), "project_id" => project_id(item), "title" => item.dig("project", "title") } }
      result(
        false, "awaiting_input", "creative project reference is ambiguous",
        { "matches" => choices },
        claims: [], not_collected: ["candidate artifacts"]
      )
    end

    def result(ok, lifecycle, reason, data, claims:, not_collected:)
      {
        "ok" => ok,
        "lifecycle_state" => lifecycle,
        "reason" => reason,
        "scope" => "Bounded read-only local Music Studio and Visual Studio project records and explicitly requested existing visual evidence",
        "assessment" => "creative_archive",
        "source_kind" => "local_creative_archive",
        "collected" => { "creative_archive" => data },
        "claims" => claims,
        "not_collected" => not_collected,
        "verification" => {
          "read_only" => true,
          "no_generation_started" => true,
          "no_project_or_candidate_modified" => true,
          "no_core_change_requested" => true,
          "temporary_derived_frames_removed" => true
        }
      }
    end

    def project_id(item)
      item.dig("project", "project_id")
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^\p{Alnum}]+/u, " ").strip.gsub(/\s+/, " ")
    end
  end
end
