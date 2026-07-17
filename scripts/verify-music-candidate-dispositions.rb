#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/music_candidate_disposition_service"
require_relative "../lib/soul_core/application_facade"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

class DispositionAnalysisFixture
  def initialize(value) = (@value = value)
  def read(**) = @value
end

class DispositionFacadeFixture
  attr_reader :calls
  def initialize = (@calls = [])
  %i[reject_preview reject_execute export_preview export_execute].each do |method|
    define_method(method) do |**args|
      @calls << [method, args]
      { "ok" => true, "lifecycle_state" => method.to_s.end_with?("execute") ? "complete" : "blocked_for_human_review", "data" => {}, "mutation" => "none" }
    end
  end
end

def disposition_project
  {
    "title" => "Signal at Midnight", "intent" => "A restrained nocturnal torch song.",
    "target_duration_seconds" => 30, "vocal_mode" => "vocal", "rights_status" => "original",
    "caption" => "Noir trip-hop with close vocal and a clear opening pickup.",
    "lyrics" => "[Verse]\nA careful hand upon the table", "bpm" => 78,
    "keyscale" => "D minor", "timesignature" => "4", "language" => "en", "seed" => 1701
  }
end

def publish_fixture(store, project_id, candidate_id, input, source_candidate_id: nil)
  generations = store.generations_path(project_id)
  staging = File.join(generations, ".#{candidate_id}.fixture")
  Dir.mkdir(staging, 0o700)
  flac = "fixture lossless #{candidate_id}"
  mp3 = "fixture listening #{candidate_id}"
  File.write(File.join(staging, "master.flac"), flac, mode: "wx", perm: 0o600)
  File.write(File.join(staging, "listening.mp3"), mp3, mode: "wx", perm: 0o600)
  File.write(File.join(staging, "input.json"), JSON.pretty_generate(input) + "\n", mode: "wx", perm: 0o600)
  receipt = {
    "schema_version" => "soul.music.generation.v1", "project_id" => project_id,
    "candidate_id" => candidate_id, "source_candidate_id" => source_candidate_id,
    "generation_kind" => source_candidate_id ? "revision" : "initial",
    "artifacts" => {
      "flac" => { "sha256" => Digest::SHA256.hexdigest(flac), "path" => "master.flac" },
      "mp3" => { "sha256" => Digest::SHA256.hexdigest(mp3), "path" => "listening.mp3" }
    }
  }
  store.publish_candidate(project_id, candidate_id, staging, receipt)
  receipt
end

def review(disposition)
  {
    "rating" => disposition == "keep" ? 4 : 2, "disposition" => disposition,
    "musical_quality" => disposition == "keep" ? "passed" : "partial", "prompt_adherence" => "partial",
    "vocal_adherence" => "partial", "lyric_adherence" => disposition == "keep" ? "passed" : "failed",
    "notes" => disposition == "keep" ? "Ready for the finished library." : "Superseded by the linked revision."
  }
end

