#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/long_form_mix_service"
require_relative "../lib/soul_core/music_project_store"
require_relative "../lib/soul_core/application_facade"

failures = []
def check(failures, label, value)
  puts "- #{label}: #{value ? 'ok' : 'FAILED'}"
  failures << label unless value
end

module Fixture
  module_function

  def write_file(path, contents)
    File.write(path, contents, perm: 0o600)
  end

  def make_project(store, title, intent, seed)
    store.create(
      "title" => title,
      "intent" => intent,
      "target_duration_seconds" => 180,
      "vocal_mode" => "instrumental",
      "rights_status" => "original",
      "caption" => "Long-form mix fixture",
      "lyrics" => "",
      "bpm" => 128,
      "keyscale" => "C minor",
      "timesignature" => "4",
      "language" => "en",
      "seed" => seed
    )
  end

  def write_finished_candidate(store, project_id, candidate_id, export_root, duration, song_contents = nil)
    source_dir = File.join(export_root, candidate_id)
    FileUtils.mkdir_p(source_dir, mode: 0o700)

    master = "master.flac content #{candidate_id}"
    listen = "listening.mp3 content #{candidate_id}"
    song_info = "song-info.md content #{candidate_id}"
    song_json = {
      "schema_version" => "soul.music.finished_song.v1",
      "duration_seconds" => duration
    }

    write_file(File.join(source_dir, "master.flac"), master)
    write_file(File.join(source_dir, "listening.mp3"), listen)
    write_file(File.join(source_dir, "song-info.md"), song_info)
    write_file(File.join(source_dir, "song.json"), JSON.generate(song_json))

    candidate_dir = File.join(store.generations_path(project_id), candidate_id)
    FileUtils.mkdir_p(candidate_dir, mode: 0o700)
    write_file(File.join(candidate_dir, "candidate.json"), JSON.generate({ "schema_version" => "soul.music.generation.v1" }))

    export = {
      "schema_version" => "soul.music.finished_export.v1",
      "project_id" => project_id,
      "candidate_id" => candidate_id,
      "destination" => source_dir,
      "scope_digest" => "a" * 64,
      "files" => {
        "master.flac" => Digest::SHA256.file(File.join(source_dir, "master.flac")).hexdigest,
        "listening.mp3" => Digest::SHA256.file(File.join(source_dir, "listening.mp3")).hexdigest,
        "song.json" => Digest::SHA256.file(File.join(source_dir, "song.json")).hexdigest,
        "song-info.md" => Digest::SHA256.file(File.join(source_dir, "song-info.md")).hexdigest
      },
      "exported_at" => "2026-07-30T20:00:00Z"
    }
    exports_dir = File.join(store.project_path(project_id), "exports")
    FileUtils.mkdir_p(exports_dir, mode: 0o700)
    write_file(File.join(exports_dir, "#{candidate_id}.json"), JSON.generate(export))

    store.record_review(
      project_id: project_id,
      candidate_id: candidate_id,
      attributes: {
        "rating" => 5,
        "disposition" => "keep",
        "musical_quality" => "passed",
        "prompt_adherence" => "passed",
        "vocal_adherence" => "not_applicable",
        "lyric_adherence" => "not_applicable",
        "notes" => "Keep this candidate for mix handoff."
      }
    )
  end
end

