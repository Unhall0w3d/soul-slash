#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tempfile"
require_relative "../lib/soul_core/blender_audio_analyzer"
require_relative "../lib/soul_core/blender_scene_manifest"

ROOT = File.expand_path("..", __dir__)
ADAPTER = File.join(ROOT, "scripts", "blender", "soul_scene_adapter.py")
TEMPLATE = JSON.parse(File.binread(File.join(ROOT, "config", "blender_scene_templates.json"))).fetch("templates").fetch("orbital_campfire_study")

def copy(value)
  JSON.parse(JSON.generate(value))
end

def reject_by_both(raw)
  begin
    SoulCore::BlenderSceneManifest.new(copy(raw))
  rescue SoulCore::BlenderSceneManifest::ValidationError
    # Rejection here is required before checking equivalent adapter behavior.
  else
    raise "Ruby manifest accepted invalid A8 input"
  end

  Tempfile.create(["soul-a8-invalid-", ".json"]) do |file|
    file.write(JSON.generate(raw))
    file.flush
    _output, status = Open3.capture2e("python3", ADAPTER, "--manifest", file.path, "--blend-path", "ignored.blend", "--dry-run")
    raise "Python adapter accepted invalid A8 input" if status.success?
  end
end

checks = []
check = lambda do |label, &block|
  block.call
  checks << label
  puts "PASS: #{label}"
rescue StandardError => error
  warn "FAIL: #{label}: #{error.message}"
  exit 1
end

check.call("A8 template is an exact 900-frame 720p30 study") do
  normalized = SoulCore::BlenderSceneManifest.new(copy(TEMPLATE)).to_h
  render = normalized.fetch("render")
  raise "render contract drifted" unless render.values_at("width", "height", "fps", "frame_start", "frame_end") == [1280, 720, 30, 1, 900]
  raise "composition drifted" unless normalized.dig("composition", "preset") == "orbital_campfire_study"
end

check.call("A8 pins the reviewed campfire composition and seven curated instances") do
  assets = TEMPLATE.fetch("curated_assets")
  ids = assets.group_by { |entry| entry.fetch("asset_id") }.transform_values(&:length)
  raise "curated composition drifted" unless ids == { "island_tree_01" => 3, "boulder_01" => 4 }
  object_ids = TEMPLATE.fetch("objects").map { |entry| entry.fetch("id") }
  light_ids = TEMPLATE.fetch("lights").map { |entry| entry.fetch("id") }
  raise "campfire primitives drifted" unless %w[fire_ember ground_slice log_a log_b].all? { |id| object_ids.include?(id) }
  raise "reviewed lighting drifted" unless %w[campfire_light moon_key night_rim].all? { |id| light_ids.include?(id) }
end

check.call("unreviewed asset identities and manifest paths fail closed") do
  bad_id = copy(TEMPLATE)
  bad_id.fetch("curated_assets").first["asset_id"] = "internet_tree"
  reject_by_both(bad_id)
  injected_path = copy(TEMPLATE)
  injected_path.fetch("curated_assets").first["path"] = "/tmp/unreviewed.blend"
  reject_by_both(injected_path)
end

check.call("adapter owns exactly one reviewed library loader") do
  source = File.binread(ADAPTER)
  raise "loader count changed" unless source.scan("bpy.data.libraries.load").length == 1
  scope = source[/def build_curated_assets\(.*?\n\n\ndef /m]
  raise "loader escaped reviewed builder" unless scope&.include?("bpy.data.libraries.load")
  forbidden = %w[subprocess socket requests urllib bpy.ops.wm.append bpy.ops.wm.link autoexec]
  found = forbidden.select { |token| source.include?(token) }
  raise "forbidden runtime capability: #{found.join(', ')}" unless found.empty?
end

check.call("30-second analysis is non-looping and exactly 900 frames") do
  Tempfile.create(["soul-a8-audio-", ".wav"]) do |audio|
    audio.close
    output, status = Open3.capture2e("ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=220:duration=31", "-y", audio.path)
    raise "fixture audio failed: #{output}" unless status.success?
    analysis = SoulCore::BlenderAudioAnalyzer.new.analyze(path: audio.path, bpm: 120, beats_per_bar: 4, fps: 30, duration_seconds: 30.0)
    raise "study mode drifted" unless analysis.fetch("temporal_mode") == "thirty_second_study"
    raise "frame contract drifted" unless analysis.fetch("frame_count") == 900
    raise "study became loop-shaped" unless analysis.fetch("bar_frames") == [] && analysis.fetch("loop_state_equal") == false
  end
end

check.call("service keeps A8 comparison-only and digest-bound") do
  service = File.binread(File.join(ROOT, "lib", "soul_core", "blender_scene_service.rb"))
  required = [
    'TEMPORAL_MODES = %w[whole_bar_loop thirty_second_study]',
    'analyzer_parameters[:duration_seconds] = 30.0 if study',
    '"publication_eligible" => !study',
    'comparison_scene_ids',
    'preview_sha256',
    '30-second Blender studies are comparison evidence and cannot be bound'
  ]
  missing = required.reject { |token| service.include?(token) }
  raise "missing service guardrails: #{missing.join(', ')}" unless missing.empty?
end

check.call("Dashboard exposes a labeled four-way nonpublishable comparison") do
  html = File.binread(File.join(ROOT, "assets", "dashboard", "index.html"))
  javascript = File.binread(File.join(ROOT, "assets", "dashboard", "dashboard.js"))
  required = %w[orbital_campfire_study thirty_second_study comparison_scenes]
  missing = required.reject { |token| html.include?(token) || javascript.include?(token) }
  raise "missing Dashboard markers: #{missing.join(', ')}" unless missing.empty?
  raise "four-way comparison contract missing" unless javascript.include?('scene.comparison_scenes.length === 3')
  raise "comparison-only label missing" unless javascript.include?("not publishable")
end

check.call("A8 remains foreground-only with no scheduling implementation") do
  combined = [
    File.binread(File.join(ROOT, "lib", "soul_core", "blender_scene_service.rb")),
    File.binread(ADAPTER),
    File.binread(File.join(ROOT, "docs", "soul", "BLENDER_CURATED_ASSET_COMPARISON_A8_BRIEF.md"))
  ].join("\n")
  forbidden = ["cron", "systemd timer", "daemonize", "background continuation"]
  found = forbidden.select { |token| combined.downcase.include?(token) }
  raise "A8 acquired scheduling behavior: #{found.join(', ')}" unless found.empty?
end

check.call("human review packet covers evidence, risk, and known weaknesses") do
  review = File.binread(File.join(ROOT, "docs", "assessments", "BLENDER_CURATED_ASSET_COMPARISON_A8_REVIEW.md"))
  headings = ["## What was implemented", "## Commands and deterministic results", "## Live qualification evidence", "## Local LLM evaluation", "## Memory and lifecycle", "## Risk classification", "## Known weaknesses", "## Human review checklist"]
  missing = headings.reject { |heading| review.include?(heading) }
  raise "review packet is incomplete: #{missing.join(', ')}" unless missing.empty?
end

puts "Blender Scene A8 checks passed: #{checks.length}"
