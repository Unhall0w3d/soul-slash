#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))
require "soul_core/blender_scene_service"

Result = Struct.new(:status, :stderr, :stdout, keyword_init: true) do
  def success? = status == "ok"
end

class FixtureRunner
  attr_accessor :fail_render_once

  def initialize(root)
    @fail_render_once = false
    @root = root
    %w[blender ffmpeg ffprobe].each do |name|
      path = File.join(@root, name)
      File.write(path, "fixture executable")
      File.chmod(0o700, path)
    end
  end

  def which(name) = File.join(@root, name)

  def run(command, **_options)
    command = command.flatten
    if command.any? { |entry| entry.end_with?("soul_scene_adapter.py") }
      File.write(value_after(command, "--blend-path"), "fixture blend")
      File.write(value_after(command, "--still-path"), "fixture png")
    elsif command.any? { |entry| entry.end_with?("soul_scene_render.py") }
      directory = value_after(command, "--frames-dir")
      first = Integer(value_after(command, "--frame-start"))
      last = Integer(value_after(command, "--frame-end"))
      FileUtils.mkdir_p(directory)
      upper = @fail_render_once ? first + ((last - first) / 2) : last
      (first..upper).each { |frame| File.write(File.join(directory, format("frame_%04d.png", frame)), "frame #{frame}") }
      if @fail_render_once
        @fail_render_once = false
        return Result.new(status: "timeout", stderr: "fixture cancellation", stdout: "")
      end
    elsif command.first.end_with?("ffmpeg")
      File.write(command.last, "fixture mp4")
    end
    Result.new(status: "ok", stderr: "", stdout: "")
  end

  private

  def value_after(command, flag) = command.fetch(command.index(flag) + 1)
end

class FixtureAnalyzer
  def analyze(path:, bpm:, beats_per_bar:, bars:, fps:)
    frame_count = bars == 8 ? 12 : 18
    values = [0.0, 0.65, 1.0, 0.35, 0.0]
    {
      "schema_version" => "soul.blender.audio_analysis.v1",
      "source_audio_sha256" => Digest::SHA256.file(path).hexdigest,
      "bpm" => Float(bpm), "beats_per_bar" => beats_per_bar, "bars" => bars, "fps" => fps,
      "frame_count" => frame_count, "nominal_duration_seconds" => (bars * beats_per_bar * 60.0 / bpm).round(6),
      "rendered_duration_seconds" => frame_count.to_f / fps, "bar_frames" => (0..bars).to_a,
      "curve_frames" => [1, 4, 7, 10, frame_count],
      "curves" => %w[low_band mid_band high_band energy kick].to_h { |name| [name, values.dup] },
      "loop_state_equal" => true, "analysis_process" => "fixture"
    }
  end
end

class FixtureMusicStore
  def initialize(audio)
    @audio = audio
  end

  def read(project_id) = { "project_id" => project_id, "title" => "Fixture music" }
  def candidate_input(_project_id, _candidate_id)
    { "caption" => "fixture", "lyrics" => "[Instrumental]", "bpm" => 120, "keyscale" => "D minor", "timesignature" => "4", "language" => "en", "duration" => 90, "seed" => 4, "batch_size" => 1, "inference_steps" => 8 }
  end
  def read_review(_project_id, candidate_id) = { "candidate_id" => candidate_id, "disposition" => "keep", "rating" => 4 }
  def candidate_artifact_path(_project_id, _candidate_id, artifact)
    raise "wrong artifact" unless artifact == "flac"
    @audio
  end
end

class FixtureLeaseStore
  def acquire_exclusive(**_attributes) = { "lease_id" => "a" * 32 }
  def release(_lease_id) = true
end

checks = 0
failures = []
check = lambda do |label, &block|
  checks += 1
  block.call
  puts "PASS: #{label}"
rescue StandardError => error
  failures << "#{label}: #{error.message}"
end

