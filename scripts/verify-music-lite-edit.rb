#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/soul_core/music_candidate_trim_service"
require_relative "../lib/soul_core/application_facade"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

def project_attributes
  {
    "title" => "Tail Signal", "intent" => "A bounded trim fixture.",
    "target_duration_seconds" => 30, "vocal_mode" => "instrumental", "rights_status" => "original",
    "caption" => "Progressive electronic rock with an intentionally quiet tail.", "lyrics" => "",
    "bpm" => 110, "keyscale" => "D minor", "timesignature" => "4", "language" => "en", "seed" => 1701
  }
end

class TrimFacadeFixture
  attr_reader :calls
  def initialize = (@calls = [])
  def preview(**args) = (@calls << [:preview, args]; { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => {} })
  def execute(**args) = (@calls << [:execute, args]; { "ok" => true, "lifecycle_state" => "complete", "data" => {} })
end

Dir.mktmpdir("soul-music-lite-edit-") do |root|
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1111111111111111" }, clock: -> { Time.utc(2026, 7, 18, 12, 0, 0) })
  project = store.create(project_attributes)
  project_id = project.fetch("project_id")
  candidate_id = "candidate_2222222222222222"
  generations = store.generations_path(project_id)
  staging = File.join(generations, ".fixture")
  Dir.mkdir(staging, 0o700)
  source = File.join(staging, "master.flac")
  _stdout, stderr, status = Open3.capture3("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-c:a", "flac", source)
  raise "fixture audio failed: #{stderr}" unless status.success?
  FileUtils.copy_file(source, File.join(staging, "listening.mp3"))
  input = store.input_payload(project)
  File.write(File.join(staging, "input.json"), JSON.pretty_generate(input) + "\n", mode: "wx", perm: 0o600)
  receipt = {
    "schema_version" => "soul.music.generation.v1", "project_id" => project_id, "candidate_id" => candidate_id,
    "generation_kind" => "initial", "source_candidate_id" => nil,
    "artifacts" => {
      "flac" => { "sha256" => Digest::SHA256.file(source).hexdigest, "path" => "master.flac" },
      "mp3" => { "sha256" => Digest::SHA256.file(File.join(staging, "listening.mp3")).hexdigest, "path" => "listening.mp3" }
    }
  }
  store.publish_candidate(project_id, candidate_id, staging, receipt)
  review = { "rating" => 4, "disposition" => "keep", "musical_quality" => "passed", "prompt_adherence" => "passed", "vocal_adherence" => "not_applicable", "lyric_adherence" => "not_applicable", "notes" => "Keep the original and clean its tail." }
  store.record_review(project_id: project_id, candidate_id: candidate_id, attributes: review)

  export_parent = File.join(root, "Music")
  export_root = File.join(export_parent, "soul-music")
  finished = File.join(export_root, "tail-signal")
  FileUtils.mkdir_p(finished, mode: 0o700)
  export_receipt = { "schema_version" => "soul.music.finished_export.v1", "project_id" => project_id, "candidate_id" => candidate_id, "destination" => finished, "scope_digest" => "a" * 64 }
  File.write(File.join(store.project_path(project_id), "exports", "#{candidate_id}.json"), JSON.pretty_generate(export_receipt) + "\n", mode: "wx", perm: 0o600)

  service = SoulCore::MusicCandidateTrimService.new(root: root, export_root: export_root, export_parent: export_parent, project_store: store, clock: -> { Time.utc(2026, 7, 18, 12, 5, 0) })
  unchanged = service.preview(project_id: project_id, candidate_id: candidate_id, start_seconds: 0.0, end_seconds: 3.0)
  preview = service.preview(project_id: project_id, candidate_id: candidate_id, start_seconds: 0.2, end_seconds: 2.5)
  check.call("unchanged edges do not create a derivative", unchanged["lifecycle_state"] == "awaiting_input")
  check.call("preview binds immutable source, exact edges, result duration, and non-overwrite destination", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "preview_scope", "source_artifact") == "immutable candidate master.flac" && preview.dig("data", "preview_scope", "result_duration_seconds") == 2.3 && preview.dig("data", "preview_scope", "edit_of_edit") == false)
  destination = preview.dig("data", "preview_scope", "destination")
  wrong = service.execute(project_id: project_id, candidate_id: candidate_id, start_seconds: 0.2, end_seconds: 2.5, confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong confirmation writes no edit", wrong["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(destination))
  changed = service.execute(project_id: project_id, candidate_id: candidate_id, start_seconds: 0.2, end_seconds: 2.4, confirmation: "APPLY_MUSIC_TRIM", expected_digest: preview.dig("data", "expected_digest"))
  check.call("changed boundaries invalidate the exact preview", changed["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(destination))
  executed = service.execute(project_id: project_id, candidate_id: candidate_id, start_seconds: 0.2, end_seconds: 2.5, confirmation: "APPLY_MUSIC_TRIM", expected_digest: preview.dig("data", "expected_digest"))
  output = executed.dig("data", "trim")
  check.call("confirmed trim produces private FLAC MP3 and receipt without changing source", executed["lifecycle_state"] == "complete" && Dir.children(destination).sort == %w[edit.json listening.mp3 master.flac] && Digest::SHA256.file(store.candidate_artifact_path(project_id, candidate_id, "flac")).hexdigest == receipt.dig("artifacts", "flac", "sha256"))
  check.call("trim receipt records source-only lineage and verified output digests", output["source_sha256"] == receipt.dig("artifacts", "flac", "sha256") && output["internal_edits"] == false && output["output_digests"].all? { |name, sha| Digest::SHA256.file(File.join(destination, name)).hexdigest == sha })
  replay = service.preview(project_id: project_id, candidate_id: candidate_id, start_seconds: 0.2, end_seconds: 2.5)
  check.call("exact trim replay is idempotent", replay["lifecycle_state"] == "complete" && replay.dig("data", "idempotent_replay") == true)
end

fixture = TrimFacadeFixture.new
facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, music_candidate_trim_service: fixture)
request = lambda do |operation, parameters|
  facade.call({ "schema_version" => "soul.application.v1", "request_id" => "trim-fixture-1234", "operation" => operation, "parameters" => parameters, "context" => { "interface" => "dashboard_test" } })
end
base = { "project_id" => "music_1111111111111111", "candidate_id" => "candidate_2222222222222222", "start_seconds" => 0.2, "end_seconds" => 2.5 }
request.call("music.candidates.trim.preview", base)
request.call("music.candidates.trim.execute", base.merge("confirmation" => "APPLY_MUSIC_TRIM", "expected_digest" => "b" * 64))
check.call("application contract and facade expose preview and execute with numeric boundaries", fixture.calls.map(&:first) == %i[preview execute])

dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
styles = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
check.call("dashboard defers waveform decoding until requested and exposes no edit chaining", dashboard.include?("Open trim controls") && dashboard.include?("decodeAudioData") && dashboard.include?("music.candidates.trim.preview") && dashboard.include?("immutable original") && styles.include?(".music-trim"))

abort "Music Lite Edit verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music Lite Edit deterministic verification passed."
