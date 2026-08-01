#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/dev_model_runtime_coordinator"
require_relative "../lib/soul_core/model_runtime_lease_store"
require_relative "../lib/soul_core/ollama_model_runtime_deployment"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class DevRuntimeRunner
  attr_reader :commands
  attr_accessor :state

  def initialize(state: "inactive")
    @state = state
    @commands = []
  end

  def run(*command, **_options)
    @commands << command
    return result(true) if command.first.end_with?("systemd-analyze") || command[2] == "daemon-reload"
    if command[2] == "show"
      if command.any? { |part| part == "--property=LoadState" }
        return result(true, "loaded")
      end
      property = command.find { |part| part.start_with?("--property=") }&.delete_prefix("--property=")
      return result(true, { "ActiveState" => state, "UnitFileState" => "static" }.fetch(property))
    end
    return result(state == "active", state, state == "active" ? 0 : 3) if command[2] == "is-active"
    if command[2] == "start"
      self.state = "active"
      return result(true)
    end
    if command[2] == "stop"
      self.state = "inactive"
      return result(true)
    end
    result(false)
  end

  private

  def result(ok, stdout = "", exit_status = ok ? 0 : 1)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "#{stdout}\n", stderr: "", exit_status:, status: ok ? "ok" : "failed", truncated: false
    )
  end
end

def executable(path)
  File.write(path, "fixture\n")
  File.chmod(0o700, path)
  path
end

puts "Soul Dev Core runtime verification:"

Dir.mktmpdir("soul-dev-unit-") do |root|
  home = File.join(root, "home")
  FileUtils.mkdir_p(home)
  ollama = executable(File.join(root, "ollama"))
  systemctl = executable(File.join(root, "systemctl"))
  analyze = executable(File.join(root, "systemd-analyze"))
  runner = DevRuntimeRunner.new
  deployment = SoulCore::OllamaModelRuntimeDeployment.new(
    home:, ollama_path: ollama, systemctl_path: systemctl, systemd_analyze_path: analyze, runner:,
    unit_name: SoulCore::DevModelRuntimeCoordinator::UNIT_NAME,
    marker: "# Managed by Soul Dev Core Ollama Runtime Deployment",
    confirm_install: "INSTALL_INACTIVE_DEV_OLLAMA_UNIT",
    confirm_uninstall: "REMOVE_INACTIVE_DEV_OLLAMA_UNIT",
    display_name: "GPT-OSS Dev Core",
    description: "Soul GPT-OSS Dev Core AMD Vulkan Ollama runtime",
    keep_alive: "30m"
  )
  options = {
    expected_ollama_sha256: Digest::SHA256.file(ollama).hexdigest,
    source_model: SoulCore::DevModelRuntimeCoordinator::DEFAULT_MODEL,
    api_model: SoulCore::DevModelRuntimeCoordinator::DEFAULT_MODEL,
    expected_model_digest: SoulCore::DevModelRuntimeCoordinator::DEFAULT_DIGEST,
    port: 18_083
  }
  plan = deployment.plan(**options)
  check.call("Dev unit plan is inactive unenabled and exact", plan.ok && !plan.details["will_start"] && !plan.details["will_enable"] && plan.details["confirmation_phrase"] == "INSTALL_INACTIVE_DEV_OLLAMA_UNIT")
  installed = deployment.install(**options, confirmation: "INSTALL_INACTIVE_DEV_OLLAMA_UNIT")
  unit = File.read(File.join(home, ".config/systemd/user/soul-model-dev.service"))
  check.call("Dev unit uses a separate loopback Vulkan endpoint", installed.ok && unit.include?("OLLAMA_HOST=127.0.0.1:18083") && unit.include?("OLLAMA_VULKAN=1") && unit.include?("OLLAMA_MAX_LOADED_MODELS=1"))
  check.call("Dev unit cannot start at login", !unit.include?("[Install]") && runner.commands.none? { |command| command.include?("enable") || command.include?("start") })
end

Dir.mktmpdir("soul-dev-coordinator-") do |root|
  runner = DevRuntimeRunner.new
  loaded = false
  posts = []
  http_get = lambda do |uri|
    case uri.path
    when "/api/version" then { status: runner.state == "active" ? 200 : 503, body: '{}' }
    when "/api/ps"
      models = loaded ? [{ "name" => "gpt-oss:20b", "digest" => SoulCore::DevModelRuntimeCoordinator::DEFAULT_DIGEST, "size" => 12, "size_vram" => 12 }] : []
      { status: 200, body: JSON.generate("models" => models) }
    else { status: 404, body: "" }
    end
  end
  http_post = lambda do |_uri, payload|
    posts << payload
    loaded = true
    { status: 200, body: '{"done":true}' }
  end
  coordinator = SoulCore::DevModelRuntimeCoordinator.new(
    root:, runner:, http_get:, http_post:, sleeper: ->(_seconds) {},
    monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  )
  selected = coordinator.activate_selected
  check.call("selected Dev Core starts and pins only the reviewed digest", selected["ok"] && runner.state == "active" && posts.last["keep_alive"] == -1)
  stopped = coordinator.deactivate_selected
  check.call("leaving selected Dev Core unloads its service", stopped["ok"] && runner.state == "inactive")

  loaded = false
  value, receipt = coordinator.with_request(request_id: "dev_fixture", purpose: "bounded verifier", selected_core: false) { |runtime| runtime.fetch("model") }
  check.call("scoped Dev work starts, returns, releases, and stops", value == "gpt-oss:20b" && receipt["selected_core"] == false && runner.state == "inactive" && coordinator.status.dig("data", "active_work_count").zero?)

  lease_store = SoulCore::ModelRuntimeLeaseStore.new(root:)
  held = lease_store.acquire_exclusive(provider_id: "music.fixture", model_id: "ace", request_id: "music", resource_group: SoulCore::DevModelRuntimeCoordinator::RESOURCE_GROUP, ttl_seconds: 60)
  blocked = coordinator.activate_selected
  check.call("creative ownership blocks Dev activation before service mutation", !blocked["ok"] && blocked["lifecycle_state"] == "awaiting_input" && runner.state == "inactive")
  lease_store.release(held.fetch("lease_id"))
end

js = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
brief = File.read(File.join(__dir__, "../docs/soul/DEV_CORE_GPT_OSS_INTEGRATION_BRIEF.md"))
draft = File.read(File.join(__dir__, "../Soul/skills/skill/brief/draft.rb"))
review = File.read(File.join(__dir__, "../Soul/skills/skill/brief/review.rb"))
check.call("Free Core has a modal inert-dashboard selection surface", html.include?('aria-labelledby="core-unavailable-title"') && js.include?('element.inert = locked') && js.include?('mode === "free"'))
check.call("Free Core lock survives a transient Core-status failure", js.include?('window.sessionStorage.setItem("soul-core-unloaded"') && js.include?('state.coreLocked || window.sessionStorage.getItem("soul-core-unloaded") === "1"'))
check.call("brief draft and review are local-first with explicit-only cloud fallback",
           [draft, review].all? { |source| source.include?("draft_with_local") || source.include?("review_with_local") } &&
             [draft, review].all? { |source| source.include?('option_value("--provider")') && source.include?("LocalDevelopmentModelClient") })
check.call("approved brief preserves local-first fallback and Vault boundaries", brief.include?("explicit configured Mistral fallback") && brief.include?("do not automatically ingest or\nwrite it"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Dev Core runtime is candidate-ready for human review."
