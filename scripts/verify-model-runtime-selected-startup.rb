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
  attr_accessor :states, :fail_start, :fail_stop, :gpu_uuid, :gpu_memory_mib, :gpu_probe_delay, :gpu_rows

  def initialize(states)
    @states = states
    @commands = []
    @fail_start = false
    @fail_stop = false
    @gpu_uuid = "GPU-92d94102-e241-1a40-62c5-832d60874aab"
    @gpu_memory_mib = 5296
    @gpu_probe_delay = 0
    @gpu_rows = nil
  end

  def which(_name) = nil

  def run(*command, **_options)
    @commands << command
    if command.first.end_with?("nvidia-smi")
      if command.include?("--query-gpu=uuid")
        return command_result(true, "#{gpu_uuid}\n")
      end
      if command.any? { |part| part.start_with?("--query-compute-apps=") }
        if gpu_probe_delay.positive?
          self.gpu_probe_delay -= 1
          return command_result(true, "")
        end
        return command_result(true, gpu_rows || "4242, #{gpu_uuid}, #{gpu_memory_mib}\n")
      end
    end
    action = command[2]
    service = command[3]
    case action
    when "show"
      command_result(true, command.include?("--property=MainPID") ? "4242\n" : "loaded\n")
    when "is-active"
      state = states.fetch(service)
      command_result(state == "active", "#{state}\n", state == "active" ? 0 : 3)
    when "start"
      return command_result(false) if fail_start
      states[service] = "active"
      command_result(true)
    when "stop"
      return command_result(false) if fail_stop
      states[service] = "inactive"
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

  core_selection = File.join(root, "Soul/runtime/model_runtime/core_selection.json")
  core_record = { "schema_version" => "soul.core_selection.v2", "active_core_id" => "free", "profiles" => {} }
  File.write(core_selection, JSON.generate(core_record))
  free_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  free = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: free_runner, systemctl_path: systemctl).run
  check("Free Core suppresses remembered model startup", free.ok && free.details["active_core_id"] == "free" && !free.details["started"] && free_runner.commands.none? { |command| %w[start stop restart].include?(command[2]) }, errors)

  free_active_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "active")
  free_active = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: free_active_runner, systemctl_path: systemctl).run
  check("Free Core with active chat blocks without automatic stop", free_active.lifecycle_state == "blocked_for_human_review" && free_active_runner.commands.none? { |command| %w[start stop restart].include?(command[2]) }, errors)

  ["{", "[]", JSON.generate(core_record.merge("active_core_id" => "unknown")), JSON.generate(core_record.merge("profiles" => { "daily" => "foreign" })), " " * 4097].each_with_index do |body, index|
    File.write(core_selection, body)
    runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
    result = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: runner, systemctl_path: systemctl).run
    check("invalid Core record #{index} blocks before commands", result.lifecycle_state == "blocked_for_human_review" && runner.commands.empty?, errors)
  end
  File.unlink(core_selection)
  File.symlink(profile_file, core_selection)
  runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  result = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: runner, systemctl_path: systemctl).run
  check("symlinked Core record blocks before commands", result.lifecycle_state == "blocked_for_human_review" && runner.commands.empty?, errors)
  File.unlink(core_selection)
  [core_record.merge("active_core_id" => "daily"), { "schema_version" => "soul.core_selection.v1", "profiles" => {} }].each do |record|
    File.write(core_selection, JSON.generate(record))
    runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
    result = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: runner, systemctl_path: systemctl).run
    check("#{record['schema_version']} non-Free startup remains selected-profile based", result.ok && result.details["started"] && runner.commands.count { |command| command[2] == "start" } == 1, errors)
  end
  File.unlink(core_selection)

  selection = File.join(root, "Soul/runtime/model_runtime/selected_profile.json")
  File.unlink(selection)
  File.symlink(profile_file, selection)
  unsafe_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  unsafe = SoulCore::ModelRuntimeSelectedStarter.new(root: root, env: env, runner: unsafe_runner, systemctl_path: systemctl).run
  check("symlinked selection fails closed before model mutation", unsafe.lifecycle_state == "blocked_for_human_review" && unsafe_runner.commands.none? { |command| command[2] == "start" }, errors)
end