Dir.mktmpdir("soul-music-dispositions-") do |root|
  ids = %w[1111111111111111]
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { ids.shift || "ffffffffffffffff" }, clock: -> { Time.utc(2026, 7, 17, 23, 0, 0) })
  project = store.create(disposition_project)
  project_id = project.fetch("project_id")
  original_id = "candidate_2222222222222222"
  revision_id = "candidate_3333333333333333"
  original_input = store.input_payload(project)
  revised_input = original_input.merge("caption" => "Noir trip-hop with exposed first lines and sparse opening drums.", "bpm" => 76, "seed" => 1702)
  publish_fixture(store, project_id, original_id, original_input)
  publish_fixture(store, project_id, revision_id, revised_input, source_candidate_id: original_id)
  store.record_review(project_id: project_id, candidate_id: original_id, attributes: review("revise"))
  store.record_review(project_id: project_id, candidate_id: original_id, attributes: review("reject"))
  store.record_review(project_id: project_id, candidate_id: revision_id, attributes: review("keep"))

  analysis = {
    "schema_version" => "soul.music.candidate_analysis.v1", "project_id" => project_id,
    "candidate_id" => revision_id, "machine_route" => "human_listening_test",
    "machine_heard_formatted" => "A careful hand upon the table",
    "machine_heard_lyrics" => "A careful hand upon the table",
    "alignment" => { "sequence_recall" => 1.0, "problem_line_count" => 0 }
  }
  export_parent = File.join(root, "Music")
  export_root = File.join(export_parent, "soul-music")
  service = SoulCore::MusicCandidateDispositionService.new(
    root: root, export_root: export_root, export_parent: export_parent, project_store: store,
    analysis_service: DispositionAnalysisFixture.new(analysis), clock: -> { Time.utc(2026, 7, 17, 23, 5, 0) }
  )

  missing_analysis_service = SoulCore::MusicCandidateDispositionService.new(
    root: root, export_root: export_root, export_parent: export_parent, project_store: store,
    analysis_service: DispositionAnalysisFixture.new(nil), clock: -> { Time.utc(2026, 7, 17, 23, 5, 0) }
  )
  missing_analysis = missing_analysis_service.export_preview(project_id: project_id, candidate_id: revision_id)
  check.call("vocal keep cannot export before bounded transcription completes", missing_analysis["lifecycle_state"] == "awaiting_input" && !File.exist?(export_root))

  outside = Dir.mktmpdir("soul-music-export-outside-")
  FileUtils.mkdir_p(export_parent)
  linked_export = File.join(export_parent, "linked-library")
  File.symlink(outside, linked_export)
  linked_service = SoulCore::MusicCandidateDispositionService.new(
    root: root, export_root: linked_export, export_parent: export_parent, project_store: store,
    analysis_service: DispositionAnalysisFixture.new(analysis), clock: -> { Time.utc(2026, 7, 17, 23, 5, 0) }
  )
  linked_preview = linked_service.export_preview(project_id: project_id, candidate_id: revision_id)
  linked_result = linked_service.export_execute(project_id: project_id, candidate_id: revision_id, confirmation: "EXPORT_FINISHED_SONG", expected_digest: linked_preview.dig("data", "expected_digest"))
  check.call("symlinked finished-library path fails closed without external writes", linked_result["lifecycle_state"] == "blocked_for_human_review" && Dir.children(outside).empty?)
  File.unlink(linked_export)
  FileUtils.rm_rf(outside)

  reject_preview = service.reject_preview(project_id: project_id, candidate_id: original_id)
  wrong_reject = service.reject_execute(project_id: project_id, candidate_id: original_id, confirmation: "yes", expected_digest: reject_preview.dig("data", "expected_digest"))
  original_dir = File.join(store.generations_path(project_id), original_id)
  check.call("rejected candidate preview binds artifacts, review, and linked descendants", reject_preview["lifecycle_state"] == "blocked_for_human_review" && reject_preview.dig("data", "preview_scope", "descendant_candidate_ids") == [revision_id] && File.directory?(original_dir))
  check.call("wrong deletion confirmation preserves every candidate file", wrong_reject["lifecycle_state"] == "blocked_for_human_review" && File.directory?(original_dir))
  rejected = service.reject_execute(project_id: project_id, candidate_id: original_id, confirmation: "DELETE_REJECTED_CANDIDATE", expected_digest: reject_preview.dig("data", "expected_digest"))
  tombstone = File.join(store.project_path(project_id), "reviews", "rejected", "#{original_id}.json")
  history = Dir.glob(File.join(store.project_path(project_id), "reviews", "history", "#{original_id}.*.json"))
  check.call("confirmed rejection removes candidate media and current review", rejected["lifecycle_state"] == "complete" && !File.exist?(original_dir) && store.read_review(project_id, original_id).nil?)
  check.call("small rejection receipt preserves lineage but no audio or analysis", File.file?(tombstone) && JSON.parse(File.read(tombstone))["descendant_candidate_ids"] == [revision_id] && history.length == 1 && File.directory?(File.join(store.generations_path(project_id), revision_id)))

  export_preview = service.export_preview(project_id: project_id, candidate_id: revision_id)
  destination = export_preview.dig("data", "preview_scope", "destination")
  wrong_export = service.export_execute(project_id: project_id, candidate_id: revision_id, confirmation: "yes", expected_digest: export_preview.dig("data", "expected_digest"))
  check.call("finished export preview is exact and vocal-transcription gated", export_preview["lifecycle_state"] == "blocked_for_human_review" && export_preview.dig("data", "preview_scope", "files").include?("lyrics.txt") && !File.exist?(destination))
  check.call("wrong export confirmation writes nothing", wrong_export["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(destination))
  exported = service.export_execute(project_id: project_id, candidate_id: revision_id, confirmation: "EXPORT_FINISHED_SONG", expected_digest: export_preview.dig("data", "expected_digest"))
  metadata = JSON.parse(File.read(File.join(destination, "song.json")))
  check.call("kept revision exports FLAC MP3 metadata and machine-heard lyric sheet atomically", exported["lifecycle_state"] == "complete" && Dir.children(destination).sort == %w[listening.mp3 lyrics.txt master.flac song-info.md song.json] && File.read(File.join(destination, "lyrics.txt")).include?("careful hand"))
  check.call("finished metadata uses exact candidate values rather than original defaults", metadata["title"] == "Signal at Midnight" && metadata["intent"] == project["intent"] && metadata["bpm"] == 76 && metadata["key"] == "D minor" && metadata["time"] == "4" && metadata["seed"] == 1702)
  check.call("finished library remains owner-private", (File.stat(destination).mode & 0o777) == 0o700 && Dir.children(destination).all? { |name| (File.stat(File.join(destination, name)).mode & 0o777) == 0o600 })
  replay = service.export_preview(project_id: project_id, candidate_id: revision_id)
  check.call("finished export is idempotent and never overwrites", replay["lifecycle_state"] == "complete" && replay.dig("data", "idempotent_replay") == true)

  instrumental = store.create(disposition_project.merge(
    "title" => "Instrumental Signal", "vocal_mode" => "instrumental", "lyrics" => "",
    "caption" => "Slow cinematic instrumental with no vocals.", "seed" => 1800
  ))
  instrumental_id = "candidate_4444444444444444"
  publish_fixture(store, instrumental.fetch("project_id"), instrumental_id, store.input_payload(instrumental))
  store.record_review(project_id: instrumental.fetch("project_id"), candidate_id: instrumental_id, attributes: review("keep").merge("vocal_adherence" => "not_applicable", "lyric_adherence" => "not_applicable"))
  instrumental_service = SoulCore::MusicCandidateDispositionService.new(
    root: root, export_root: export_root, export_parent: export_parent, project_store: store,
    analysis_service: DispositionAnalysisFixture.new(nil), clock: -> { Time.utc(2026, 7, 17, 23, 6, 0) }
  )
  instrumental_preview = instrumental_service.export_preview(project_id: instrumental.fetch("project_id"), candidate_id: instrumental_id)
  instrumental_export = instrumental_service.export_execute(project_id: instrumental.fetch("project_id"), candidate_id: instrumental_id, confirmation: "EXPORT_FINISHED_SONG", expected_digest: instrumental_preview.dig("data", "expected_digest"))
  instrumental_destination = instrumental_export.dig("data", "export", "destination")
  check.call("instrumental keep exports without inventing a transcription file", instrumental_export["lifecycle_state"] == "complete" && Dir.children(instrumental_destination).sort == %w[listening.mp3 master.flac song-info.md song.json])
end

facade_fixture = DispositionFacadeFixture.new
facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, music_candidate_disposition_service: facade_fixture)
call = lambda do |operation, parameters|
  facade.call({ "schema_version" => "soul.application.v1", "request_id" => "disposition-#{operation}", "operation" => operation, "parameters" => parameters, "context" => { "interface" => "dashboard" } })
end
base = { "project_id" => "music_1111111111111111", "candidate_id" => "candidate_2222222222222222" }
reject_api = call.call("music.candidates.reject.preview", base)
export_api = call.call("music.candidates.export.execute", base.merge("confirmation" => "EXPORT_FINISHED_SONG", "expected_digest" => "a" * 64))
check.call("application allowlist dispatches disposition preview and exact execution", reject_api["lifecycle_state"] == "blocked_for_human_review" && export_api["lifecycle_state"] == "complete" && facade_fixture.calls.map(&:first) == %i[reject_preview export_execute])

dashboard = File.read(File.join(__dir__, "..", "assets", "dashboard", "dashboard.js"))
check.call("dashboard collapses linked revisions and exposes no automatic disposition", dashboard.include?("older version") && dashboard.include?("music.candidates.${kind}.preview") && dashboard.include?("music.candidates.${kind}.execute") && !dashboard.match?(/setInterval|setTimeout/))

abort "#{failures.length} music disposition verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Music candidate disposition deterministic verification passed."
