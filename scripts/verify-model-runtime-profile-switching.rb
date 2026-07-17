#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/model_runtime_control_service"
require_relative "../lib/soul_core/model_runtime_profile_registry"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def configuration_error?(registry)
  registry.configuration
  false
rescue SoulCore::ModelRuntimeProfileRegistry::ConfigurationError
  true
end

class ProfileRunner
  attr_reader :states, :mutations
  attr_accessor :fail_start

  def initialize(states)
    @states = states
    @mutations = []
    @fail_start = nil
  end

  def run(*command, **_options)
    action = command.fetch(2)
    unit = command.fetch(3)
    case action
    when "show"
      result(true, states.key?(unit) ? "loaded\n" : "not-found\n", 0)
    when "is-active"
      state = states.fetch(unit, "unknown")
      result(state == "active", "#{state}\n", state == "active" ? 0 : 3)
    when "is-enabled"
      result(true, "enabled\n", 0)
    when "start"
      @mutations << [action, unit]
      return result(false, "", 1) if fail_start == unit

      states[unit] = "active"
      result(true, "", 0)
    when "stop"
      @mutations << [action, unit]
      states[unit] = "inactive"
      result(true, "", 0)
    else
      result(false, "", 1)
    end
  end

  private

  def result(ok, stdout, exit_status)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: exit_status, status: ok ? "ok" : "failed", truncated: false)
  end
end

def write_profiles(root, body)
  path = File.join(root, "Soul/config/runtime.local.yaml")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
  "Soul/config/runtime.local.yaml"
end

def valid_profiles(extra: "")
  <<~YAML
    schema_version: soul.model_runtime_profiles.v2
    default_profile: nvidia-fallback
    profiles:
      - id: nvidia-fallback
        label: NVIDIA fallback
        model_name: Qwen3 8B Q4_K_M
        accelerator: NVIDIA CUDA
        service: llama-server.service
      - id: amd-quality
        label: AMD quality
        model_name: Ministral 3 14B Instruct 2512 Q4_K_M
        accelerator: AMD Vulkan
        service: soul-model-amd.service
    #{extra}
  YAML
end

puts "Soul Model Runtime Profile Switching verification:"

