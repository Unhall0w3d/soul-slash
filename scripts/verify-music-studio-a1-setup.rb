#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

root = File.expand_path("..", __dir__)
script = File.join(root, "scripts", "soul-music-pilot")
manifest = File.join(root, "config", "music_pilot_models.json")
failures = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? 'ok' : 'FAILED'}"
  failures << name unless condition
end

puts "Music Studio A1 setup verification:"

Dir.mktmpdir("soul-music-a1-") do |pilot_root|
  stdout, stderr, status = Open3.capture3("ruby", script, "plan", "--manifest", manifest, "--root", pilot_root)
  plan = JSON.parse(stdout)
  check.call("default model pair is exact and case-sensitive", status.success? && plan["dit_model"] == "acestep-v15-turbo" && plan["lm_model"] == "acestep-5Hz-lm-0.6B")
  check.call("plan pins source, Python, and Pascal-compatible PyTorch", plan["source_revision"] == "dce621408bee8c31b4fcf4811682eb9359e1bc94" && plan["python"] == "3.12" && plan.dig("pytorch_compatibility_override", "version") == "2.10.0+cu126")
  check.call("plan exposes exact download bytes and no implicit persistence", plan["download_bytes"] == 7_709_375_886 && plan["automatic_download"] == false && plan["persistent_service"] == false && plan["network_listener"] == false)
  check.call("plan stops for review with digest and separate confirmations", plan["lifecycle_state"] == "blocked_for_human_review" && plan["expected_digest"].match?(/\A[0-9a-f]{64}\z/) && plan["setup_confirmation"] != plan["download_confirmation"])

  bad_stdout, = Open3.capture3("ruby", script, "plan", "--manifest", manifest, "--root", pilot_root, "--dit-model", "Acestep-v15-turbo")
  check.call("unknown or case-mismatched checkpoint names fail closed", bad_stdout.empty?)

  _wrong_stdout, _wrong_stderr, wrong_status = Open3.capture3("ruby", script, "setup", "--manifest", manifest, "--root", pilot_root, "--expected-digest", plan["expected_digest"], "--confirmation", "WRONG")
  check.call("wrong confirmation performs no installation", !wrong_status.success? && Dir.children(pilot_root).empty?)
end

source = File.read(script)
makefile = File.read(File.join(root, "Makefile"))
tool_check = File.read(File.join(root, "scripts", "soul-runtime-check.sh"))
check.call("general check labels uv as optional Music tooling", tool_check.include?("Optional Music pilot tools") && tool_check.include?("required only for Music pilot setup"))
check.call("Make defaults are exact but manifest and names are overridable", makefile.include?("MUSIC_MODEL_MANIFEST ?=") && makefile.include?("MUSIC_DIT_MODEL ?= acestep-v15-turbo") && makefile.include?("MUSIC_LM_MODEL ?= acestep-5Hz-lm-0.6B"))
check.call("environment and weights require independent preview gates", makefile.include?("INSTALL_SOUL_MUSIC_PILOT") && makefile.include?("DOWNLOAD_SOUL_MUSIC_MODELS") && source.include?("authorize!(CONFIRMATION)") && source.include?("authorize!(DOWNLOAD_CONFIRMATION)"))
check.call("pilot is foreground, offline, and bounded to approved durations", source.include?("DURATIONS = [30, 90, 180]") && source.include?("HF_HUB_OFFLINE") && source.include?("TRANSFORMERS_OFFLINE") && source.include?("timeout\", \"--signal=INT") && !source.include?("uvicorn"))
check.call("Pascal wheel is probed on the real CUDA device", source.include?("get_device_capability") && source.include?("get_arch_list") && source.include?("sm_61"))

abort "#{failures.length} verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Music Studio A1 setup verification passed."
