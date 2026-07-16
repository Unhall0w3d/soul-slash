#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/model_runtime_selected_starter"
require_relative "../lib/soul_core/model_runtime_startup_deployment"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def command_result(ok, stdout = "", exit_status = nil)
  SoulCore::BoundedCommandRunner::Result.new(
    stdout: stdout, stderr: "", exit_status: exit_status || (ok ? 0 : 1),
    status: ok ? "ok" : "failed", truncated: false
  )
end

class StartupRunner
  attr_reader :commands
  attr_accessor :states, :fail_start

  def initialize(states)
    @states = states
    @commands = []
    @fail_start = false
  end

  def which(_name) = nil

  def run(*command, **_options)
    @commands << command
    action = command[2]
    service = command[3]
    case action
    when "show"
      command_result(true, "loaded\n")
    when "is-active"
      state = states.fetch(service)
      command_result(state == "active", "#{state}\n", state == "active" ? 0 : 3)
    when "start"
      return command_result(false) if fail_start
      states[service] = "active"
      command_result(true)
    else
      command_result(false)
    end
  end
end

class DeploymentPolicyRunner
  attr_reader :commands
  attr_accessor :selector_enabled, :legacy_enabled, :fail_legacy_disable

  def initialize
    @commands = []
    @selector_enabled = false
    @legacy_enabled = true
    @fail_legacy_disable = false
  end

  def which(_name) = nil

  def run(*command, **_options)
    @commands << command
    return command_result(true) if command.first.end_with?("systemd-analyze")

    action = command[2]
    unit = command[3]
    case action
    when "daemon-reload"
      command_result(true)
    when "is-enabled"
      enabled = unit == SoulCore::ModelRuntimeStartupDeployment::UNIT_NAME ? selector_enabled : legacy_enabled
      command_result(enabled, enabled ? "enabled\n" : "disabled\n", enabled ? 0 : 1)
    when "enable"
      self.selector_enabled = true if unit == SoulCore::ModelRuntimeStartupDeployment::UNIT_NAME
      self.legacy_enabled = true if unit == SoulCore::ModelRuntimeStartupDeployment::LEGACY_UNIT
      command_result(true)
    when "disable"
      return command_result(false) if unit == SoulCore::ModelRuntimeStartupDeployment::LEGACY_UNIT && fail_legacy_disable
      self.selector_enabled = false if unit == SoulCore::ModelRuntimeStartupDeployment::UNIT_NAME
      self.legacy_enabled = false if unit == SoulCore::ModelRuntimeStartupDeployment::LEGACY_UNIT
      command_result(true)
    else
      command_result(false)
    end
  end
end

def executable(path)
  File.write(path, "fixture\n")
  File.chmod(0o700, path)
  path
end

def write_profiles(root)
  path = File.join(root, "config/profiles.yaml")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, <<~YAML)
    schema_version: soul.model_runtime_profiles.v1
    default_profile: nvidia-fallback
    profiles:
      - id: nvidia-fallback
        label: NVIDIA fallback
        service: llama-server.service
      - id: amd-quality
        label: AMD quality
        service: soul-model-amd.service
  YAML
  path
end

def select_profile(root, id)
  directory = File.join(root, "Soul/runtime/model_runtime")
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "selected_profile.json"), JSON.generate("profile_id" => id))
end

puts "Soul selected model-runtime startup verification:"

Dir.mktmpdir("soul-selected-startup-") do |root|
  profile_file = write_profiles(root)
  select_profile(root, "amd-quality")
  env = { "SOUL_MODEL_RUNTIME_PROFILES_FILE" => profile_file }
  systemctl = executable(File.join(root, "systemctl"))

  active_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "active")
  active = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: active_runner, systemctl_path: systemctl).run
  check("selected already active completes without mutation", active.ok && active.details["started"] == false && active_runner.commands.none? { |command| command.include?("start") }, errors)

  idle_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  started = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: idle_runner, systemctl_path: systemctl).run
  starts = idle_runner.commands.select { |command| command[2] == "start" }
  check("all-inactive startup starts only selected allowlisted unit once", started.ok && started.details["started"] && starts == [[systemctl, "--user", "start", "soul-model-amd.service"]], errors)

  conflict_runner = StartupRunner.new("llama-server.service" => "active", "soul-model-amd.service" => "inactive")
  conflict = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: conflict_runner, systemctl_path: systemctl).run
  check("wrong active profile blocks without stop or start", conflict.lifecycle_state == "blocked_for_human_review" && conflict_runner.commands.none? { |command| %w[start stop].include?(command[2]) }, errors)

  failure_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  failure_runner.fail_start = true
  failure = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: failure_runner, systemctl_path: systemctl).run
  check("start failure terminates explicitly without retry or fallback", failure.lifecycle_state == "failed" && failure_runner.commands.count { |command| command[2] == "start" } == 1, errors)

  selection = File.join(root, "Soul/runtime/model_runtime/selected_profile.json")
  File.unlink(selection)
  File.symlink(profile_file, selection)
  unsafe_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  unsafe = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: unsafe_runner, systemctl_path: systemctl).run
  check("symlinked selection fails closed before model mutation", unsafe.lifecycle_state == "blocked_for_human_review" && unsafe_runner.commands.none? { |command| command[2] == "start" }, errors)
