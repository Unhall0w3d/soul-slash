#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/long_form_mix_render_service"
require_relative "../lib/soul_core/long_form_mix_service"
require_relative "../lib/soul_core/music_project_store"

failures = []

check = lambda do |name, value|
  puts "- #{name}: #{value ? "ok" : "FAILED"}"
  failures << name unless value
end

def read_body(response)
  body = +""
  response.body.each { |chunk| body << chunk }
  body
end

def parse_manifest(body)
  values = {}
  body.each_line do |line|
    next if line.strip.empty?
    value, name = line.strip.split(/\s+/, 2)
    name = name.to_s.sub(/^  /, "")
    values[name] = value
  end
  values
end

class FakeCommandResult
  attr_reader :stdout, :stderr, :exit_status, :truncated, :status

  def initialize(status:, stdout: "", stderr: "", exit_status: 0, truncated: false)
    @status = status
    @stdout = stdout
    @stderr = stderr
    @exit_status = exit_status
    @truncated = truncated
  end

  def success?
    status == "ok"
  end
end

class FakeRunner
  attr_reader :commands

  def initialize
    @commands = []
  end

  def which(name)
    name
  end

  def run(*command, **)
    args = command.flatten.map(&:to_s)
    @commands << args

    if args.include?("ffprobe")
      duration = "14.500"
      payload = JSON.generate({ "streams" => [{ "duration" => duration, "sample_rate" => "48000", "channels" => "2" }] })
      return FakeCommandResult.new(status: "ok", stdout: payload)
    end

    output = args.last.to_s
    if output.end_with?("master.flac")
      File.write(output, "fake flac artifact", mode: "wb", perm: 0o600)
    elsif output.end_with?("listening.mp3")
      File.write(output, "fake mp3 artifact", mode: "wb", perm: 0o600)
    end

    FakeCommandResult.new(status: "ok")
  end
end

module RenderFixture
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
      "caption" => "Long-form mix A1 fixture",
      "lyrics" => "",
      "bpm" => 128,
      "keyscale" => "C minor",
      "timesignature" => "4",
      "language" => "en",
      "seed" => seed
    )
  end

  def write_finished_candidate(store, project_id, candidate_id, export_root, duration)
    source_dir = File.join(export_root, candidate_id)
    FileUtils.mkdir_p(source_dir, mode: 0o700)
    write_file(File.join(source_dir, "master.flac"), "master.flac")
    write_file(File.join(source_dir, "listening.mp3"), "listening.mp3")
    write_file(File.join(source_dir, "song-info.md"), "song-info")
    write_file(File.join(source_dir, "song.json"), JSON.generate({
      "schema_version" => "soul.music.finished_song.v1",
      "duration_seconds" => duration
    }))

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
        "notes" => "Keep this source for A1 render."
      }
    )
  end
end

class RenderFacadeFixture
  attr_reader :calls

  def initialize
    @calls = []
  end

  %i[status preview execute].each do |name|
    define_method(name) do |**arguments|
      @calls << ["mix.render.#{name}", arguments]
      { "ok" => true, "lifecycle_state" => "complete", "data" => { "method" => name.to_s }, "mutation" => "none" }
    end
  end
end