Dir.mktmpdir("soul-runtime-profiles-") do |root|
  file = write_profiles(root, valid_profiles)
  runner = ProfileRunner.new("llama-server.service" => "active", "soul-model-amd.service" => "inactive")
  active_slots = 0
  reachable = true
  http_get = lambda do |uri|
    case uri.path
    when "/slots" then reachable ? { status: 200, body: JSON.generate([{ "is_processing" => active_slots.positive? }]) } : nil
    when "/metrics" then { status: 200, body: "llamacpp:requests_processing 0\nllamacpp:requests_deferred 0\n" }
    when "/health" then { status: 200, body: '{"status":"ok"}' }
    end
  end
  env = {
    "SOUL_MODEL_RUNTIME_CONTROL" => "1",
    "SOUL_MODEL_RUNTIME_PROFILES_FILE" => file,
    "SOUL_MODEL_RUNTIME_SLOTS_URL" => "http://127.0.0.1:8082/slots",
    "SOUL_LOCAL_OPENAI_BASE_URL" => "http://127.0.0.1:8082/v1",
    "SOUL_LOCAL_OPENAI_MODEL" => "soul-primary"
  }
  service = SoulCore::ModelRuntimeControlService.new(root: root, env: env, runner: runner, http_get: http_get)

  status = service.status
  check("status exposes two bounded profiles and the active rollback", status["ok"] && status.dig("data", "profiles").length == 2 && status.dig("data", "active_profile_id") == "nvidia-fallback" && status.dig("data", "can_switch"), errors)
  check("status separates actual profile identity from neutral API alias", status.dig("data", "model_name") == "Qwen3 8B Q4_K_M" && status.dig("data", "accelerator") == "NVIDIA CUDA" && status.dig("data", "api_alias") == "soul-primary", errors)
  check("status exposes selected-profile startup policy without mutation", status.dig("data", "startup", "enabled") == true && status.dig("data", "startup", "selected_profile_id") == "nvidia-fallback" && runner.mutations.empty?, errors)

  preview = service.preview(action: "switch", profile_id: "amd-quality")
  check("switch preview is target-bound and read-only", preview["ok"] && preview.dig("data", "confirmation_phrase") == "SWITCH_MODEL_RUNTIME_TO_AMD_QUALITY" && runner.mutations.empty?, errors)
  stale = service.execute(action: "switch", profile_id: "amd-quality", confirmation: "SWITCH_MODEL_RUNTIME_TO_AMD_QUALITY", expected_digest: "0" * 64)
  check("changed switch digest blocks before service mutation", stale["lifecycle_state"] == "blocked_for_human_review" && runner.mutations.empty?, errors)

  active_slots = 1
  busy = service.preview(action: "switch", profile_id: "amd-quality")
  check("active slot blocks switching", busy["lifecycle_state"] == "blocked_for_human_review" && runner.mutations.empty?, errors)
  active_slots = 0

  switched = service.execute(action: "switch", profile_id: "amd-quality", confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  selection = JSON.parse(File.read(File.join(root, "Soul/runtime/model_runtime/selected_profile.json")))
  check("verified switch stops rollback then starts AMD", switched["ok"] && runner.mutations == [["stop", "llama-server.service"], ["start", "soul-model-amd.service"]] && runner.states["soul-model-amd.service"] == "active", errors)
  check("successful switch persists only selected profile ID", selection == { "profile_id" => "amd-quality" }, errors)

  runner.states["llama-server.service"] = "active"
  conflict = service.status
  check("multiple active profiles create a blocking conflict", conflict.dig("data", "profile_conflict") == true && !conflict.dig("data", "can_unload") && service.preview(action: "unload")["lifecycle_state"] == "blocked_for_human_review", errors)

  runner.states["llama-server.service"] = "inactive"
  runner.states["soul-model-amd.service"] = "inactive"
  load = service.preview(action: "load", profile_id: "nvidia-fallback")
  loaded = service.execute(action: "load", profile_id: "nvidia-fallback", confirmation: load.dig("data", "confirmation_phrase"), expected_digest: load.dig("data", "expected_digest"))
  check("all-unloaded state permits explicit profile load", load.dig("data", "confirmation_phrase") == "LOAD_MODEL_RUNTIME_NVIDIA_FALLBACK" && loaded["ok"] && runner.states["llama-server.service"] == "active", errors)

  facade = SoulCore::ApplicationFacade.new(root: root, process_env: {}, model_runtime_control_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1", "request_id" => "runtime-switch-preview",
    "operation" => "model_runtime.switch.preview", "parameters" => { "profile_id" => "amd-quality" },
    "context" => { "interface" => "dashboard_test" }
  })
  check("application facade exposes explicit switch preview", envelope["operation"] == "model_runtime.switch.preview" && envelope["lifecycle_state"] == "complete", errors)

  runner.states.delete("soul-model-amd.service")
  missing = service.status
  blocked_missing = service.preview(action: "switch", profile_id: "amd-quality")
  check("missing target unit is unavailable and cannot be switched to", missing.dig("data", "profiles").find { |profile| profile["id"] == "amd-quality" }["service_state"] == "unavailable" && blocked_missing["lifecycle_state"] == "blocked_for_human_review", errors)
end