end

Dir.mktmpdir("soul-startup-deploy-") do |root|
  home = File.join(root, "home")
  FileUtils.mkdir_p(home)
  ruby = executable(File.join(root, "ruby"))
  systemctl = executable(File.join(root, "systemctl"))
  analyze = executable(File.join(root, "systemd-analyze"))
  script = File.join(root, "scripts/soul-model-runtime-start-selected")
  FileUtils.mkdir_p(File.dirname(script)); File.write(script, "fixture\n")
  runner = DeploymentPolicyRunner.new
  deployment = SoulCore::ModelRuntimeStartupDeployment.new(root: root, home: home, ruby_path: ruby, script_path: script, systemctl_path: systemctl, systemd_analyze_path: analyze, runner: runner)

  plan = deployment.plan
  check("plan is read-only, exact-confirmation, and no-reboot", plan.ok && plan.lifecycle_state == "blocked_for_human_review" && plan.details["confirmation_phrase"] == "INSTALL_SELECTED_MODEL_STARTUP" && plan.details["will_require_reboot"] == false && runner.commands.empty?, errors)

  wrong = deployment.install(confirmation: "INSTALL")
  unit_path = File.join(home, ".config/systemd/user/soul-model-runtime-selected.service")
  check("wrong confirmation writes and executes nothing", wrong.lifecycle_state == "awaiting_input" && !File.exist?(unit_path) && runner.commands.empty?, errors)

  installed = deployment.install(confirmation: "INSTALL_SELECTED_MODEL_STARTUP")
  unit = File.read(unit_path)
  mutations = runner.commands.reject { |command| command.first.end_with?("systemd-analyze") || command[2] == "is-enabled" }
  check("install enables selector and disables legacy startup", installed.ok && runner.selector_enabled && !runner.legacy_enabled, errors)
  check("oneshot unit is bounded and has no daemon or restart policy", unit.include?("Type=oneshot") && unit.include?("WantedBy=default.target") && !unit.include?("Restart=") && unit.include?("RestrictAddressFamilies=AF_UNIX"), errors)
  check("installation never starts, stops, restarts, or uses --now", mutations.none? { |command| command.any? { |part| %w[start stop restart --now].include?(part) } }, errors)
  check("status reports immediate policy activation without reboot", deployment.status.ok && deployment.status.details["selector_enabled"] && !deployment.status.details["legacy_enabled"] && deployment.status.details["reboot_required"] == false, errors)

  repeated_count = runner.commands.length
  repeated = deployment.install(confirmation: "INSTALL_SELECTED_MODEL_STARTUP")
  check("matching installed policy is idempotent", repeated.ok && runner.commands.length > repeated_count && File.read(unit_path) == unit, errors)
end

starter_source = File.read(File.join(__dir__, "../lib/soul_core/model_runtime_selected_starter.rb"))
brief = File.read(File.join(__dir__, "../docs/soul/MODEL_RUNTIME_PORTABILITY_2D_SELECTED_STARTUP_BRIEF.md"))
check("startup source has no automatic stop, enable, disable, or polling", !starter_source.match?(/run_systemctl\("(?:stop|enable|disable|restart)"/) && !starter_source.include?("sleep"), errors)
check("human brief explicitly authorizes the persistent bounded oneshot", brief.include?("persistent_oneshot_authorized: yes") && brief.include?("without requiring a system reboot"), errors)

if errors.empty?
  puts "Verification complete."
  puts "Selected-profile startup is candidate-complete for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
