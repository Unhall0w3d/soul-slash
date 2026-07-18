#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/music_resource_coordinator"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

result_class = SoulCore::BoundedCommandRunner::Result

class HeadlessProbeRunner
  attr_reader :vulkan_environment

  def initialize(result_class)
    @result_class = result_class
  end

  def run(*command, **options)
    joined = command.join(" ")
    case joined
    when /vulkaninfo --summary/
      @vulkan_environment = options[:env]
      return result("XCB surface connection failed", ok: false) unless @vulkan_environment == { "DISPLAY" => nil, "WAYLAND_DISPLAY" => nil }

      result("deviceName = AMD Radeon RX 6900 XT (RADV NAVI21)\n")
    when /systemctl --user is-active llama-server\.service/
      result("active\n")
    when /systemctl --user is-active soul-model-gemma\.service/
      result("inactive\n", ok: false)
    when /nvidia-smi --query-gpu=memory\.free/
      result("7000\n")
    when /nvidia-smi --query-compute-apps/
      result("")
    when /curl .*\/health/
      result('{"status":"ok"}')
    else
      result("", ok: false)
    end
  end

  private

  def result(stdout, ok: true)
    @result_class.new(stdout: stdout, stderr: "", exit_status: ok ? 0 : 1, status: ok ? "ok" : "failed", truncated: false)
  end
end

puts "Soul Music Vulkan headless-probe verification:"

previous_display = ENV["SOUL_HEADLESS_PROBE_TEST"]
ENV["SOUL_HEADLESS_PROBE_TEST"] = "must-not-leak"
begin
  runner = SoulCore::BoundedCommandRunner.new
  result = runner.run(
    RbConfig.ruby,
    "-e",
    'print ENV.key?("SOUL_HEADLESS_PROBE_TEST") ? ENV.fetch("SOUL_HEADLESS_PROBE_TEST") : "unset"',
    env: { "SOUL_HEADLESS_PROBE_TEST" => nil },
    timeout_seconds: 5,
    max_output_bytes: 128
  )
  check.call("bounded runner can remove one inherited variable for a child only",
             result.success? && result.stdout == "unset" && ENV["SOUL_HEADLESS_PROBE_TEST"] == "must-not-leak")
ensure
  previous_display.nil? ? ENV.delete("SOUL_HEADLESS_PROBE_TEST") : ENV["SOUL_HEADLESS_PROBE_TEST"] = previous_display
end

invalid_environment = SoulCore::BoundedCommandRunner.new.run(RbConfig.ruby, "-e", "exit", env: { :DISPLAY => nil })
check.call("bounded runner rejects malformed environment overrides",
           invalid_environment.status == "failed" && invalid_environment.stderr.include?("ArgumentError"))

Dir.mktmpdir("soul-headless-vulkan-") do |root|
  selection = File.join(root, "Soul/runtime/model_runtime/core_selection.json")
  FileUtils.mkdir_p(File.dirname(selection))
  File.write(selection, JSON.generate(
    "schema_version" => "soul.core_selection.v2",
    "active_core_id" => "music",
    "profiles" => { "music" => "nvidia-fallback" }
  ))
  runner = HeadlessProbeRunner.new(result_class)
  inventory = SoulCore::MusicResourceCoordinator.new(root: root, lane: "amd-music", runner: runner).inventory
  check.call("Music Core inventory uses headless Vulkan enumeration and exposes AMD",
             runner.vulkan_environment == { "DISPLAY" => nil, "WAYLAND_DISPLAY" => nil } &&
               inventory.dig("lanes", "amd-music", "gpu_state") == "available" &&
               inventory["can_acquire_music"] && inventory["blockers"].empty?)
end

if errors.empty?
  puts "PASS: 3 checks"
  exit 0
end

warn "FAIL: #{errors.length} checks failed: #{errors.join(', ')}"
exit 1