Dir.mktmpdir("soul-runtime-switch-failure-") do |root|
  file = write_profiles(root, valid_profiles)
  runner = ProfileRunner.new("llama-server.service" => "active", "soul-model-amd.service" => "inactive")
  runner.fail_start = "soul-model-amd.service"
  http_get = ->(uri) { uri.path == "/slots" ? { status: 200, body: '[{"is_processing":false}]' } : { status: 200, body: "" } }
  env = { "SOUL_MODEL_RUNTIME_CONTROL" => "1", "SOUL_MODEL_RUNTIME_PROFILES_FILE" => file,
          "SOUL_MODEL_RUNTIME_SLOTS_URL" => "http://127.0.0.1:8082/slots", "SOUL_LOCAL_OPENAI_MODEL" => "soul-primary" }
  service = SoulCore::ModelRuntimeControlService.new(root: root, env: env, runner: runner, http_get: http_get)
  preview = service.preview(action: "switch", profile_id: "amd-quality")
  result = service.execute(action: "switch", profile_id: "amd-quality", confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  check("failed target start stops and reports partial work without rollback", result["lifecycle_state"] == "failed" && result.dig("data", "completed") == [{ "action" => "stop", "profile_id" => "nvidia-fallback" }] && result.dig("data", "rollback_profile_id") == "nvidia-fallback" && runner.mutations == [["stop", "llama-server.service"], ["start", "soul-model-amd.service"]], errors)
end

Dir.mktmpdir("soul-runtime-profile-validation-") do |root|
  env = { "SOUL_MODEL_RUNTIME_SERVICE" => "llama-server.service" }
  outside = File.join(Dir.tmpdir, "outside-runtime-profiles-#{Process.pid}.yaml")
  File.write(outside, valid_profiles)
  traversal = SoulCore::ModelRuntimeProfileRegistry.new(root: root, env: env.merge("SOUL_MODEL_RUNTIME_PROFILES_FILE" => outside))
  check("profile inventory cannot escape project root", configuration_error?(traversal), errors)

  path = File.join(root, "Soul/config/runtime.local.yaml")
  FileUtils.mkdir_p(File.dirname(path))
  File.symlink(outside, path)
  symlink = SoulCore::ModelRuntimeProfileRegistry.new(root: root, env: env.merge("SOUL_MODEL_RUNTIME_PROFILES_FILE" => "Soul/config/runtime.local.yaml"))
  check("symlinked profile inventory fails closed", configuration_error?(symlink), errors)
  File.unlink(path)

  duplicate = valid_profiles.sub("service: soul-model-amd.service", "service: llama-server.service")
  write_profiles(root, duplicate)
  registry = SoulCore::ModelRuntimeProfileRegistry.new(root: root, env: env.merge("SOUL_MODEL_RUNTIME_PROFILES_FILE" => "Soul/config/runtime.local.yaml"))
  check("duplicate service inventory fails closed", configuration_error?(registry), errors)

  invalid_documents = {
    "duplicate profile IDs fail closed" => valid_profiles.sub("id: amd-quality", "id: nvidia-fallback"),
    "invalid default profile fails closed" => valid_profiles.sub("default_profile: nvidia-fallback", "default_profile: missing"),
    "unknown profile keys fail closed" => valid_profiles.sub("service: soul-model-amd.service", "service: soul-model-amd.service\n        command: unsafe"),
    "arbitrary units fail closed" => valid_profiles.sub("service: soul-model-amd.service", "service: ssh.service"),
    "more than four profiles fail closed" => valid_profiles +
      "  - id: third-profile\n    label: Third\n    model_name: Third Model\n    accelerator: Test\n    service: soul-third.service\n" \
      "  - id: fourth-profile\n    label: Fourth\n    model_name: Fourth Model\n    accelerator: Test\n    service: soul-fourth.service\n" \
      "  - id: fifth-profile\n    label: Fifth\n    model_name: Fifth Model\n    accelerator: Test\n    service: soul-fifth.service\n"
  }
  invalid_documents.each do |label, document|
    write_profiles(root, document)
    invalid = SoulCore::ModelRuntimeProfileRegistry.new(root: root, env: env.merge("SOUL_MODEL_RUNTIME_PROFILES_FILE" => "Soul/config/runtime.local.yaml"))
    check(label, configuration_error?(invalid), errors)
  end
ensure
  FileUtils.rm_f(outside)
end

dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
brief = File.read(File.join(__dir__, "../docs/soul/MODEL_RUNTIME_PORTABILITY_2_BRIEF.md"))
check("dashboard renders explicit profiles and switch actions", html.include?('id="runtime-profile-list"') && dashboard.include?('previewModelRuntime(action, profileId = null)') && dashboard.include?('action = "switch"'), errors)
check("dashboard distinguishes model identity, accelerator, API alias, and startup selection", %w[model_name accelerator api_alias selected_profile_id].all? { |field| dashboard.include?(field) }, errors)
check("profile dashboard remains timer-free", !dashboard.match?(/setInterval|setTimeout|requestAnimationFrame/), errors)
check("approved brief keeps host deployment behind a later gate", brief.include?("implementation_authorized: yes") && brief.include?("must not create, install, enable, start, stop, or modify the AMD"), errors)

if errors.empty?
  puts "Verification complete."
  puts "Model Runtime Portability 2A is candidate-complete for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