Dir.mktmpdir("soul-long-form-mix-a0-") do |root|
  store = SoulCore::MusicProjectStore.new(
    root: root,
    id_generator: -> { "beefbeefbeefbeef" }
  )
  project = Fixture.make_project(store, "Long-form Mix Fixture", "Measured longer-form sequence fixture.", 31)
  project_id = project.fetch("project_id")

  export_root = File.join(root, "Music", "soul-music")
  handoff_root = File.join(root, "Music", "soul-music", "mixes")

  Fixture.write_finished_candidate(store, project_id, "candidate_1111111111111111", export_root, 9.4)
  Fixture.write_finished_candidate(store, project_id, "candidate_2222222222222222", export_root, 8.1)

  clock_tick = 0
  service = SoulCore::LongFormMixService.new(
    root: root,
    export_root: export_root,
    export_parent: File.join(root, "Music"),
    project_store: store,
    handoff_root: handoff_root,
    plans_root: File.join(root, "Soul", "private", "mix_projects"),
    clock: -> { clock_tick += 1; Time.utc(2026, 7, 30, 20, 0, 0) + clock_tick }
  )

  source_id_1 = "#{project_id}/candidate_1111111111111111"
  source_id_2 = "#{project_id}/candidate_2222222222222222"

  sources = service.sources(limit: 10).dig("data", "sources")
  check(failures, "sources includes two finished keep-reviewed exports", sources.length == 2)
  check(failures, "source list includes expected source ids", sources.map { |record| record.fetch("source_id") }.sort == [source_id_1, source_id_2].sort)

  sequence = [
    {
      "project_id" => project_id,
      "candidate_id" => "candidate_1111111111111111",
      "trim_start_seconds" => 0.0,
      "trim_end_seconds" => 9.0,
      "crossfade_seconds" => 0.0,
      "transition_note" => "Intro lead"
    },
    {
      "project_id" => project_id,
      "candidate_id" => "candidate_2222222222222222",
      "trim_start_seconds" => 1.0,
      "trim_end_seconds" => 7.0,
      "crossfade_seconds" => 0.5,
      "transition_note" => "Bridge overlap"
    }
  ]

  create_payload = {
    "title" => "Verified Mix",
    "intent" => "Deterministic handoff test.",
    "sequence" => sequence
  }

  created = service.create(plan: create_payload)
  check(failures, "create returns a mix", created.fetch("lifecycle_state") == "complete" && created.dig("data", "mix").is_a?(Hash))
  mix_id = created.dig("data", "mix", "mix_id")

  replay = service.create(plan: create_payload)
  check(failures, "create is idempotent for same payload", replay.dig("data", "idempotent_replay") == true)

  listing = service.list(limit: 10).dig("data", "mixes")
  check(failures, "list contains created mix", listing.any? { |entry| entry.fetch("mix_id") == mix_id })

  read = service.get(mix_id: mix_id)
  check(failures, "get returns same mix id", read.dig("data", "mix", "mix_id") == mix_id)

  invalid = service.create(plan: {
    "title" => "Invalid Mix",
    "intent" => "Invalid crossfade test.",
    "sequence" => sequence.map { |entry| entry.merge("crossfade_seconds" => 12.0) }
  })
  check(failures, "invalid sequence is blocked", invalid.fetch("lifecycle_state") == "awaiting_input")

  preview = service.handoff_preview(mix_id: mix_id)
  check(failures, "handoff preview requires confirmation", preview.fetch("lifecycle_state") == "blocked_for_human_review")
  check(failures, "handoff preview exposes exact phrase", preview.dig("data", "confirmation_phrase") == "EXPORT_MIX_HANDOFF")
  expected = preview.dig("data", "expected_digest")

  wrong = service.handoff_execute(mix_id: mix_id, confirmation: "WRONG", expected_digest: expected)
  check(failures, "wrong confirmation is blocked", wrong.fetch("lifecycle_state") == "blocked_for_human_review")

  first_master = File.join(export_root, "candidate_1111111111111111", "master.flac")
  Fixture.write_file(first_master, "changed after preview")
  changed_after_preview = service.handoff_execute(mix_id: mix_id, confirmation: "EXPORT_MIX_HANDOFF", expected_digest: expected)
  check(failures, "source drift after preview blocks execution", changed_after_preview.fetch("lifecycle_state") == "blocked_for_human_review")
  Fixture.write_file(first_master, "master.flac content candidate_1111111111111111")

  prepared = service.handoff_execute(mix_id: mix_id, confirmation: "EXPORT_MIX_HANDOFF", expected_digest: expected)
  check(failures, "handoff execute creates package", prepared.fetch("lifecycle_state") == "complete")
  package = prepared.dig("data", "package")
  destination = package.fetch("destination")
  check(failures, "package destination exists", File.directory?(destination))
  expected_files = ["mix.edl.json", "cue-sheet.csv", "README.md", "checksums.sha256"]
  expected_source_files = Array(package.fetch("files"))
  expected_payload_files = expected_source_files - ["checksums.sha256"]
  check(failures, "package includes required manifest files", expected_files.all? { |name| File.file?(File.join(destination, name)) })
  check(failures, "package includes all files from preview scope", expected_payload_files.all? { |name| File.file?(File.join(destination, name)) })

  readme = File.read(File.join(destination, "README.md")).downcase
  check(failures, "package README is stereo-aware", readme.include?("stereo-source"))
  check(failures, "package README states no native DAW project", readme.include?("separated stems") && readme.include?("fl studio"))

  manifest = JSON.parse(File.read(File.join(destination, "mix.edl.json")))
  check(failures, "manifest scope digest matches preview", manifest.fetch("scope_digest") == expected)
  check(failures, "manifest source_count is stable", manifest.fetch("source_count") == 2)

  checksums = package.fetch("checksums")
  check(failures, "checksum manifest is complete", checksums.keys.include?("README.md") &&
    checksums.keys.include?("mix.edl.json") &&
    checksums.keys.include?("cue-sheet.csv") &&
    expected_payload_files.include?("README.md") &&
    expected_payload_files.include?("mix.edl.json") &&
    expected_payload_files.include?("cue-sheet.csv") &&
    expected_payload_files.all? { |name| checksums.key?(name) && checksums.fetch(name) })
  checksums.each do |name, expected_value|
    actual_value = Digest::SHA256.file(File.join(destination, name)).hexdigest
    check(failures, "checksum matches for #{name}", actual_value == expected_value)
  end

  cue_lines = File.readlines(File.join(destination, "cue-sheet.csv"), chomp: true)
  check(failures, "cue sheet includes one row per source", cue_lines.length == 3)
  check(failures, "cue sheet rows contain track IDs", cue_lines.any? { |line| line.include?(source_id_1) } && cue_lines.any? { |line| line.include?(source_id_2) })

  replayed = service.handoff_execute(mix_id: mix_id, confirmation: "EXPORT_MIX_HANDOFF", expected_digest: expected)
  check(failures, "handoff execute is idempotent", replayed.dig("data", "idempotent_replay") == true)

  checksum_path = File.join(destination, "checksums.sha256")
  checksum_body = File.readlines(checksum_path).reject { |line| line.include?("README.md") }.join
  Fixture.write_file(checksum_path, checksum_body)
  incomplete_manifest = service.handoff_preview(mix_id: mix_id)
  check(failures, "incomplete package checksum inventory is blocked", incomplete_manifest.fetch("lifecycle_state") == "blocked_for_human_review")

  source_dir = File.join(export_root, "candidate_1111111111111111")
  export = JSON.parse(File.read(File.join(store.project_path(project_id), "exports", "candidate_1111111111111111.json")))
  export["files"]["master.flac"] = "bad"
  Fixture.write_file(File.join(store.project_path(project_id), "exports", "candidate_1111111111111111.json"), JSON.generate(export))

  drift = service.sources(limit: 10)
  check(failures, "drifted source blocks inventory for human review", drift.fetch("lifecycle_state") == "blocked_for_human_review" && drift.fetch("reason").include?("digest changed"))
