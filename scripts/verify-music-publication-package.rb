#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/music_publication_package_service"

class PublicationVisualFixture
  def initialize(record, base, preview)
    @record = record
    @paths = { "base" => base, "preview" => preview }
  end
  def inventory(project_id:, candidate_id:)
    @record.values_at("project_id", "candidate_id") == [project_id, candidate_id] ? [@record] : []
  end
  def artifact_path(project_id:, candidate_id:, visual_id:, artifact:)
    raise "identity mismatch" unless @record.values_at("project_id", "candidate_id", "visual_id") == [project_id, candidate_id, visual_id]
    @paths.fetch(artifact)
  end
end

PublicationResult = Struct.new(:status) do
  def success? = status == "ok"
end

class PublicationRunner
  attr_reader :commands
  def initialize = (@commands = [])
  def which(name) = "/usr/bin/#{name}"
  def run(*command, **_options)
    @commands << command
    File.binwrite(command.last, "derived thumbnail fixture")
    PublicationResult.new("ok")
  end
end

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

Dir.mktmpdir("soul-publication-package-") do |root|
  export_root = File.join(root, "Music", "soul-music")
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1" * 16 }, clock: -> { Time.utc(2026, 7, 19, 5) })
  project = store.create(
    "title" => "Afterimage Fixture", "intent" => "A luminous nocturnal current.", "target_duration_seconds" => 180,
    "vocal_mode" => "instrumental", "rights_status" => "original", "caption" => "Liquid drum and bass with warm sub-bass and restrained Rhodes chords.",
    "lyrics" => "", "bpm" => 174, "keyscale" => "F# minor", "timesignature" => "4", "language" => "en", "seed" => 42
  )
  project_id = project.fetch("project_id")
  candidate_id = "candidate_#{'2' * 16}"
  candidate_dir = File.join(store.generations_path(project_id), candidate_id)
  Dir.mkdir(candidate_dir, 0o700)
  File.write(File.join(candidate_dir, "input.json"), JSON.generate(store.input_payload(project)))

  destination = File.join(export_root, "afterimage-fixture")
  FileUtils.mkdir_p(destination)
  %w[master.flac listening.mp3 song.json song-info.md].each { |name| File.binwrite(File.join(destination, name), "fixture #{name}") }
  export_scope_digest = "a" * 64
  exports = File.join(store.project_path(project_id), "exports")
  FileUtils.mkdir_p(exports)
  File.write(File.join(exports, "#{candidate_id}.json"), JSON.generate({ "schema_version" => "soul.music.finished_export.v1", "project_id" => project_id, "candidate_id" => candidate_id, "destination" => destination, "scope_digest" => export_scope_digest }))

  visual_id = "visual_#{'3' * 16}"
  base = File.join(root, "base.png"); video = File.join(root, "preview.mp4")
  File.binwrite(base, "png publication fixture"); File.binwrite(video, "mp4 publication fixture")
  visual = {
    "project_id" => project_id, "candidate_id" => candidate_id, "visual_id" => visual_id, "stage" => "preview_ready",
    "artifacts" => { "base" => { "sha256" => Digest::SHA256.file(base).hexdigest }, "preview" => { "sha256" => Digest::SHA256.file(video).hexdigest } }
  }
  service = SoulCore::MusicPublicationPackageService.new(root: root, export_root: export_root, project_store: store, visual_service: PublicationVisualFixture.new(visual, base, video), clock: -> { Time.utc(2026, 7, 19, 5, 1) })

  draft = service.draft(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id)
  description = draft.dig("data", "description")
  check.call("instrumental description includes metadata links disclosure and truthful credit", draft["lifecycle_state"] == "complete" && description.start_with?("Liquid drum and bass | A luminous nocturnal current.") && description.include?("BPM: 174") && description.include?("https://github.com/Unhall0w3d/soul-slash") && description.include?("https://nocthoughts.com/") && description.include?("Created locally with generative models and human review.") && !description.include?("Lyrics created"))
  foreboding_genre = service.send(:genre_influence, "Funeral doom fused with dark ambient and restrained industrial noise: downtuned baritone guitars, sub-bass drones, distant floor toms, bowed metal, and low male bass vocals.")
  check.call("colon-delimited genre identity remains complete", foreboding_genre == "Funeral doom fused with dark ambient and restrained industrial noise")
  check.call("instrument-led captions retain their concise genre identity", service.send(:genre_influence, "Liquid drum and bass with warm sub-bass and restrained Rhodes chords.") == "Liquid drum and bass")

  preview = service.preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, description: description)
  wrong = service.execute(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, description: description, confirmation: "WRONG", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong exact gate creates no package", wrong["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(File.join(destination, "youtube")))

  complete = service.execute(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, description: description, confirmation: "EXPORT_YOUTUBE_PACKAGE", expected_digest: preview.dig("data", "expected_digest"))
  package = complete.dig("data", "package")
  upload = JSON.parse(File.binread(File.join(destination, "youtube", "upload.json")))
  check.call("exact package is atomic local and upload-ready", complete["lifecycle_state"] == "complete" && package["external_publication"] == false && %w[video.mp4 thumbnail.png youtube-description.txt upload.json].all? { |name| File.file?(File.join(destination, "youtube", name)) })
  check.call("upload metadata defaults to private human publication", upload.values_at("category_id", "privacy_status", "made_for_kids", "contains_synthetic_media", "api_upload_performed", "human_publication_required") == ["10", "private", false, true, false, true])
  replay = service.preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, description: description)
  check.call("identical package replay is idempotent", replay["lifecycle_state"] == "complete" && replay.dig("data", "idempotent_replay") == true)

  motion_destination = File.join(export_root, "afterimage-motion-fixture")
  FileUtils.mkdir_p(motion_destination)
  %w[master.flac listening.mp3 song.json song-info.md].each { |name| File.binwrite(File.join(motion_destination, name), "motion fixture #{name}") }
  File.write(File.join(exports, "#{candidate_id}.json"), JSON.generate({ "schema_version" => "soul.music.finished_export.v1", "project_id" => project_id, "candidate_id" => candidate_id, "destination" => motion_destination, "scope_digest" => "b" * 64 }))
  motion_visual_id = "visual_#{'4' * 16}"
  motion_visual = {
    "project_id" => project_id, "candidate_id" => candidate_id, "visual_id" => motion_visual_id,
    "source_kind" => "generated_motion", "stage" => "preview_ready",
    "artifacts" => { "preview" => { "sha256" => Digest::SHA256.file(video).hexdigest } }
  }
  motion_runner = PublicationRunner.new
  motion_service = SoulCore::MusicPublicationPackageService.new(
    root: root, export_root: export_root, project_store: store,
    visual_service: PublicationVisualFixture.new(motion_visual, nil, video), runner: motion_runner,
    clock: -> { Time.utc(2026, 7, 19, 5, 2) }
  )
  motion_preview = motion_service.preview(project_id: project_id, candidate_id: candidate_id, visual_id: motion_visual_id, description: description)
  motion_complete = motion_service.execute(project_id: project_id, candidate_id: candidate_id, visual_id: motion_visual_id, description: description, confirmation: "EXPORT_YOUTUBE_PACKAGE", expected_digest: motion_preview.dig("data", "expected_digest"))
  motion_thumbnail = File.join(motion_destination, "youtube", "thumbnail.png")
  check.call("generated motion package derives one deterministic thumbnail without requiring base.png", motion_preview.dig("data", "preview_scope", "thumbnail_derivation") == "reviewed-preview-frame-v1" && motion_complete["lifecycle_state"] == "complete" && File.file?(motion_thumbnail) && motion_runner.commands.one? && motion_runner.commands.first.each_cons(2).include?(["-ss", "1.0"]))
end

contract = File.binread(File.expand_path("../lib/soul_core/application_contract.rb", __dir__))
facade = File.binread(File.expand_path("../lib/soul_core/application_facade.rb", __dir__))
javascript = File.binread(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("application and dashboard expose draft preview execute gates", %w[music.publication.draft music.publication.preview music.publication.execute].all? { |operation| contract.include?(operation) && facade.include?(operation) && javascript.include?(operation) })
check.call("dashboard makes description editable before exact export", javascript.include?("youtube-description.txt") && javascript.include?("textarea.maxLength = 5000") && javascript.include?("Prepare YouTube upload package"))

abort "music publication package verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music publication package deterministic verification passed."
