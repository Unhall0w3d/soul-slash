#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/visual_studio_service"
require_relative "../lib/soul_core/application_contract"

Result = SoulCore::BoundedCommandRunner::Result

class MotionFixtureRunner
  attr_reader :commands
  def initialize = (@commands = [])
  def run(command, **)
    @commands << command
    output = command[command.index("-o") + 1]
    bytes = command.include?("vid_gen") ? ("webm-motion" * 300) : ("\x89PNG\r\n\x1a\n".b + ("still" * 300))
    File.binwrite(output, bytes)
    Result.new(stdout: "bounded fixture", stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
end

class MotionCompanionFixture
  attr_reader :calls
  def initialize = (@calls = [])
  def generated_motion_import_preview(**arguments)
    @calls << ["preview", arguments]
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => { "confirmation_phrase" => "BIND_VISUAL_COMPANION", "expected_digest" => "a" * 64 } }
  end
  def generated_motion_import_execute(**arguments)
    @calls << ["execute", arguments]
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => { "visual" => { "stage" => "loop_ready" } } }
  end
end

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

Dir.mktmpdir("soul-generated-motion-") do |root|
  visual_runtime = File.join(root, "still-runtime")
  motion_runtime = File.join(root, "motion-runtime")
  [visual_runtime, motion_runtime].each do |runtime|
    bin = runtime == motion_runtime ? File.join(runtime, "bin") : File.join(runtime, "stable-diffusion.cpp", "bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "sd-cli"), "#!/bin/sh\n")
    File.chmod(0o700, File.join(bin, "sd-cli"))
    FileUtils.mkdir_p(File.join(runtime, "models"))
  end
  make_file = lambda do |runtime, role|
    path = File.join(runtime, "models", "#{role}.bin")
    File.binwrite(path, "#{role}-fixture")
    { "role" => role, "filename" => File.basename(path), "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
  end
  still_files = %w[diffusion_model text_encoder vae].map { |role| make_file.call(visual_runtime, role) }
  motion_files = %w[diffusion_model text_encoder tae].map { |role| make_file.call(motion_runtime, role) }
  still_manifest = File.join(root, "still.json")
  motion_manifest = File.join(root, "motion.json")
  File.write(still_manifest, JSON.generate({ "profiles" => { "still" => { "label" => "Still", "accelerator" => "AMD", "steps" => 1, "cfg_scale" => 1, "files" => still_files } }, "motion_candidates" => {} }))
  File.write(motion_manifest, JSON.generate({ "profiles" => { "motion" => { "label" => "Wan fixture", "accelerator" => "AMD Vulkan", "width" => 832, "height" => 480, "frames" => 33, "fps" => 8, "steps" => 1, "cfg_scale" => 1, "flow_shift" => 3, "sampling_method" => "euler", "decoder_role" => "tae", "files" => motion_files } } }))

  ids = %w[1111111111111111 2222222222222222 3333333333333333]
  runner = MotionFixtureRunner.new
  companion = MotionCompanionFixture.new
  service = SoulCore::VisualStudioService.new(root: root, visual_root: File.join(root, "Soul", "visual", "projects"), runtime_root: visual_runtime, manifest_path: still_manifest, motion_runtime_root: motion_runtime, motion_manifest_path: motion_manifest, runner: runner, id_generator: -> { ids.shift }, clock: -> { Time.utc(2026, 7, 21, 20) }, music_visual_companion: companion)
  project = service.create("title" => "Motion fixture", "intent" => "Test a reviewed image-to-video lane.", "prompt" => "A still nocturnal machine chamber.", "negative_prompt" => "text", "aspect_ratio" => "landscape", "seed" => 42).dig("data", "project")
  still_preview = service.generation_preview(project_id: project.fetch("project_id")).fetch("data")
  service.generation_execute(project_id: project.fetch("project_id"), candidate_id: still_preview.fetch("candidate_id"), confirmation: still_preview.fetch("confirmation_phrase"), expected_digest: still_preview.fetch("expected_digest"))
  blocked = service.motion_preview(project_id: project.fetch("project_id"), source_candidate_id: still_preview.fetch("candidate_id"), instruction: "Locked camera with restrained atmospheric motion.", seed: 77)
  check.call("motion requires a kept source still", blocked["lifecycle_state"] == "awaiting_input")
  service.record_review(project_id: project.fetch("project_id"), candidate_id: still_preview.fetch("candidate_id"), review: { "rating" => 4, "disposition" => "keep", "notes" => "Stable source." })
  preview = service.motion_preview(project_id: project.fetch("project_id"), source_candidate_id: still_preview.fetch("candidate_id"), instruction: "Locked camera with restrained atmospheric motion.", seed: 77).fetch("data")
  wrong = service.motion_execute(project_id: project.fetch("project_id"), source_candidate_id: still_preview.fetch("candidate_id"), motion_id: preview.fetch("motion_candidate_id"), instruction: "Locked camera with restrained atmospheric motion.", seed: 77, confirmation: "yes", expected_digest: preview.fetch("expected_digest"))
  rendered = service.motion_execute(project_id: project.fetch("project_id"), source_candidate_id: still_preview.fetch("candidate_id"), motion_id: preview.fetch("motion_candidate_id"), instruction: "Locked camera with restrained atmospheric motion.", seed: 77, confirmation: preview.fetch("confirmation_phrase"), expected_digest: preview.fetch("expected_digest"))
  check.call("exact approval gates one bounded Wan invocation", wrong["lifecycle_state"] == "failed" && rendered["lifecycle_state"] == "blocked_for_human_review" && runner.commands.count { |command| command.include?("vid_gen") } == 1)
  motion_id = preview.fetch("motion_candidate_id")
  inspect = service.inspect(project_id: project.fetch("project_id"))
  check.call("motion candidate is immutable archive evidence", inspect.dig("data", "project", "motions", 0, "motion_candidate_id") == motion_id && File.file?(service.motion_artifact_path(project_id: project.fetch("project_id"), motion_id: motion_id)))
  service.motion_review(project_id: project.fetch("project_id"), motion_id: motion_id, review: { "rating" => 4, "disposition" => "keep", "notes" => "Coherent motion." })
  promotion = service.motion_promotion_preview(project_id: project.fetch("project_id"), motion_id: motion_id, music_project_id: "music_#{'4' * 16}", music_candidate_id: "candidate_#{'5' * 16}")
  check.call("only reviewed motion advances to exact Music binding", promotion["lifecycle_state"] == "blocked_for_human_review" && companion.calls.one?)
end

operations = SoulCore::ApplicationContract::OPERATIONS
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
check.call("dashboard and contract expose the bounded reviewed motion lane", %w[visual.motion.preview visual.motion.execute visual.motion.review visual.motion.delete.preview visual.motion.delete.execute visual.motion.promotion.preview visual.motion.promotion.execute].all? { |operation| operations.key?(operation) } && js.include?("Create motion study") && js.include?("Bind motion to Music") && js.include?("Delete motion study") && js.include?("Dashboard security token refreshed; preview the exact action again") && http.include?("/api/v1/visual/motion/") && http.match?(/allowed = %w\[[^\]]*visual\.motion\.execute/))

abort "#{failures.length} generated-motion verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Visual Studio generated-motion deterministic verification passed."
