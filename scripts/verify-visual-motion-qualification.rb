#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

SCRIPT = File.expand_path("soul-visual-motion-runtime", __dir__)
checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  failures << label unless condition
end

def invoke(*arguments)
  stdout, stderr, status = Open3.capture3("ruby", SCRIPT, *arguments)
  [JSON.parse(stdout), stderr, status]
rescue JSON::ParserError => error
  [{ "parse_error" => error.message, "raw" => stdout }, stderr, status]
end

Dir.mktmpdir("soul-visual-motion-") do |temporary|
  root = File.join(temporary, "runtime")
  models = File.join(root, "models")
  FileUtils.mkdir_p(models)
  files = {
    "diffusion_model" => "diffusion.gguf",
    "text_encoder" => "text.gguf",
    "vae" => "vae.safetensors"
  }.map do |role, filename|
    path = File.join(models, filename)
    File.binwrite(path, "#{role}-fixture")
    { "role" => role, "repository" => "fixture/models", "revision" => "a" * 40, "filename" => filename, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
  end
  manifest = File.join(temporary, "manifest.json")
  profile = {
    "label" => "Wan fixture", "accelerator" => "AMD Vulkan with CPU offload", "mode" => "image_to_video",
    "width" => 832, "height" => 480, "frames" => 33, "fps" => 8, "steps" => 20,
    "cfg_scale" => 6.0, "flow_shift" => 3.0, "sampling_method" => "euler", "timeout_seconds" => 3,
    "files" => files
  }
  File.write(manifest, JSON.generate({ "schema_version" => "soul.visual_motion.models.v1", "runtime" => { "repository" => "https://example.invalid/runtime.git", "revision" => "b" * 40, "build" => "vulkan" }, "profiles" => { "wan-fixture" => profile } }))

  runner = File.join(temporary, "fake-sd-cli")
  File.write(runner, <<~'SH')
    #!/bin/sh
    output=""
    previous=""
    for value in "$@"; do
      if [ "$previous" = "-o" ]; then output="$value"; fi
      previous="$value"
    done
    test -n "$output" || exit 9
    printf 'fixture-video' > "$output"
    printf 'Vulkan fixture completed\n'
  SH
  File.chmod(0o700, runner)

  probe = File.join(temporary, "fake-ffprobe")
  File.write(probe, <<~'SH')
    #!/bin/sh
    printf '%s\n' '{"streams":[{"codec_type":"video","width":832,"height":480,"avg_frame_rate":"8/1","nb_frames":"33","duration":"4.125"}],"format":{"duration":"4.125"}}'
  SH
  File.chmod(0o700, probe)

  source = File.join(temporary, "source.png")
  File.binwrite(source, "\x89PNG\r\n\x1a\nfixture")
  request = File.join(temporary, "request.json")
  File.write(request, JSON.generate({ "source_image" => source, "prompt" => "Restrained water and atmospheric motion; locked camera.", "negative_prompt" => "camera pan, deformation", "seed" => 42 }))
  common = ["--manifest", manifest, "--root", root, "--runner", runner, "--probe", probe]

  status_data, = invoke("check", *common)
  check.call("exact fixture runtime and models report ready", status_data["lifecycle_state"] == "complete" && status_data["runtime_ready"] && status_data["models_ready"])

  setup_plan, = invoke("plan", "--action", "setup", *common)
  download_plan, = invoke("plan", "--action", "download", *common)
  check.call("setup and download are separate exact human gates", setup_plan["confirmation_phrase"] == "INSTALL_VISUAL_MOTION_VULKAN_RUNTIME" && download_plan["confirmation_phrase"] == "DOWNLOAD_VISUAL_MOTION_MODELS" && setup_plan["expected_digest"] != download_plan["expected_digest"])
  check.call("plans prohibit persistent runtime architecture", [setup_plan, download_plan].all? { |plan| plan["lifecycle_state"] == "blocked_for_human_review" && !plan["persistent_service"] && !plan["network_listener"] })

  run_plan, = invoke("plan", "--action", "run", "--request", request, *common)
  check.call("pilot plan binds source image and fixed conservative profile", run_plan["source_image_sha256"] == Digest::SHA256.file(source).hexdigest && run_plan.dig("profile", "frames") == 33 && run_plan.dig("profile", "fps") == 8)
  wrong, _, wrong_status = invoke("run", "--request", request, "--expected-digest", run_plan["expected_digest"], "--confirmation", "WRONG", *common)
  check.call("wrong confirmation cannot start a pilot", !wrong_status.success? && wrong["lifecycle_state"] == "failed" && !File.exist?(File.join(root, "runs")))

  result, _, run_status = invoke("run", "--request", request, "--expected-digest", run_plan["expected_digest"], "--confirmation", "RUN_VISUAL_MOTION_PILOT", *common)
  check.call("one exact pilot terminates at human review", run_status.success? && result["lifecycle_state"] == "blocked_for_human_review" && File.file?(result["output_path"]) && File.file?(result["receipt_path"]))
  check.call("pilot output is dimension and digest validated", result.dig("video", "width") == 832 && result.dig("video", "duration_seconds") == 4.125 && result["output_sha256"] == Digest::SHA256.file(result["output_path"]).hexdigest)

  changed_request = File.join(temporary, "changed.json")
  File.write(changed_request, JSON.generate({ "source_image" => source, "prompt" => "Different motion", "negative_prompt" => "", "seed" => 43 }))
  stale, _, stale_status = invoke("run", "--request", changed_request, "--expected-digest", run_plan["expected_digest"], "--confirmation", "RUN_VISUAL_MOTION_PILOT", *common)
  check.call("changed inputs invalidate a stale approval", !stale_status.success? && stale["error"].include?("EXPECTED_DIGEST"))

  symlink = File.join(temporary, "source-link.png")
  File.symlink(source, symlink)
  symlink_request = File.join(temporary, "symlink-request.json")
  File.write(symlink_request, JSON.generate({ "source_image" => symlink, "prompt" => "motion", "seed" => 44 }))
  linked, _, linked_status = invoke("plan", "--action", "run", "--request", symlink_request, *common)
  check.call("symlink source images are rejected", !linked_status.success? && linked["error"].include?("non-symlink"))

  slow_runner = File.join(temporary, "slow-sd-cli")
  File.write(slow_runner, "#!/bin/sh\nsleep 10\n")
  File.chmod(0o700, slow_runner)
  slow_manifest = File.join(temporary, "slow-manifest.json")
  slow_profile = profile.merge("timeout_seconds" => 1)
  File.write(slow_manifest, JSON.generate({ "schema_version" => "soul.visual_motion.models.v1", "runtime" => { "repository" => "https://example.invalid/runtime.git", "revision" => "b" * 40, "build" => "vulkan" }, "profiles" => { "wan-fixture" => slow_profile } }))
  slow_common = ["--manifest", slow_manifest, "--root", root, "--runner", slow_runner, "--probe", probe]
  slow_plan, = invoke("plan", "--action", "run", "--request", changed_request, *slow_common)
  timed, _, timed_status = invoke("run", "--request", changed_request, "--expected-digest", slow_plan["expected_digest"], "--confirmation", "RUN_VISUAL_MOTION_PILOT", *slow_common)
  partials = Dir.glob(File.join(root, "runs", "*.partial-*"))
  check.call("timeout is terminal and removes partial state", !timed_status.success? && timed["error"].include?("timed out") && partials.empty?)
end

brief = File.read(File.expand_path("../docs/soul/VISUAL_STUDIO_A3_MOTION_QUALIFICATION_BRIEF.md", __dir__))
makefile = File.read(File.expand_path("../Makefile", __dir__))
manifest = JSON.parse(File.read(File.expand_path("../config/visual_motion_models.json", __dir__)))
check.call("production manifest pins exact runtime and model identities", manifest.dig("runtime", "revision").match?(/\A[0-9a-f]{40}\z/) && manifest.fetch("profiles").values.first.fetch("files").all? { |file| file.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) && file.fetch("bytes").positive? })
check.call("Makefile exposes check plan install download and pilot gates", %w[visual-motion-check visual-motion-runtime-plan visual-motion-runtime-install visual-motion-model-download-plan visual-motion-model-download visual-motion-pilot-plan visual-motion-pilot-run].all? { |target| makefile.include?("#{target}:") })
check.call("brief stops before production enablement", brief.include?("does not yet add a production") && brief.include?("No service, network listener, queue, scheduler, watcher"))

abort "Visual motion qualification verification failed: #{failures.join(', ')}" unless failures.empty?
puts "PASS: #{checks} Visual Studio A3 motion qualification checks"
