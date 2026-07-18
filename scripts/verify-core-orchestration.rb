#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/core_orchestration_service"
require_relative "../lib/soul_core/model_runtime_control_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class CoreRunner
  attr_reader :states, :mutations

  def initialize(states)
    @states = states
    @mutations = []
  end

  def run(*command, **_options)
    action = command.fetch(2)
    unit = command.fetch(3)
    case action
    when "show" then result(states.key?(unit), states.key?(unit) ? "loaded\n" : "not-found\n")
    when "is-active"
      state = states.fetch(unit, "unknown")
      result(state == "active", "#{state}\n", state == "active" ? 0 : 3)
    when "is-enabled" then result(true, "enabled\n")
    when "start"
      @mutations << [action, unit]
      states[unit] = "active"
      result(true)
    when "stop"
      @mutations << [action, unit]
      states[unit] = "inactive"
      result(true)
    else result(false)
    end
  end

  private

  def result(ok, stdout = "", exit_status = ok ? 0 : 1)
    SoulCore::BoundedCommandRunner::Result.new(stdout:, stderr: "", exit_status:, status: ok ? "ok" : "failed", truncated: false)
  end
end

def write_profiles(root)
  path = File.join(root, "Soul/config/core-runtime.local.yaml")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, <<~YAML)
    schema_version: soul.model_runtime_profiles.v3
    default_profile: amd-quality
    profiles:
      - id: nvidia-fallback
        label: NVIDIA fallback
        model_name: Qwen3 8B Q4_K_M
        api_model: soul-local-chat
        runtime: llamacpp_openai
        accelerator: NVIDIA CUDA
        service: llama-server.service
        endpoint: http://127.0.0.1:8082/v1
        core_role: reserve-chat
      - id: amd-quality
        label: AMD quality
        model_name: Ministral 3 14B Q4_K_M
        api_model: soul-local-chat
        runtime: llamacpp_openai
        accelerator: AMD Vulkan
        service: soul-model-amd.service
        endpoint: http://127.0.0.1:8082/v1
        core_role: daily-chat
      - id: amd-gemma
        label: AMD Gemma candidate
        model_name: Gemma 4 12B Q4_K_M
        api_model: soul-local-chat
        runtime: llamacpp_openai
        accelerator: AMD Vulkan
        service: soul-model-gemma.service
        endpoint: http://127.0.0.1:8082/v1
        core_role: daily-chat
  YAML
  "Soul/config/core-runtime.local.yaml"
end

def request(operation, parameters = {})
  { "schema_version" => "soul.application.v1", "request_id" => "core-#{operation.tr('.', '-')}",
    "operation" => operation, "parameters" => parameters, "context" => { "interface" => "dashboard_test" } }
end

puts "Soul Core orchestration verification:"