end

class MixFacadeFixture
  attr_reader :calls

  def initialize
    @calls = []
  end

  %i[sources list get create handoff_preview handoff_execute].each do |name|
    define_method(name) do |**arguments|
      @calls << [name, arguments]
      { "ok" => true, "lifecycle_state" => "complete", "data" => { "method" => name.to_s }, "mutation" => "none" }
    end
  end
end

fixture = MixFacadeFixture.new
facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, long_form_mix_service: fixture)
requests = [
  ["mix.sources.list", { "limit" => 4 }],
  ["mix.projects.list", { "limit" => 5 }],
  ["mix.projects.get", { "mix_id" => "mix_1111111111111111" }],
  ["mix.projects.create", { "plan" => { "title" => "x" } }],
  ["mix.handoff.preview", { "mix_id" => "mix_1111111111111111" }],
  ["mix.handoff.execute", { "mix_id" => "mix_1111111111111111", "confirmation" => "EXPORT_MIX_HANDOFF", "expected_digest" => "a" * 64 }]
]
requests.each_with_index do |(operation, parameters), index|
  envelope = facade.call({
    "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
    "request_id" => format("mix-test-%02d", index),
    "operation" => operation,
    "parameters" => parameters,
    "context" => { "interface" => "dashboard" }
  })
  check(failures, "facade dispatches #{operation}", envelope.fetch("lifecycle_state") == "complete")
end
check(failures, "all mix facade operations reached the injected service", fixture.calls.map(&:first) == %i[sources list get create handoff_preview handoff_execute])

dashboard_html = File.read(File.join(__dir__, "..", "assets", "dashboard", "index.html"), encoding: "UTF-8")
dashboard_js = File.read(File.join(__dir__, "..", "assets", "dashboard", "dashboard.js"), encoding: "UTF-8")
dashboard_css = File.read(File.join(__dir__, "..", "assets", "dashboard", "dashboard.css"), encoding: "UTF-8")
brief = File.read(File.join(__dir__, "..", "docs", "soul", "LONG_FORM_MIX_A0_BRIEF.md"), encoding: "UTF-8")
check(failures, "dashboard exposes Mix Studio navigation and panel", dashboard_html.include?('id="mix-tab"') && dashboard_html.include?('id="mix-panel"'))
check(failures, "dashboard states stereo-source limitations", dashboard_html.include?("does not render a mix") && dashboard_html.include?("No inferred stems"))
check(failures, "dashboard wires all mix operations", %w[mix.sources.list mix.projects.list mix.projects.get mix.projects.create mix.handoff.preview mix.handoff.execute].all? { |operation| dashboard_js.include?(operation) })
check(failures, "dashboard includes responsive mix styling", dashboard_css.include?(".mix-layout") && dashboard_css.include?(".mix-sequence-fields"))
check(failures, "brief preserves exact export gate", brief.include?("EXPORT_MIX_HANDOFF"))

if failures.empty?
  puts "Long-form mix A0 deterministic verification passed."
  exit 0
end

warn "Long-form mix A0 verification failed: #{failures.join(', ')}"
exit 1