Dir.mktmpdir(".soul-blender-a2-", ROOT) do |temporary|
  visual_root = File.join(temporary, "Soul", "visual", "projects")
  project_id = "visual_project_#{'a' * 16}"
  project_dir = File.join(visual_root, project_id)
  FileUtils.mkdir_p(project_dir)
  File.write(File.join(project_dir, "project.json"), JSON.generate({ "project_id" => project_id, "title" => "Fixture visual" }))
  audio = File.join(temporary, "fixture.flac")
  File.write(audio, "fixture audio")
  runner = FixtureRunner.new(File.join(temporary, "tools").tap { |path| FileUtils.mkdir_p(path) })
  service = SoulCore::BlenderSceneService.new(
    root: ROOT, visual_root: visual_root, runner: runner, analyzer: FixtureAnalyzer.new,
    music_store: FixtureMusicStore.new(audio), lease_store: FixtureLeaseStore.new,
    id_generator: -> { "b" * 16 }, clock: -> { Time.utc(2026, 8, 10, 1, 0, 0) }
  )
  parameters = {
    project_id: project_id, music_project_id: "music_project_#{'c' * 16}", music_candidate_id: "candidate_#{'d' * 16}",
    template_id: "audio_reactive", bars: 8, direction: "A bounded cyan and copper pulse chamber.", seed: 42, quality: "review"
  }

  preview = service.preview(**parameters)
  scene_id = preview.dig("data", "scene_id")
  check.call("preview binds reviewed music, whole bars, manifest, and exact gate") do
    raise "preview failed" unless preview["ok"] && preview["lifecycle_state"] == "blocked_for_human_review"
    raise "wrong bars" unless preview.dig("data", "bars") == 8
    raise "loop is not closed" unless preview.dig("data", "audio_analysis_summary", "loop_state_equal")
    raise "missing gate" unless preview.dig("data", "confirmation_phrase") == SoulCore::BlenderSceneService::CONFIRMATION
  end

  wrong = service.execute(**parameters.merge(scene_id: scene_id, confirmation: "WRONG", expected_digest: preview.dig("data", "expected_digest")))
  check.call("wrong exact confirmation is rejected") { raise "wrong gate accepted" if wrong["ok"] }

  runner.fail_render_once = true
  failed = service.execute(**parameters.merge(scene_id: scene_id, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest")))
  check.call("interrupted render retains bounded resumable frames") do
    raise "failure was not retained" unless failed["lifecycle_state"] == "failed" && failed.dig("data", "resumable")
    raise "no retained frames" unless failed.dig("data", "retained_frames").positive?
  end

  resume_preview = service.resume_preview(project_id: project_id, scene_id: scene_id)
  resumed = service.resume_execute(
    project_id: project_id, scene_id: scene_id, confirmation: resume_preview.dig("data", "confirmation_phrase"),
    expected_digest: resume_preview.dig("data", "expected_digest")
  )
  check.call("retained render resumes only missing frames and becomes reviewable") do
    raise "resume failed: #{resumed}" unless resumed["ok"] && resumed["lifecycle_state"] == "blocked_for_human_review"
    record = resumed.dig("data", "blender_scene")
    raise "wrong lifecycle" unless record["lifecycle_state"] == "blocked_for_human_review"
    raise "artifact package incomplete" unless %w[manifest blend still audio_analysis preview].all? { |name| record.dig("artifacts", name, "sha256") }
  end

  review = service.review(project_id: project_id, scene_id: scene_id, review: { "rating" => 4, "disposition" => "keep", "notes" => "fixture accepted" })
  check.call("human keep review is retained") { raise "review failed" unless review["ok"] }

  listed = service.list(project_id: project_id)
  check.call("Blender scenes remain a distinct project subtree") do
    raise "scene missing from inventory" unless listed.dig("data", "blender_scenes").map { |entry| entry["scene_id"] }.include?(scene_id)
  end
end

if failures.empty?
  puts "Blender Scene A2 verifier complete: #{checks} checks passed"
else
  failures.each { |failure| warn "FAIL: #{failure}" }
  abort "Blender Scene A2 verifier failed"
end
