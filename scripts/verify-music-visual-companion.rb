#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/music_visual_companion_service"

Result = Struct.new(:stdout, :stderr, :status, keyword_init: true) do
  def success? = status == "ok"
end

class VisualRunner
  attr_reader :commands
  def initialize = (@commands = [])
  def which(name) = "/usr/bin/#{name}"
  def run(*command, **_options)
    argv = command.length == 1 && command.first.is_a?(Array) ? command.first : command
    @commands << argv
    return Result.new(stdout: "3.000\n", stderr: "", status: "ok") if argv.first.end_with?("ffprobe")
    File.binwrite(argv.last, "bounded visual fixture") if argv.last.end_with?(".mp4")
    Result.new(stdout: "", stderr: "", status: "ok")
  end
end

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

Dir.mktmpdir("soul-visual-companion-") do |root|
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1" * 16 }, clock: -> { Time.utc(2026, 7, 18, 20) })
  project = store.create(
    "title" => "Visual fixture", "intent" => "Prove exact audio binding.", "target_duration_seconds" => 30,
    "vocal_mode" => "instrumental", "rights_status" => "original", "caption" => "Liquid drum and bass with restrained nocturnal atmosphere.",
    "lyrics" => "", "bpm" => 174, "keyscale" => "F# minor", "timesignature" => "4", "language" => "en", "seed" => 42
  )
  project_id = project.fetch("project_id")
  candidate_id = "candidate_#{'2' * 16}"
  candidate_dir = File.join(store.generations_path(project_id), candidate_id)
  Dir.mkdir(candidate_dir, 0o700)
  audio = File.join(candidate_dir, "master.flac")
  File.binwrite(audio, "lossless audio fixture")
  File.binwrite(File.join(candidate_dir, "listening.mp3"), "mp3 fixture")
  audio_sha = Digest::SHA256.file(audio).hexdigest
  candidate = {
    "schema_version" => "soul.music.generation.v1", "project_id" => project_id, "candidate_id" => candidate_id,
    "artifacts" => { "flac" => { "sha256" => audio_sha }, "mp3" => { "sha256" => Digest::SHA256.file(File.join(candidate_dir, "listening.mp3")).hexdigest } }
  }
  File.write(File.join(candidate_dir, "candidate.json"), JSON.generate(candidate))

  source_root = File.join(root, "assets", "music_visuals")
  FileUtils.mkdir_p(source_root)
  asset_id = "visual-fixture-v1"
  File.binwrite(File.join(source_root, "#{asset_id}.png"), "png fixture")
  source = {
    "schema_version" => "soul.music.visual_source.v1", "asset_id" => asset_id, "label" => "Visual fixture",
    "image" => "#{asset_id}.png", "project_id" => project_id, "candidate_id" => candidate_id,
    "provider" => "test provider", "rights_status" => "original", "generated_at" => "2026-07-18T20:00:00Z",
    "prompt_summary" => "A bounded fixture.", "animation_intent" => ["water"]
  }
  File.write(File.join(source_root, "#{asset_id}.json"), JSON.generate(source))
  runner = VisualRunner.new
  service = SoulCore::MusicVisualCompanionService.new(root: root, project_store: store, runner: runner, source_root: source_root, clock: -> { Time.utc(2026, 7, 18, 20, 1) })

  sources = service.available_sources(project_id: project_id, candidate_id: candidate_id)
  preview = service.import_preview(project_id: project_id, candidate_id: candidate_id, asset_id: asset_id)
  wrong = service.import_execute(project_id: project_id, candidate_id: candidate_id, asset_id: asset_id, confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  bound = service.import_execute(project_id: project_id, candidate_id: candidate_id, asset_id: asset_id, confirmation: "BIND_VISUAL_COMPANION", expected_digest: preview.dig("data", "expected_digest"))
  visual = bound.dig("data", "visual")
  check.call("reviewed source binds only to its exact candidate and audio digest", sources.one? && wrong["lifecycle_state"] == "blocked_for_human_review" && visual["candidate_audio_sha256"] == audio_sha && visual["stage"] == "base_bound")

  presentation = { "mode" => "static", "fit" => "contain", "matte" => "#060B11", "intro_fade_seconds" => 1.5, "outro_fade_seconds" => 3.5 }
  loop_preview = service.loop_preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"), presentation: presentation)
  changed_presentation = presentation.merge("fit" => "cover")
  stale = service.loop_execute(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"), presentation: changed_presentation, confirmation: "RENDER_VISUAL_LOOP", expected_digest: loop_preview.dig("data", "expected_digest"))
  unavailable_motion = service.loop_preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"), presentation: presentation.merge("mode" => "generated_motion"))
  check.call("presentation changes invalidate approval and generated motion remains unavailable", stale["ok"] == false && unavailable_motion["lifecycle_state"] == "awaiting_input" && runner.commands.empty?)
  looped = service.loop_execute(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"), presentation: presentation, confirmation: "RENDER_VISUAL_LOOP", expected_digest: loop_preview.dig("data", "expected_digest"))
  loop = looped.dig("data", "visual", "artifacts", "loop")
  loop_command = runner.commands.find { |command| command.last.end_with?(".mp4") }
  check.call("one bounded CPU encode holds the still without synthesized effects", looped["lifecycle_state"] == "blocked_for_human_review" && loop["duration_seconds"] == 12 && loop["motion_profile"] == "static_hold" && loop["frame_change_expected"] == false && loop_command.join(" ").include?("force_original_aspect_ratio=decrease") && loop_command.join(" ").include?("pad=1280:720") && loop_command.join(" ").include?("gradfun=1.2:16") && loop_command.include?("stillimage") && !loop_command.join(" ").include?("displace"))

  final_preview = service.final_preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"))
  rendered = service.final_execute(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"), confirmation: "RENDER_VISUAL_COMPANION", expected_digest: final_preview.dig("data", "expected_digest"))
  final = rendered.dig("data", "visual", "artifacts", "preview")
  final_command = runner.commands.find { |command| command.first.end_with?("ffmpeg") && command.include?(audio) }
  base_image = File.join(store.project_path(project_id), "visuals", visual.fetch("visual_id"), "base.png")
  check.call("final render uses the lossless still directly and binds exact audio once", rendered["lifecycle_state"] == "blocked_for_human_review" && final["duration_seconds"] == 3.0 && final_command.include?(audio) && final_command.include?(base_image) && !final_command.include?("-stream_loop") && final_command.include?("stillimage") && final_command[final_command.index("-crf") + 1] == "16" && final_command.join(" ").include?("gradfun=1.2:16") && final_command.join(" ").include?("fade=t=in:st=0:d=1.5") && final_command.join(" ").include?("fade=t=out:st=0:d=3.5"))
  check.call("authenticated artifact resolver verifies every stored digest", %w[base loop preview].all? { |kind| File.file?(service.artifact_path(project_id: project_id, candidate_id: candidate_id, visual_id: visual.fetch("visual_id"), artifact: kind)) })
end

contract = File.read(File.join(__dir__, "..", "lib", "soul_core", "application_contract.rb"))
facade = File.read(File.join(__dir__, "..", "lib", "soul_core", "application_facade.rb"))
http = File.read(File.join(__dir__, "..", "lib", "soul_core", "dashboard_http_application.rb"))
javascript = File.read(File.join(__dir__, "..", "assets", "dashboard", "dashboard.js"))
check.call("application and dashboard expose static presentation and immutable private media", %w[music.visuals.import.preview music.visuals.loop.execute music.visuals.final.execute visual_presentation].all? { |operation| contract.include?(operation) && facade.include?(operation) } && http.include?("/api/v1/music/visual/") && javascript.include?("Static visual presentation") && javascript.include?("Generated motion") && javascript.include?("Qualification pending"))
check.call("visual slice has no image-model service listener or publication path", !File.read(File.join(__dir__, "..", "lib", "soul_core", "music_visual_companion_service.rb")).match?(/youtube|upload|listen|daemon|Thread\.new/))

abort "#{failures.length} visual companion verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Music visual companion deterministic verification passed."
