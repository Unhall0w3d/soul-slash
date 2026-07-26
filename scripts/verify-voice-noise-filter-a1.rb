#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

Dir.mktmpdir("soul-rnnoise-test-") do |root|
  command = [
    { "SOUL_RNNOISE_SKIP_RESTART" => "1" },
    "ruby", File.expand_path("soul-voice-noise-filter", __dir__),
    "--config-root", root, "--source", "fixture.microphone", "plan"
  ]
  output, status = Open3.capture2e(*command)
  plan = JSON.parse(output)
  check.call("plan is read-only and exact-confirmation gated", status.success? && plan["lifecycle_state"] == "blocked_for_human_review" && plan["confirmation_phrase"] == "INSTALL_SOUL_RNNOISE_FILTER")
  destination = plan.fetch("destination")
  check.call("plan writes no persistent configuration", !File.exist?(destination))

  install = command.dup
  install[-1] = "install"
  install.insert(-1, "--expected-digest", plan.fetch("expected_digest"), "--confirmation", plan.fetch("confirmation_phrase"))
  output, status = Open3.capture2e(*install)
  result = JSON.parse(output)
  config = File.binread(destination)
  check.call("exact install creates one bounded user configuration", status.success? && result["configured"] && File.stat(destination).mode & 0o777 == 0o600)
  check.call("configuration is mono RNNoise bound to the reviewed source", config.include?("noise_suppressor_mono") && config.include?('target.object = "fixture.microphone"') && config.include?("effect_output.soul-rnnoise"))
  check.call("test installation never restarts an audio service", result["activated"] == false)
  check_output, check_status = Open3.capture2e(
    { "SOUL_RNNOISE_SKIP_RESTART" => "1" },
    "ruby", File.expand_path("soul-voice-noise-filter", __dir__),
    "--config-root", root, "--source", "fixture.microphone", "check"
  )
  check_result = JSON.parse(check_output)
  check.call("installed configuration validates idempotently", check_status.success? && check_result["configured"])
end

source = File.read(File.expand_path("soul-voice-noise-filter", __dir__))
brief = File.read(File.expand_path("../docs/soul/VOICE_NOISE_FILTER_A1_BRIEF.md", __dir__))
check.call("failure path removes generated configuration", source.include?("FileUtils.rm_f(destination)"))
check.call("brief explicitly authorizes only an existing audio-stack restart", brief.include?("persistent user audio configuration") && brief.include?("No new service"))

abort "Voice noise-filter verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Voice noise-filter A1 candidate verification passed."