Dir.mktmpdir("soul-nvidia-startup-") do |root|
  profile_file = File.join(root, "config/profiles.yaml")
  FileUtils.mkdir_p(File.dirname(profile_file))
  File.write(profile_file, <<~YAML)
    schema_version: soul.model_runtime_profiles.v2
    default_profile: nvidia-fallback
    profiles:
      - id: nvidia-fallback
        label: NVIDIA fallback
        model_name: Qwen3 8B
        accelerator: NVIDIA CUDA
        service: llama-server.service
      - id: amd-quality
        label: AMD quality
        model_name: Ministral
        accelerator: AMD Vulkan
        service: soul-model-amd.service
  YAML
  systemctl = executable(File.join(root, "systemctl"))
  nvidia_smi = executable(File.join(root, "nvidia-smi"))
  env = { "SOUL_MODEL_RUNTIME_PROFILES_FILE" => profile_file }

  make_start = lambda do |states:, device_ready:, runner: nil|
    runner ||= StartupRunner.new(states)
    elapsed = [0.0]
    starter = SoulCore::ModelRuntimeSelectedStarter.new(
      root: root, env: env, runner: runner, systemctl_path: systemctl,
      nvidia_smi_path: nvidia_smi, nvidia_device_ready: device_ready,
      monotonic_clock: -> { elapsed[0] }, sleeper: ->(seconds) { elapsed[0] += seconds }
    )
    [starter.run, runner, elapsed[0]]
  end

  checks = 0
  delayed_device = -> { checks += 1; checks >= 4 }
  delayed_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  delayed_runner.gpu_probe_delay = 2
  delayed, delayed_runner, elapsed = make_start.call(states: delayed_runner.states, device_ready: delayed_device, runner: delayed_runner)
  check("late NVIDIA nodes and model allocation complete with one start", delayed.ok && delayed.details["started"] &&
        delayed_runner.commands.count { |command| command[2] == "start" } == 1 &&
        delayed_runner.commands.none? { |command| command[2] == "stop" } && elapsed >= 1.25, errors)

  absent_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  absent, absent_runner, elapsed = make_start.call(states: absent_runner.states, device_ready: -> { false }, runner: absent_runner)
  check("missing NVIDIA nodes fail before model start within bound", absent.lifecycle_state == "failed" &&
        absent_runner.commands.none? { |command| %w[start stop].include?(command[2]) } && elapsed <= 15, errors)

  cpu_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  cpu_runner.gpu_memory_mib = 0
  cpu, cpu_runner, elapsed = make_start.call(states: cpu_runner.states, device_ready: -> { true }, runner: cpu_runner)
  check("CPU fallback is stopped after bounded placement failure", cpu.lifecycle_state == "failed" &&
        cpu_runner.commands.count { |command| command[2] == "start" } == 1 &&
        cpu_runner.commands.count { |command| command[2] == "stop" } == 1 &&
        cpu_runner.states["llama-server.service"] == "inactive" && elapsed <= 30, errors)

  failed_stop_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  failed_stop_runner.gpu_memory_mib = 0
  failed_stop_runner.fail_stop = true
  failed_stop, _, = make_start.call(states: failed_stop_runner.states, device_ready: -> { true }, runner: failed_stop_runner)
  check("failed CPU fallback cleanup is explicit", failed_stop.lifecycle_state == "failed" &&
        failed_stop.message.include?("cleanup failed") && failed_stop.details["cleanup_state"] == "active", errors)

  existing_runner = StartupRunner.new("llama-server.service" => "active", "soul-model-amd.service" => "inactive")
  existing_runner.gpu_memory_mib = 0
  existing, existing_runner, = make_start.call(states: existing_runner.states, device_ready: -> { true }, runner: existing_runner)
  check("preexisting CPU-backed Qwen blocks without mutation", existing.lifecycle_state == "blocked_for_human_review" &&
        existing_runner.commands.none? { |command| %w[start stop].include?(command[2]) }, errors)

  healthy_runner = StartupRunner.new("llama-server.service" => "active", "soul-model-amd.service" => "inactive")
  healthy, healthy_runner, = make_start.call(states: healthy_runner.states, device_ready: -> { true }, runner: healthy_runner)
  check("preexisting GPU-backed Qwen completes without mutation", healthy.ok && !healthy.details["started"] &&
        healthy_runner.commands.none? { |command| %w[start stop].include?(command[2]) }, errors)

  foreign_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  foreign_runner.gpu_rows = "7777, #{foreign_runner.gpu_uuid}, 5296\n"
  foreign, foreign_runner, = make_start.call(states: foreign_runner.states, device_ready: -> { true }, runner: foreign_runner)
  check("foreign GPU allocation cannot prove Qwen placement", foreign.lifecycle_state == "failed" &&
        foreign_runner.commands.count { |command| command[2] == "stop" } == 1, errors)
  select_profile(root, "amd-quality")
  amd_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  amd, amd_runner, = make_start.call(states: amd_runner.states, device_ready: -> { false }, runner: amd_runner)
  check("AMD selection starts without NVIDIA guard", amd.ok &&
        amd_runner.commands.count { |command| command[2] == "start" } == 1 &&
        amd_runner.commands.none? { |command| command.first.end_with?("nvidia-smi") }, errors)
  select_profile(root, "nvidia-fallback")
  core_file = File.join(root, "Soul/runtime/model_runtime/core_selection.json")
  File.write(core_file, JSON.generate("schema_version" => "soul.core_selection.v2", "active_core_id" => "free", "profiles" => {}))
  free_runner = StartupRunner.new("llama-server.service" => "inactive", "soul-model-amd.service" => "inactive")
  free, free_runner, = make_start.call(states: free_runner.states, device_ready: -> { false }, runner: free_runner)
  check("Free Core suppresses Qwen and NVIDIA probing", free.ok && !free.details["started"] &&
        free_runner.commands.none? { |command| command[2] == "start" || command.first.end_with?("nvidia-smi") }, errors)
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
check("startup never enables, disables, or restarts a model unit", !starter_source.match?(/run_systemctl\("(?:enable|disable|restart)"/), errors)
check("human brief explicitly authorizes the persistent bounded oneshot", brief.include?("persistent_oneshot_authorized: yes") && brief.include?("without requiring a system reboot"), errors)

if errors.empty?
  puts "Verification complete."
  puts "Selected-profile startup is candidate-complete for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