Dir.mktmpdir("soul-core-orchestration-") do |root|
  file = write_profiles(root)
  runner = CoreRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "active", "soul-model-gemma.service" => "inactive")
  http_get = lambda do |uri|
    case uri.path
    when "/slots" then { status: 200, body: '[{"is_processing":false}]' }
    when "/metrics" then { status: 200, body: "llamacpp:requests_processing 0\nllamacpp:requests_deferred 0\n" }
    when "/health" then { status: 200, body: '{"status":"ok"}' }
    end
  end
  env = { "SOUL_MODEL_RUNTIME_CONTROL" => "1", "SOUL_MODEL_RUNTIME_PROFILES_FILE" => file,
          "SOUL_LOCAL_OPENAI_MODEL" => "soul-local-chat" }
  runtime = SoulCore::ModelRuntimeControlService.new(root:, env:, runner:, http_get:)
  cores = SoulCore::CoreOrchestrationService.new(root:, runtime_control: runtime, env:)

  status = cores.status
  check.call("explicit roles form Daily and AMD-Free Cores", status["ok"] && status.dig("data", "cores").map { |core| core["id"] } == %w[daily amd-free])
  check.call("active Daily Core keeps NVIDIA available for Music Studio", status.dig("data", "active_core_id") == "daily" && status.dig("data", "music_lane", "available_in_active_core") == true)
  check.call("Daily fallback target is the first configured Daily profile", status.dig("data", "cores", 0, "target_profile", "id") == "amd-quality")

  preview = cores.preview(core_id: "amd-free")
  check.call("Core preview delegates the exact runtime confirmation", preview["ok"] && preview.dig("data", "confirmation_phrase") == "SWITCH_MODEL_RUNTIME_TO_NVIDIA_FALLBACK" && runner.mutations.empty?)
  stale = cores.execute(core_id: "amd-free", target_profile_id: "nvidia-fallback", confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: "0" * 64)
  check.call("stale Core digest blocks before service mutation", stale["lifecycle_state"] == "blocked_for_human_review" && runner.mutations.empty?)

  switched = cores.execute(core_id: "amd-free", target_profile_id: "nvidia-fallback", confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  selection_path = File.join(root, SoulCore::CoreOrchestrationService::SELECTION_PATH)
  selection = JSON.parse(File.read(selection_path))
  check.call("exact Core activation uses the reviewed stop-start controller", switched["ok"] && runner.mutations == [["stop", "soul-model-amd.service"], ["start", "llama-server.service"]])
  check.call("successful activation records only bounded per-Core profile choices", selection == { "schema_version" => "soul.core_selection.v1", "profiles" => { "amd-free" => "nvidia-fallback", "daily" => "amd-quality" } })
  check.call("AMD-Free Core discloses NVIDIA music contention", switched.dig("data", "active_core_id") == "amd-free" && switched.dig("data", "music_lane", "available_in_active_core") == false && switched.dig("data", "music_lane", "conflict").include?("NVIDIA chat"))

  return_preview = cores.preview(core_id: "daily")
  check.call("returning to Daily restores its recorded profile", return_preview.dig("data", "target_profile", "id") == "amd-quality")
  wrong_target = cores.execute(core_id: "daily", target_profile_id: "amd-gemma", confirmation: return_preview.dig("data", "confirmation_phrase"), expected_digest: return_preview.dig("data", "expected_digest"))
  check.call("execution cannot substitute another profile after preview", wrong_target["lifecycle_state"] == "blocked_for_human_review")

  facade = SoulCore::ApplicationFacade.new(root:, process_env: {}, core_orchestration_service: cores, model_runtime_control_service: runtime)
  facade_status = facade.call(request("core.status"))
  facade_preview = facade.call(request("core.activate.preview", "core_id" => "daily"))
  check.call("application contract exposes authenticated Core status and preview", facade_status["lifecycle_state"] == "complete" && facade_preview["lifecycle_state"] == "complete")
end

Dir.mktmpdir("soul-core-selection-integrity-") do |root|
  file = write_profiles(root)
  runner = CoreRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "active", "soul-model-gemma.service" => "inactive")
  env = { "SOUL_MODEL_RUNTIME_CONTROL" => "1", "SOUL_MODEL_RUNTIME_PROFILES_FILE" => file, "SOUL_LOCAL_OPENAI_MODEL" => "soul-local-chat" }
  http_get = ->(uri) { uri.path == "/slots" ? { status: 200, body: '[{"is_processing":false}]' } : { status: 200, body: "" } }
  runtime = SoulCore::ModelRuntimeControlService.new(root:, env:, runner:, http_get:)
  path = File.join(root, SoulCore::CoreOrchestrationService::SELECTION_PATH)
  FileUtils.mkdir_p(File.dirname(path)); File.symlink("missing-target", path)
  result = SoulCore::CoreOrchestrationService.new(root:, runtime_control: runtime, env:).status
  check.call("symlinked Core selection blocks safely", result["lifecycle_state"] == "blocked_for_human_review" && result["reason"].include?("non-symlink"))
end

js = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
brief = File.read(File.join(__dir__, "../docs/soul/CORE_ORCHESTRATION_A0_A1_BRIEF.md"))
check.call("top bar exposes an explicit Core selector beside Local", html.include?('id="connection-label"') && html.include?('id="core-selector"') && html.index('id="connection-label"') < html.index('id="core-selector"'))
check.call("dashboard uses the Core application gate rather than direct service control", js.include?('core.activate.preview') && js.include?('core.activate.execute') && js.include?('prefillApprovalGate("model-runtime-confirmation"'))
check.call("Core interface remains event-driven without polling", !js.match?(/setInterval|setTimeout|requestAnimationFrame/))
check.call("brief preserves Qwen and ACE-Step mutual exclusion", brief.include?("Qwen fallback and\nACE-Step share the NVIDIA lane") && brief.include?("No attempt is made to run Qwen and ACE-Step concurrently"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Core orchestration is candidate-ready for human review."
