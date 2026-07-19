# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "music_project_store"
require_relative "music_visual_companion_service"

module SoulCore
  class MusicPublicationPackageService
    CONFIRMATION = "EXPORT_YOUTUBE_PACKAGE"
    MAX_DESCRIPTION = 5_000
    MAX_RECORD_BYTES = 8 * 1024 * 1024

    def initialize(root: Dir.pwd, export_root: File.join(Dir.home, "Music", "soul-music"), project_store: nil, visual_service: nil, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @export_root = File.expand_path(export_root)
      @store = project_store || MusicProjectStore.new(root: @root)
      @visuals = visual_service || MusicVisualCompanionService.new(root: @root, project_store: @store)
      @clock = clock
    end

    def draft(project_id:, candidate_id:, visual_id:)
      context = publication_context(project_id, candidate_id, visual_id)
      outcome("complete", true, "YouTube package description drafted for human review", data: {
        "title" => context.fetch("project").fetch("title"),
        "description" => description_for(context),
        "description_editable" => true,
        "publication_performed" => false,
        "api_upload_performed" => false
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def preview(project_id:, candidate_id:, visual_id:, description:)
      context = publication_context(project_id, candidate_id, visual_id)
      text = validate_description(description)
      scope = package_scope(context, text)
      existing = existing_package(scope)
      return outcome("complete", true, "YouTube upload package already exists", data: { "package" => existing, "idempotent_replay" => true }) if existing
      destination = scope.fetch("destination")
      return outcome("blocked_for_human_review", false, "YouTube package destination already exists; Soul will not overwrite it") if File.exist?(destination) || File.symlink?(destination)
      outcome("blocked_for_human_review", true, "exact local YouTube package export requires approval", data: {
        "confirmation_phrase" => CONFIRMATION,
        "expected_digest" => digest(scope),
        "preview_scope" => scope
      })
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def execute(project_id:, candidate_id:, visual_id:, description:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      context = publication_context(project_id, candidate_id, visual_id)
      text = validate_description(description)
      scope = package_scope(context, text)
      return outcome("blocked_for_human_review", false, "exact YouTube package confirmation did not match") unless confirmation == CONFIRMATION
      return outcome("blocked_for_human_review", false, "YouTube package scope changed; preview again") unless secure_compare(expected_digest, digest(scope))
      existing = existing_package(scope)
      return outcome("complete", true, "YouTube upload package already exists", data: { "package" => existing, "idempotent_replay" => true }) if existing

      destination = scope.fetch("destination")
      raise MusicProjectStore::IntegrityError, "YouTube package destination already exists" if File.exist?(destination) || File.symlink?(destination)
      export_destination = context.fetch("export_destination")
      staging = File.join(export_destination, ".youtube.partial-#{SecureRandom.hex(6)}")
      Dir.mkdir(staging, 0o700)
      video = @visuals.artifact_path(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, artifact: "preview")
      thumbnail = @visuals.artifact_path(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, artifact: "base")
      copy_verified(video, File.join(staging, "video.mp4"), scope.fetch("video_sha256"))
      copy_verified(thumbnail, File.join(staging, "thumbnail.png"), scope.fetch("thumbnail_sha256"))
      write_private(File.join(staging, "youtube-description.txt"), text.end_with?("\n") ? text : "#{text}\n")
      upload = {
        "schema_version" => "soul.music.youtube_upload.v1",
        "title" => context.fetch("project").fetch("title"),
        "description_file" => "youtube-description.txt",
        "video_file" => "video.mp4",
        "thumbnail_file" => "thumbnail.png",
        "category_id" => "10",
        "privacy_status" => "private",
        "made_for_kids" => false,
        "contains_synthetic_media" => true,
        "api_upload_performed" => false,
        "human_publication_required" => true
      }
      write_json(File.join(staging, "upload.json"), upload)
      File.rename(staging, destination)
      receipt = {
        "schema_version" => "soul.music.youtube_package.v1",
        "project_id" => project_id,
        "candidate_id" => candidate_id,
        "visual_id" => visual_id,
        "destination" => destination,
        "exported_at" => @clock.call.iso8601,
        "scope_digest" => digest(scope),
        "files" => Dir.children(destination).sort.to_h { |name| [name, Digest::SHA256.file(File.join(destination, name)).hexdigest] },
        "api_upload_performed" => false,
        "external_publication" => false
      }
      receipt_path = package_receipt_path(project_id, candidate_id, visual_id)
      FileUtils.mkdir_p(File.dirname(receipt_path), mode: 0o700)
      write_json(receipt_path, receipt)
      outcome("complete", true, "local YouTube upload package exported; no upload or publication was performed", data: { "package" => receipt }, mutation: "youtube_upload_package_exported")
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    ensure
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging) && !File.symlink?(staging)
    end

    private

    def publication_context(project_id, candidate_id, visual_id)
      project = @store.read(project_id)
      input = @store.candidate_input(project_id, candidate_id)
      visual = @visuals.inventory(project_id: project_id, candidate_id: candidate_id).find { |item| item["visual_id"] == visual_id }
      raise MusicProjectStore::ValidationError, "visual companion does not exist for this exact candidate" unless visual
      raise MusicProjectStore::ValidationError, "render and review the full visual companion before packaging" unless visual["stage"] == "preview_ready" && visual.dig("artifacts", "preview")
      export = read_finished_export(project_id, candidate_id)
      {
        "project" => project,
        "input" => input,
        "visual" => visual,
        "export" => export,
        "export_destination" => export.fetch("destination")
      }
    end

    def read_finished_export(project_id, candidate_id)
      path = File.join(@store.project_path(project_id), "exports", "#{candidate_id}.json")
      raise MusicProjectStore::ValidationError, "record a keep review and export the finished song before packaging its video" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_RECORD_BYTES)
      receipt = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      destination = File.expand_path(receipt.fetch("destination"))
      raise MusicProjectStore::IntegrityError, "finished export destination is invalid" unless within?(destination, @export_root) && File.directory?(destination) && !File.symlink?(destination)
      required = %w[master.flac listening.mp3 song.json song-info.md]
      raise MusicProjectStore::IntegrityError, "finished export is incomplete" unless required.all? { |name| File.file?(File.join(destination, name)) && !File.symlink?(File.join(destination, name)) }
      receipt
    rescue JSON::ParserError
      raise MusicProjectStore::IntegrityError, "finished export receipt is invalid"
    end

    def description_for(context)
      project = context.fetch("project")
      input = context.fetch("input")
      genre = genre_influence(project.fetch("caption"))
      lines = ["#{genre} | #{project.fetch('intent')}", "", "BPM: #{input.fetch('bpm')}", "Key: #{input.fetch('keyscale')}", "Time: #{time_label(input.fetch('timesignature'))}"]
      lyrics = input.fetch("lyrics").to_s.strip
      lines.concat(["", lyrics]) unless lyrics.empty?
      lines.concat([
        "", "Created locally with generative models and human review.", "",
        "Soul/", "https://github.com/Unhall0w3d/soul-slash", "",
        "NOC Thoughts", "https://nocthoughts.com/", "",
        project.fetch("vocal_mode") == "vocal" ? "Music, Visual, Composition, and Lyrics created by Soul/." : "Music, Visual, and Composition created by Soul/."
      ])
      lines.join("\n")
    end

    def genre_influence(caption)
      first = caption.to_s.split(/[.!?]\s|\n/, 2).first.to_s.strip
      candidate = first.split(/\s+with\s+/i, 2).first.to_s.strip
      candidate = first if candidate.length < 4
      candidate.slice(0, 120)
    end

    def time_label(value)
      text = value.to_s.strip
      text.include?("/") ? text : "#{text}/4"
    end

    def package_scope(context, description)
      project = context.fetch("project")
      visual = context.fetch("visual")
      export_destination = context.fetch("export_destination")
      {
        "operation" => "export_youtube_upload_package",
        "project_id" => project.fetch("project_id"),
        "candidate_id" => visual.fetch("candidate_id"),
        "visual_id" => visual.fetch("visual_id"),
        "finished_export_scope_digest" => context.fetch("export").fetch("scope_digest"),
        "video_sha256" => visual.dig("artifacts", "preview", "sha256"),
        "thumbnail_sha256" => visual.dig("artifacts", "base", "sha256"),
        "description_sha256" => Digest::SHA256.hexdigest(description),
        "destination" => File.join(export_destination, "youtube"),
        "files" => %w[video.mp4 thumbnail.png youtube-description.txt upload.json],
        "privacy_status" => "private",
        "contains_synthetic_media" => true,
        "overwrite" => false,
        "api_upload_performed" => false,
        "external_publication" => false
      }
    end

    def validate_description(value)
      text = value.to_s.strip
      raise MusicProjectStore::ValidationError, "YouTube description must be 1..#{MAX_DESCRIPTION} characters" unless text.length.between?(1, MAX_DESCRIPTION)
      raise MusicProjectStore::ValidationError, "YouTube description contains invalid text" unless text.valid_encoding?
      text
    end

    def existing_package(scope)
      path = package_receipt_path(scope.fetch("project_id"), scope.fetch("candidate_id"), scope.fetch("visual_id"))
      return nil unless File.exist?(path)
      raise MusicProjectStore::IntegrityError, "YouTube package receipt is invalid" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, MAX_RECORD_BYTES)
      receipt = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      destination = receipt.fetch("destination")
      raise MusicProjectStore::IntegrityError, "YouTube package receipt scope changed" unless receipt["scope_digest"] == digest(scope) && destination == scope["destination"] && File.directory?(destination) && !File.symlink?(destination)
      receipt
    rescue JSON::ParserError
      raise MusicProjectStore::IntegrityError, "YouTube package receipt is invalid"
    end

    def package_receipt_path(project_id, candidate_id, visual_id) = File.join(@store.project_path(project_id), "publications", "#{candidate_id}-#{visual_id}.json")
    def copy_verified(source, destination, expected)
      raise MusicProjectStore::IntegrityError, "publication source digest is missing" unless expected.to_s.match?(/\A[a-f0-9]{64}\z/) && Digest::SHA256.file(source).hexdigest == expected
      FileUtils.copy_file(source, destination)
      File.chmod(0o600, destination)
      raise MusicProjectStore::IntegrityError, "publication copy digest changed" unless Digest::SHA256.file(destination).hexdigest == expected
    end
    def write_private(path, body) = File.write(path, body, mode: "wx", perm: 0o600)
    def write_json(path, value) = write_private(path, JSON.pretty_generate(value) + "\n")
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def within?(path, parent) = File.expand_path(path) == File.expand_path(parent) || File.expand_path(path).start_with?(File.expand_path(parent) + File::SEPARATOR)
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def outcome(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
