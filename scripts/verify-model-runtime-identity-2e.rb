#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/model_runtime_identity_migration"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def command_result(ok = true)
  SoulCore::BoundedCommandRunner::Result.new(
    stdout: "", stderr: "", exit_status: ok ? 0 : 1,
    status: ok ? "ok" : "failed", truncated: false
  )
end

class IdentityControl
  attr_accessor :busy

  def initialize
    @busy = false
  end

  def status
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "active_profile_count" => 1,
        "active_profile_id" => "amd-quality",
        "active_work_count" => busy ? 1 : 0,
        "idle_certain" => !busy,
        "service" => "soul-model-amd.service",
        "provider_endpoint" => "http://127.0.0.1:8082/v1",
        "server" => { "health" => "ready" },
        "profiles" => [
          { "id" => "nvidia-fallback", "service" => "llama-server.service", "service_state" => "inactive" },
          { "id" => "amd-quality", "service" => "soul-model-amd.service", "service_state" => "active" }
        ]
      }
    }
  end
end

class IdentityRunner
  attr_reader :commands

  def initialize
    @commands = []
  end

  def run(*command, **_options)
    @commands << command
    command_result
  end
end

def fixture(root)
  home = File.join(root, "home")
  amd = File.join(home, ".config/systemd/user/soul-model-amd.service")
  nvidia = File.join(home, ".config/systemd/user/llama-server.service.d/override.conf")
  FileUtils.mkdir_p(File.dirname(amd))
  FileUtils.mkdir_p(File.dirname(nvidia))
  File.write(File.join(root, ".env"), "PRIVATE_TOKEN=not-for-output\nSOUL_LOCAL_OPENAI_MODEL=soul-qwen3-8b-q4\n")
  File.write(amd, "ExecStart=/bin/llama-server \"-m\" /models/ministral.gguf \"-a\" \"soul-qwen3-8b-q4\" --port 8082\n")
  File.write(nvidia, "ExecStart=/bin/llama-server --model /models/qwen.gguf --alias soul-qwen3-8b-q4 --port 8082\n")
  [home, [File.join(root, ".env"), amd, nvidia]]
end

puts "Soul model-runtime identity 2E verification:"

Dir.mktmpdir("soul-identity-2e-") do |root|
  home, paths = fixture(root)
  originals = paths.to_h { |path| [path, File.binread(path)] }
  control = IdentityControl.new
  runner = IdentityRunner.new
  migration = SoulCore::ModelRuntimeIdentityMigration.new(
    root: root, home: home, runtime_control: control, runner: runner,
    probe: ->(_endpoint, alias_name) { alias_name == "soul-local-chat" },
    sleeper: ->(_seconds) {}
  )

  plan = migration.plan
  plan_text = plan.to_s
  check("plan is review-gated, read-only, and contains no private contents",
        plan["lifecycle_state"] == "blocked_for_human_review" &&
          plan.dig("data", "confirmation_phrase") == "MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT" &&
          paths.all? { |path| File.binread(path) == originals.fetch(path) } &&
          runner.commands.empty? && !plan_text.include?("not-for-output") && !plan_text.include?("/models/"),
        errors)

  digest = plan.dig("data", "expected_digest")
  wrong = migration.execute(confirmation: "MIGRATE", expected_digest: digest)
  check("wrong confirmation mutates nothing",
        wrong["lifecycle_state"] == "blocked_for_human_review" &&
          paths.all? { |path| File.binread(path) == originals.fetch(path) } && runner.commands.empty?,
        errors)

  stale = migration.execute(
    confirmation: "MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT",
    expected_digest: "0" * 64
  )
  check("stale digest mutates nothing",
        stale["lifecycle_state"] == "blocked_for_human_review" &&
          paths.all? { |path| File.binread(path) == originals.fetch(path) } && runner.commands.empty?,
        errors)

  control.busy = true
  busy = migration.plan
  check("active work blocks preview before mutation",
        busy["reason"].include?("complete or be canceled") && runner.commands.empty?, errors)
  control.busy = false

  completed = migration.execute(
    confirmation: "MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT",
    expected_digest: digest
  )
  command_actions = runner.commands.map { |command| [command[2], command[3]] }
  check("coordinated migration updates all and only reviewed aliases",
        completed["ok"] &&
          paths.all? { |path| File.read(path).include?("soul-local-chat") && !File.read(path).include?("soul-qwen3-8b-q4") } &&
          File.read(paths[0]).include?("PRIVATE_TOKEN=not-for-output"),
        errors)
  check("migration restarts active AMD and dashboard without reboot or fallback",
        command_actions == [
          ["stop", "soul-model-amd.service"],
          ["daemon-reload", nil],
          ["start", "soul-model-amd.service"],
          ["restart", "soul-dashboard.service"]
        ] && runner.commands.flatten.none? { |part| %w[reboot enable disable llama-server.service].include?(part) },
        errors)
end

Dir.mktmpdir("soul-identity-rollback-") do |root|
  home, paths = fixture(root)
  originals = paths.to_h { |path| [path, File.binread(path)] }
  runner = IdentityRunner.new
  migration = SoulCore::ModelRuntimeIdentityMigration.new(
    root: root, home: home, runtime_control: IdentityControl.new, runner: runner,
    probe: ->(_endpoint, _alias_name) { false }, sleeper: ->(_seconds) {}
  )
  plan = migration.plan
  result = migration.execute(
    confirmation: "MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT",
    expected_digest: plan.dig("data", "expected_digest")
  )
  actions = runner.commands.map { |command| [command[2], command[3]] }
  check("readiness failure terminates and restores all files",
        result["lifecycle_state"] == "failed" && result.dig("data", "rollback_complete") == true &&
          paths.all? { |path| File.binread(path) == originals.fetch(path) },
        errors)
  check("rollback restores the same active profile with bounded commands",
        actions.last(3) == [
          ["stop", "soul-model-amd.service"],
          ["daemon-reload", nil],
          ["start", "soul-model-amd.service"]
        ] && runner.commands.length == 6,
        errors)
end

Dir.mktmpdir("soul-identity-path-") do |root|
  home, paths = fixture(root)
  target = paths.fetch(2)
  File.unlink(target)
  File.symlink(paths.fetch(1), target)
  runner = IdentityRunner.new
  result = SoulCore::ModelRuntimeIdentityMigration.new(
    root: root, home: home, runtime_control: IdentityControl.new, runner: runner
  ).plan
  check("symlinked migration target fails closed before commands",
        result["lifecycle_state"] == "blocked_for_human_review" &&
          result["reason"].include?("regular non-symlink") && runner.commands.empty?,
        errors)
end

registry = File.read(File.join(__dir__, "../lib/soul_core/model_runtime_profile_registry.rb"))
dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
brief = File.read(File.join(__dir__, "../docs/soul/MODEL_RUNTIME_PORTABILITY_2E_IDENTITY_BRIEF.md"))
check("profile schema separates model and accelerator identity",
      registry.include?("model_name") && registry.include?("accelerator") &&
        dashboard.include?("API alias") && dashboard.include?("At login"),
      errors)
check("approved brief bounds restart and forbids automatic switching",
      brief.include?("model_service_restart_authorized: idle-gated active profile only") &&
        brief.include?("automatic_switch_or_fallback_authorized: no"),
      errors)

if errors.empty?
  puts "Verification complete."
  puts "Model-runtime identity 2E is candidate-complete for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
