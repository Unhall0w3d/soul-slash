#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/application_facade"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

StatusFixture = Struct.new(:record) { def collect = record }
RuntimeFixture = Struct.new(:record) { def status = record }
MusicFixture = Struct.new(:record) { def resource_inventory = record }

Dir.mktmpdir("soul-core-status-") do |root|
  runtime = {
    "ok" => true, "lifecycle_state" => "complete", "data" => {
      "profile" => "amd-gemma", "model_name" => "Gemma 4 12B Instruct Q4_K_M", "runtime" => "ollama_openai",
      "accelerator" => "AMD Vulkan", "core_role" => "daily-chat", "service_state" => "active",
      "server" => { "model_resident" => false }
    }
  }
  music = { "engine" => { "model" => "ACE-Step 1.5", "accelerator" => "NVIDIA CUDA", "residency" => "on_demand", "loaded" => false } }
  facade = SoulCore::ApplicationFacade.new(root:, process_env: {}, status_collector: StatusFixture.new({ "ok" => true, "collected" => { "host" => { "hostname" => "fixture" } } }), model_runtime_control_service: RuntimeFixture.new(runtime), music_generation_service: MusicFixture.new(music))
  envelope = facade.call({ "schema_version" => "soul.application.v1", "request_id" => "core-status", "operation" => "system_status.refresh", "parameters" => {}, "context" => { "interface" => "dashboard_test" } })
  core = envelope.dig("data", "core")
  check.call("System Status exposes Daily Core and exact chat engine identity", core["mode"] == "daily" && core["role"] == "daily-chat" && core.dig("chat_engine", "model") == "Gemma 4 12B Instruct Q4_K_M" && core.dig("chat_engine", "runtime") == "ollama_openai")
  check.call("System Status exposes the on-demand music engine separately", core.dig("music_engine", "model") == "ACE-Step 1.5" && core.dig("music_engine", "residency") == "on_demand")
end

js = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
css = File.read(File.join(__dir__, "../assets/dashboard/dashboard.css"))
check.call("dashboard renders Core chat music runtime and residency fields", %w[Chat\ engine Music\ engine Core\ role model_resident ollama_openai].all? { |value| js.include?(value.gsub("\\ ", " ")) })
check.call("System Status scanner is smaller animated and motion-safe", css.include?("@keyframes system-scan") && css.include?("width:62px") && css.include?("prefers-reduced-motion:reduce"))
check.call("Core status remains event-driven without polling", !js.match?(/setInterval|setTimeout|requestAnimationFrame/))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Gemma Core dashboard identity is candidate-ready."