Dir.mktmpdir("soul-long-form-mix-a1-") do |root|
  store = SoulCore::MusicProjectStore.new(root: root)
  export_root = File.join(root, "Music", "soul-music")
  export_parent = File.join(root, "Music")
  project = RenderFixture.make_project(store, "A1 Listening Render Fixture", "Bounded A1 verification.", 71)
  project_id = project.fetch("project_id")

  RenderFixture.write_finished_candidate(store, project_id, "candidate_1111111111111111", export_root, 9.0)
  RenderFixture.write_finished_candidate(store, project_id, "candidate_2222222222222222", export_root, 8.0)

  sequence = [
    {
      "project_id" => project_id,
      "candidate_id" => "candidate_1111111111111111",
      "trim_start_seconds" => 0.0,
      "trim_end_seconds" => 9.0,
      "crossfade_seconds" => 0.0,
      "transition_note" => "A1 cue one"
    },
    {
      "project_id" => project_id,
      "candidate_id" => "candidate_2222222222222222",
      "trim_start_seconds" => 1.0,
      "trim_end_seconds" => 7.0,
      "crossfade_seconds" => 0.5,
      "transition_note" => "A1 overlap"
    }
  ]

  mix_service = SoulCore::LongFormMixService.new(
    root: root,
    export_root: export_root,
    export_parent: export_parent,
    project_store: store,
    handoff_root: File.join(root, "Music", "soul-music", "mixes"),
    plans_root: File.join(root, "Soul", "private", "mix_projects"),
    clock: -> { Time.utc(2026, 7, 30, 20, 0, 0) }
  )
  create = mix_service.create(plan: {
    "title" => "A1 Listening Mix",
    "intent" => "Deterministic listening render verification",
    "sequence" => sequence
  })
  check.call("mix create returns complete", create.fetch("lifecycle_state") == "complete")
  mix_id = create.dig("data", "mix", "mix_id")

  runner = FakeRunner.new
  render_service = SoulCore::LongFormMixRenderService.new(
    root: root,
    mix_service: mix_service,
    runner: runner,
    ffmpeg_path: "ffmpeg",
    ffprobe_path: "ffprobe",
    export_root: export_root,
    export_parent: export_parent,
    clock: -> { Time.utc(2026, 7, 30, 21, 0, 0) }
  )

  preview = render_service.preview(mix_id: mix_id)
  check.call("preview returns confirmation gate", preview.fetch("lifecycle_state") == "blocked_for_human_review")
  check.call("preview requires exact phrase", preview.dig("data", "confirmation_phrase") == SoulCore::LongFormMixRenderService::CONFIRMATION)
  expected = preview.fetch("data").fetch("expected_digest")

  wrong = render_service.execute(mix_id: mix_id, confirmation: "BAD_CONFIRM", expected_digest: expected)
  check.call("wrong confirmation is blocked", wrong.fetch("lifecycle_state") == "blocked_for_human_review")

  execute = render_service.execute(mix_id: mix_id, confirmation: SoulCore::LongFormMixRenderService::CONFIRMATION, expected_digest: expected)
  check.call("execute returns complete", execute.fetch("lifecycle_state") == "complete")
  render = execute.dig("data", "render")
  destination = render.fetch("destination")
  check.call("destination is under private mix_renders", destination.include?(File.join(root, "Soul", "private", "mix_renders")))
  check.call("render payload includes output files", render.fetch("files") == ["master.flac", "listening.mp3", "render.json", "checksums.sha256"])
  check.call("render payload includes output checksums", render.fetch("checksums").keys.sort == ["listening.mp3", "master.flac"])
  check.call("render artifacts exist", [File.join(destination, "master.flac"), File.join(destination, "listening.mp3"), File.join(destination, "render.json"), File.join(destination, "checksums.sha256")].all? { |path| File.file?(path) })

  files = render.fetch("files")
  manifest = parse_manifest(File.read(File.join(destination, "checksums.sha256")))
  check.call("checksum manifest is line-based and complete", manifest.keys.sort == ["listening.mp3", "master.flac", "render.json"].sort)
  check.call("render file digests match manifest", files.take(3).all? do |filename|
    expected_value = manifest.fetch(filename, "")
    actual_value = Digest::SHA256.file(File.join(destination, filename)).hexdigest
    expected_value == actual_value
  end)
  check.call("render manifest references exact sample profile", render.fetch("command_profile").fetch("render_sample_rate") == 48000 && render.fetch("command_profile").fetch("render_channels") == 2)

  check.call("status reports ready after execute", render_service.status(mix_id: mix_id).dig("data", "state") == "ready")
  expected_duration = create.dig("data", "mix", "total_duration_seconds")
  check.call("status payload reports expected duration", render_service.status(mix_id: mix_id).dig("data", "render", "duration_seconds") == expected_duration)

  replay = render_service.execute(mix_id: mix_id, confirmation: SoulCore::LongFormMixRenderService::CONFIRMATION, expected_digest: expected)
  check.call("execute is idempotent", replay.dig("data", "idempotent_replay") == true)

  first_master = File.join(export_root, "candidate_1111111111111111", "master.flac")
  RenderFixture.write_file(first_master, "mutated source bytes")
  drift = render_service.execute(mix_id: mix_id, confirmation: SoulCore::LongFormMixRenderService::CONFIRMATION, expected_digest: expected)
  check.call("source drift blocks re-render", drift.fetch("lifecycle_state") == "blocked_for_human_review")
  RenderFixture.write_file(first_master, "master.flac")

  status = render_service.status(mix_id: mix_id)
  check.call("existing_render validates source digest metadata", status.fetch("data").fetch("render").fetch("source_file_digests").is_a?(Hash))

  command_calls = runner.commands.select { |command| command.include?("ffmpeg") }
  mix_cmd = command_calls.find { |parts| parts.last.to_s.end_with?(render.fetch("files").first) }
  mp3_cmd = command_calls.find { |parts| parts.last.to_s.end_with?("listening.mp3") }
  check.call("render invocation uses ffmpeg", !!mix_cmd && !!mp3_cmd)
  check.call("mix render graph enforces stereo format", (mix_cmd.join(" ")).include?("aformat=sample_rates=48000:channel_layouts=stereo"))
  check.call("mix render command includes output sample rate", mix_cmd.include?("-ar") && mix_cmd.include?("48000"))
  check.call("mp3 render command includes output sample rate", mp3_cmd.include?("-ar") && mp3_cmd.include?("48000") && mp3_cmd.include?("libmp3lame"))

  ffprobe_calls = runner.commands.select { |command| command.include?("ffprobe") }
  check.call("ffprobe verifies outputs", ffprobe_calls.length >= 2)
  check.call("ffprobe was used for mix output", ffprobe_calls.any? { |parts| File.basename(parts.last.to_s) == "master.flac" })
  check.call("ffprobe was used for mp3 output", ffprobe_calls.any? { |parts| File.basename(parts.last.to_s) == "listening.mp3" })

  fake_auth = Object.new
  fake_auth.define_singleton_method(:session) { |_token| { "authenticated" => true, "username" => "operator", "password_change_required" => false } }

  fake_facade = Object.new
  fake_facade.define_singleton_method(:mix_artifact_path) do |mix_id:, artifact:|
    raise SoulCore::LongFormMixRenderService::ValidationError, "unexpected artifact" if artifact == "bad"
    File.join(destination, artifact == "flac" ? "master.flac" : "listening.mp3")
  end

  app = SoulCore::DashboardHttpApplication.new(root: root, facade: fake_facade, bind_host: "127.0.0.1", port: 4567, csrf_token: "a1-csrf", authentication: fake_auth)
  headers = { "host" => "127.0.0.1:4567", "cookie" => "soul_session=test" }
  mp3 = app.call(method: "GET", target: "/api/v1/mix/audio/#{mix_id}/mp3", headers: headers)
  read_body(mp3)
  range = app.call(method: "GET", target: "/api/v1/mix/audio/#{mix_id}/mp3", headers: headers.merge("range" => "bytes=1-3"))
  range_body = read_body(range)
  mp3_size = File.size(File.join(destination, "listening.mp3"))

  check.call("mix audio endpoint serves MP3", mp3.status == 200 && mp3.headers["Content-Type"] == "audio/mpeg")
  check.call("mix audio endpoint serves expected range", range.status == 206)
  check.call("range response uses expected byte span", range.headers["Content-Range"] == "bytes 1-3/#{mp3_size}")
  check.call("range body matches selected bytes", range_body == "ake")

  missing_facade = Object.new
  missing_facade.define_singleton_method(:mix_artifact_path) { |_mix_id:, _artifact:| raise SoulCore::LongFormMixRenderService::ValidationError, "missing" }
  missing_app = SoulCore::DashboardHttpApplication.new(root: root, facade: missing_facade, bind_host: "127.0.0.1", port: 4567, csrf_token: "a1-csrf", authentication: fake_auth)
  missing = missing_app.call(method: "GET", target: "/api/v1/mix/audio/#{mix_id}/flac", headers: headers)
  check.call("mix audio missing artifact maps to 404", missing.status == 404)

  check.call("dashboard HTTP route includes mix audio endpoint", File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__)).include?("/api/v1/mix/audio/"))
  check.call("dashboard UI includes mix listening route text", File.read(File.expand_path("../assets/dashboard/index.html", __dir__)).include?("Listening renders remain review evidence"))
  check.call("dashboard JS wires mix render operations", File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__)).include?("mix.render.status"))
  check.call("dashboard JS invokes mix/audio URLs", File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__)).include?("/api/v1/mix/audio/"))
  check.call("inactive mix audio does not reserve a request slot", File.read(File.expand_path("../assets/dashboard/index.html", __dir__)).include?('id="mix-render-audio" controls preload="none"'))
  check.call("plain-text overload degrades without JSON parse leakage", File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__)).include?("Dashboard is busy serving active media"))

  facade_fixture = RenderFacadeFixture.new
  facade = SoulCore::ApplicationFacade.new(root: root, long_form_mix_render_service: facade_fixture)
  requests = [
    ["mix.render.status", { "mix_id" => mix_id }],
    ["mix.render.preview", { "mix_id" => mix_id }],
    ["mix.render.execute", { "mix_id" => mix_id, "confirmation" => SoulCore::LongFormMixRenderService::CONFIRMATION, "expected_digest" => "a" * 64 }]
  ]
  requests.each do |operation, parameters|
    envelope = facade.call({
      "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
      "request_id" => operation.gsub(".", "-"),
      "operation" => operation,
      "parameters" => parameters,
      "context" => { "interface" => "dashboard" }
    })
    check.call("facade dispatches #{operation}", envelope.fetch("lifecycle_state") == "complete")
  end
  check.call("facade dispatch order is stable", facade_fixture.calls.map(&:first) == ["mix.render.status", "mix.render.preview", "mix.render.execute"])
end

if failures.empty?
  puts "Long-form mix listening render A1 deterministic verification passed."
  exit 0
end

warn "Long-form mix listening render A1 verification failed: #{failures.join(", ")}"
exit 1
