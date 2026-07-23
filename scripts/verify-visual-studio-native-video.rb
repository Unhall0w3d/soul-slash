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

class NativeVideoFixtureRunner
  attr_reader :commands, :music_conflict
  def initialize(lease_store)
    @commands = []
    @lease_store = lease_store
    @music_conflict = false
  end
  def run(command, **)
    @commands << command
    begin
      lease = @lease_store.acquire_exclusive(
        provider_id: "amd-music", model_id: "ace-step-fixture", request_id: "candidate_fixture",
        resource_group: "amd-vulkan-generation", ttl_seconds: 120
      )
    rescue SoulCore::ModelRuntimeLeaseStore::ResourceBusy
      @music_conflict = true
    ensure
      @lease_store.release(lease["lease_id"]) if defined?(lease) && lease
    end
    output = command.include?("-o") ? command[command.index("-o") + 1] : command.last
    File.binwrite(output, "native-webm" * 300)
    Result.new(stdout: "three bounded steps", stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
  def which(name) = name == "ffmpeg" ? "/usr/bin/ffmpeg" : nil
end

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

Dir.mktmpdir("soul-native-video-") do |root|
  still_runtime = File.join(root, "still")
  motion_runtime = File.join(root, "motion")
  native_runtime = File.join(root, "native")
  FileUtils.mkdir_p(File.join(still_runtime, "stable-diffusion.cpp", "bin"))
  FileUtils.mkdir_p(File.join(still_runtime, "models"))
  FileUtils.mkdir_p(File.join(motion_runtime, "models"))
  FileUtils.mkdir_p(File.join(native_runtime, "bin"))
  FileUtils.mkdir_p(File.join(native_runtime, "models"))
  File.write(File.join(native_runtime, "bin", "sd-cli"), "#!/bin/sh\n")
  File.chmod(0o700, File.join(native_runtime, "bin", "sd-cli"))

  fixture = lambda do |directory, role, filename|
    path = File.join(directory, "models", filename)
    File.binwrite(path, "#{role}-fixture")
    { "role" => role, "filename" => filename, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
  end
  text = fixture.call(motion_runtime, "text_encoder", "text.gguf")
  tae = fixture.call(motion_runtime, "tae", "tae.safetensors")
  diffusion = fixture.call(native_runtime, "diffusion_model", "fastwan.gguf")
  still_manifest = File.join(root, "still.json")
  motion_manifest = File.join(root, "motion.json")
  native_manifest = File.join(root, "native.json")
  File.write(still_manifest, JSON.generate({ "profiles" => { "still" => { "label" => "Still", "accelerator" => "AMD", "files" => [] } } }))
  File.write(motion_manifest, JSON.generate({ "profiles" => { "motion" => { "files" => [text, tae] } } }))
  native_profile = {
    "label" => "FastWan fixture", "accelerator" => "AMD Vulkan", "width" => 832, "height" => 480,
    "duration_seconds" => 4, "frames" => 97, "fps" => 24, "steps" => 3, "cfg_scale" => 1, "flow_shift" => 3,
    "sampling_method" => "euler", "scheduler" => "lcm", "timeout_seconds" => 900,
    "files" => [diffusion], "shared_files" => { "text_encoder" => "text.gguf", "tae" => "tae.safetensors" }
  }
  File.write(native_manifest, JSON.generate({ "profiles" => {
    "fastwan-4s" => native_profile,
    "fastwan-8s" => native_profile.merge("label" => "FastWan 8 second fixture", "duration_seconds" => 8, "frames" => 193),
    "fastwan-12s" => native_profile.merge(
      "label" => "FastWan 12 second fixture", "duration_seconds" => 12, "frames" => 289, "fps" => 24,
      "generation_frames" => 193, "generation_fps" => 16, "delivery_method" => "bounded optical interpolation"
    )
  } }))

  ids = %w[1111111111111111 2222222222222222 3333333333333333]
  lease_store = SoulCore::ModelRuntimeLeaseStore.new(root: root)
  runner = NativeVideoFixtureRunner.new(lease_store)
  service = SoulCore::VisualStudioService.new(
    root: root, visual_root: File.join(root, "Soul", "visual", "projects"), runtime_root: still_runtime,
    manifest_path: still_manifest, motion_runtime_root: motion_runtime, motion_manifest_path: motion_manifest,
    native_runtime_root: native_runtime, native_manifest_path: native_manifest, runner: runner,
    id_generator: -> { ids.shift }, clock: -> { Time.utc(2026, 7, 21, 22) }, generation_lease_store: lease_store
  )
  project = service.create("title" => "Machine garden", "intent" => "Native-video fixture.", "prompt" => "Unused still prompt.", "negative_prompt" => "text", "aspect_ratio" => "landscape", "seed" => 42).dig("data", "project")
  direction = "The camera moves through a subterranean machine garden as luminous mechanical petals unfold."
  preview = service.native_motion_preview(project_id: project.fetch("project_id"), instruction: direction, seed: 77).fetch("data")
  wrong = service.native_motion_execute(project_id: project.fetch("project_id"), motion_id: preview.fetch("motion_candidate_id"), instruction: direction, seed: 77, confirmation: "WRONG", expected_digest: preview.fetch("expected_digest"))
  music_lease = lease_store.acquire_exclusive(
    provider_id: "amd-music", model_id: "ace-step-fixture", request_id: "candidate_existing",
    resource_group: "amd-vulkan-generation", ttl_seconds: 120
  )
  occupied = service.native_motion_execute(project_id: project.fetch("project_id"), motion_id: preview.fetch("motion_candidate_id"), instruction: direction, seed: 77, confirmation: preview.fetch("confirmation_phrase"), expected_digest: preview.fetch("expected_digest"))
  lease_store.release(music_lease.fetch("lease_id"))
  rendered = service.native_motion_execute(project_id: project.fetch("project_id"), motion_id: preview.fetch("motion_candidate_id"), instruction: direction, seed: 77, confirmation: preview.fetch("confirmation_phrase"), expected_digest: preview.fetch("expected_digest"))
  command = runner.commands.fetch(0)
  check.call("exact approval starts one bounded native render", wrong["lifecycle_state"] == "failed" && rendered["lifecycle_state"] == "blocked_for_human_review" && runner.commands.one?)
  check.call("one shared AMD lease blocks both Studio directions without queueing", occupied["lifecycle_state"] == "blocked_for_human_review" && occupied["message"].include?("AMD generation resource is occupied") && runner.music_conflict && lease_store.active_leases.empty?)
  check.call("native command has no image input, uses distilled schedule, and bounds decoder memory", !command.include?("-i") && command.each_cons(2).include?(["--steps", "3"]) && command.each_cons(2).include?(["--scheduler", "lcm"]) && command.each_cons(2).include?(["--backend", "vae=cpu"]) && command.include?("--vae-tiling"))
  motion = service.inspect(project_id: project.fetch("project_id")).dig("data", "project", "motions", 0)
  check.call("candidate records text-to-video lineage for review", motion["generation_kind"] == "text_to_video" && motion["operation"] == "visual_text_to_video" && !motion.key?("source_candidate_id"))
  revised_direction = "Keep the portal empty at first, reveal the organism behind the threshold, then let it cross the portal plane one limb at a time."
  service.motion_review(project_id: project.fetch("project_id"), motion_id: motion.fetch("motion_candidate_id"), review: { "rating" => 3, "disposition" => "revise", "notes" => revised_direction })
  revision = service.native_motion_revision_preview(project_id: project.fetch("project_id"), source_motion_id: motion.fetch("motion_candidate_id"), instruction: revised_direction, seed: 88, duration_seconds: 12).fetch("data")
  revised = service.native_motion_revision_execute(project_id: project.fetch("project_id"), source_motion_id: motion.fetch("motion_candidate_id"), motion_id: revision.fetch("motion_candidate_id"), instruction: revised_direction, seed: 88, duration_seconds: 12, confirmation: revision.fetch("confirmation_phrase"), expected_digest: revision.fetch("expected_digest"))
  revision_command = runner.commands.fetch(1)
  interpolation_command = runner.commands.fetch(2)
  revised_motion = revised.dig("data", "motion")
  check.call("revise review unlocks a bounded twelve-second native revision", revised["lifecycle_state"] == "blocked_for_human_review" && revised_motion["generation_kind"] == "text_to_video_revision" && revised_motion["source_motion_candidate_id"] == motion["motion_candidate_id"] && revised_motion["duration_seconds"] == 12.0)
  check.call("twelve-second profile bounds model work at 193 frames and delivers 24 fps", revision_command.each_cons(2).include?(["--video-frames", "193"]) && revision_command.each_cons(2).include?(["--fps", "16"]) && interpolation_command.first == "/usr/bin/ffmpeg" && interpolation_command.join(" ").include?("minterpolate=fps=24"))
end

operations = SoulCore::ApplicationContract::OPERATIONS
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
check.call("dashboard contract exposes native video and its review-led revision lane", %w[visual.native_motion.preview visual.native_motion.execute visual.native_motion.revision.preview visual.native_motion.revision.execute visual.motion.review visual.motion.promotion.preview].all? { |operation| operations.key?(operation) } && js.include?("Generate exact native scene") && js.include?("Revise native scene") && http.match?(/allowed = %w\[[^\]]*visual\.native_motion\.revision\.execute/))
check.call("native scene generation and revision use the shared live progress treatment", js.scan("createGenerationProgress").length >= 4 && js.include?("showGenerationProgress(progress, event)") && js.include?("Engaging FastWan"))

abort "#{failures.length} native-video verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Visual Studio native-video deterministic verification passed."
