#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
SCRIPT = File.join(ROOT, "scripts", "soul-blender-visual-runtime")
FIXTURE = "scripts/blender/soul_a0_fixture.py"
PROBE = "scripts/blender/soul_runtime_probe.py"

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  failures << label unless condition
end

def invoke(*arguments)
  stdout, stderr, status = Open3.capture3("ruby", SCRIPT, *arguments, chdir: ROOT)
  [JSON.parse(stdout), stderr, status]
rescue JSON::ParserError => error
  [{ "parse_error" => error.message, "raw" => stdout }, stderr, status]
end

def write_executable(path, content)
  File.write(path, content)
  File.chmod(0o700, path)
end

Dir.mktmpdir("soul-blender-a0-") do |temporary|
  runtime_root = File.join(temporary, "runtime")
  lease_root = File.join(temporary, "leases")
  fake_blender = File.join(temporary, "blender")
  write_executable(fake_blender, <<~'RUBY')
    #!/usr/bin/env ruby
    require "fileutils"
    require "json"
    if ARGV == ["--version"]
      puts "Blender 5.2.0 LTS"
      exit 0
    end
    if ARGV.any? { |value| value.end_with?("soul_runtime_probe.py") }
      puts "SOUL_BLENDER_PROBE=" + JSON.generate({
        "blender_version" => "5.2.0 LTS", "background" => true,
        "active_engine" => "BLENDER_EEVEE", "gpu_backend" => "VULKAN",
        "gpu_vendor" => "AMD", "gpu_renderer" => "Radeon RX 6900 XT",
        "gpu_version" => "fixture", "cycles_devices" => [
          { "name" => "AMD Radeon RX 6900 XT", "type" => "HIP", "id" => "HIP_fixture" },
          { "name" => "NVIDIA GeForce GTX 1070", "type" => "CUDA", "id" => "CUDA_fixture" }
        ]
      })
      exit 0
    end
    if ARGV.any? { |value| value.end_with?("soul_a0_fixture.py") }
      index = ARGV.index("--blend-path")
      path = ARGV.fetch(index + 1)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, "fixture-blend")
      puts "SOUL_BLENDER_FIXTURE={\"engine\":\"BLENDER_EEVEE\"}"
      exit 0
    end
    output_index = ARGV.index("--render-output")
    range_index = ARGV.index("--render-frame")
    abort "missing render arguments" unless output_index && range_index
    prefix = ARGV.fetch(output_index + 1)
    first, last = ARGV.fetch(range_index + 1).split("..", 2).map(&:to_i)
    FileUtils.mkdir_p(File.dirname(prefix))
    (first..last).each { |frame| File.binwrite(format("%s%04d.png", prefix, frame), "png-#{frame}") }
    puts "Rendered #{first}..#{last}"
  RUBY

  fake_ffmpeg = File.join(temporary, "ffmpeg")
  write_executable(fake_ffmpeg, <<~'RUBY')
    #!/usr/bin/env ruby
    File.binwrite(ARGV.last, "fixture-mp4")
  RUBY

  fake_ffprobe = File.join(temporary, "ffprobe")
  write_executable(fake_ffprobe, <<~'RUBY')
    #!/usr/bin/env ruby
    puts '{"streams":[{"codec_type":"video","width":640,"height":360,"avg_frame_rate":"24/1","nb_frames":"24","duration":"1.000"}],"format":{"duration":"1.000"}}'
  RUBY

  manifest = File.join(temporary, "manifest.json")
  config = {
    "schema_version" => "soul.blender_visual.runtime.v1",
    "profile_id" => "blender-fixture-a0", "binary_name" => "blender",
    "required_version" => "Blender 5.2.0 LTS", "renderer" => "BLENDER_EEVEE",
    "width" => 640, "height" => 360, "fps" => 24, "frames" => 24,
    "frame_format" => "PNG", "timeout_seconds" => 2,
    "resource_group" => "amd-vulkan-generation", "fixture" => FIXTURE, "probe" => PROBE
  }
  File.write(manifest, JSON.generate(config))
  common = ["--manifest", manifest, "--root", runtime_root, "--blender", fake_blender, "--ffmpeg", fake_ffmpeg, "--ffprobe", fake_ffprobe, "--lease-directory", lease_root]

  status_data, = invoke("check", *common)
  check.call("clean exact fixture runtime reports ready", status_data["lifecycle_state"] == "complete" && status_data["runtime_ready"] && status_data["startup_clean"])
  check.call("probe retains renderer and device evidence", status_data.dig("probe", "data", "gpu_renderer") == "Radeon RX 6900 XT" && status_data.dig("probe", "data", "cycles_devices").length == 2)
  check.call("check declares no persistent or listening process", !status_data["persistent_service"] && !status_data["network_listener"] && status_data["bounded_foreground_operation"])

  plan, = invoke("plan", *common)
  check.call("plan is an exact human gate", plan["lifecycle_state"] == "blocked_for_human_review" && plan["confirmation_phrase"] == "RUN_BLENDER_VISUAL_A0" && plan["expected_digest"].match?(/\A[0-9a-f]{64}\z/))
  check.call("plan binds runtime scripts binary and AMD lease", plan["binary_sha256"] == Digest::SHA256.file(fake_blender).hexdigest && plan["runtime_sha256"] == Digest::SHA256.file(SCRIPT).hexdigest && plan["fixture_sha256"] == Digest::SHA256.file(File.join(ROOT, FIXTURE)).hexdigest && plan["resource_group"] == "amd-vulkan-generation")

  wrong, _, wrong_status = invoke("run", "--expected-digest", plan["expected_digest"], "--confirmation", "WRONG", *common)
  check.call("wrong confirmation cannot create run state", !wrong_status.success? && wrong["lifecycle_state"] == "failed" && !File.exist?(File.join(runtime_root, "runs")))

  result, _, run_status = invoke("run", "--expected-digest", plan["expected_digest"], "--confirmation", "RUN_BLENDER_VISUAL_A0", *common)
  check.call("exact run ends at human review", run_status.success? && result["lifecycle_state"] == "blocked_for_human_review" && File.file?(result["receipt_path"]))
  check.call("split ranges produce one complete bounded sequence", result["frame_ranges"] == [[1, 12], [13, 24]] && result["frame_count"] == 24 && result.dig("video", "duration_seconds") == 1.0)
  check.call("scene and preview are digest bound", result["scene_sha256"] == Digest::SHA256.file(result["blend_path"]).hexdigest && result["preview_sha256"] == Digest::SHA256.file(result["output_path"]).hexdigest)
  check.call("successful run releases AMD lease", Dir.glob(File.join(lease_root, "leases", "*.json")).empty?)

  slow_blender = File.join(temporary, "slow-blender")
  write_executable(slow_blender, File.read(fake_blender).sub('puts "Rendered #{first}..#{last}"', 'sleep 10; puts "Rendered #{first}..#{last}"'))
  slow_root = File.join(temporary, "slow-runtime")
  slow_common = ["--manifest", manifest, "--root", slow_root, "--blender", slow_blender, "--ffmpeg", fake_ffmpeg, "--ffprobe", fake_ffprobe, "--lease-directory", lease_root]
  slow_plan, = invoke("plan", *slow_common)
  timed, _, timed_status = invoke("run", "--expected-digest", slow_plan["expected_digest"], "--confirmation", "RUN_BLENDER_VISUAL_A0", *slow_common)
  check.call("timeout is terminal and removes partial state", !timed_status.success? && timed["error"].include?("timed out") && Dir.glob(File.join(slow_root, "runs", "*.partial-*")).empty?)
  check.call("timeout also releases AMD lease", Dir.glob(File.join(lease_root, "leases", "*.json")).empty?)
end

brief = File.read(File.join(ROOT, "docs", "soul", "BLENDER_VISUAL_PIPELINE_A0_BRIEF.md"))
makefile = File.read(File.join(ROOT, "Makefile"))
manifest = JSON.parse(File.read(File.join(ROOT, "config", "blender_visual_runtime.json")))
check.call("production manifest pins the adopted bounded EEVEE profile", manifest["required_version"] == "Blender 5.2.0 LTS" && manifest["renderer"] == "BLENDER_EEVEE" && manifest["frames"] == 24 && manifest["resource_group"] == "amd-vulkan-generation")
check.call("Makefile exposes check plan run and verify targets", %w[blender-visual-check blender-visual-plan blender-visual-run verify-blender-visual-a0].all? { |target| makefile.include?("#{target}:") })
check.call("brief prohibits arbitrary scripts and production promotion", brief.include?("does not add a Dashboard action") && brief.include?("Only the repository-owned probe and fixture scripts") && brief.include?("No daemon, service, watcher"))

abort "Blender Visual A0 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "PASS: #{checks} Blender Visual A0 qualification checks"
