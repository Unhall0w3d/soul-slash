#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/model_runtime_profile_deployment"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class DeploymentRunner
  attr_accessor :active_state
  attr_reader :commands

  def initialize
    @active_state = "inactive"
    @commands = []
  end

  def run(*command, **_options)
    @commands << command
    if command.first.end_with?("systemd-analyze")
      return result(true, "", 0)
    end
    if command[2] == "daemon-reload"
      return result(true, "", 0)
    end
    if command[2] == "show"
      property = command.find { |item| item.start_with?("--property=") }.to_s.delete_prefix("--property=")
      value = { "LoadState" => "loaded", "ActiveState" => active_state, "UnitFileState" => "static" }.fetch(property)
      return result(true, "#{value}\n", 0)
    end

    result(false, "", 1)
  end

  private

  def result(ok, stdout, exit_status)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: exit_status, status: ok ? "ok" : "failed", truncated: false)
  end
end

def executable(path)
  File.write(path, "fixture executable\n")
  File.chmod(0o700, path)
  path
end

def options(server, model)
  {
    server_path: server,
    model_path: model,
    expected_server_sha256: Digest::SHA256.file(server).hexdigest,
    expected_model_sha256: Digest::SHA256.file(model).hexdigest,
    model_alias: "soul-primary",
    host: "127.0.0.1",
    port: 8082
  }
end

puts "Soul inactive AMD model unit deployment verification:"

Dir.mktmpdir("soul-amd-unit-") do |root|
  home = File.join(root, "home")
  FileUtils.mkdir_p(home)
  server = executable(File.join(root, "llama-server"))
  model = File.join(root, "model.gguf"); File.write(model, "GGUF fixture\n")
  systemctl = executable(File.join(root, "systemctl"))
  analyze = executable(File.join(root, "systemd-analyze"))
  nvidia = File.join(home, ".config/systemd/user/llama-server.service")
  override = File.join(home, ".config/systemd/user/llama-server.service.d/override.conf")
  FileUtils.mkdir_p(File.dirname(nvidia)); File.write(nvidia, "nvidia base\n")
  FileUtils.mkdir_p(File.dirname(override)); File.write(override, "nvidia override\n")
  nvidia_before = [nvidia, override].to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
  runner = DeploymentRunner.new
  deployment = SoulCore::ModelRuntimeProfileDeployment.new(root: root, home: home, systemctl_path: systemctl, systemd_analyze_path: analyze, runner: runner)

  plan = deployment.plan(**options(server, model))
  check("plan is read-only and requires exact confirmation", plan.ok && plan.lifecycle_state == "blocked_for_human_review" && plan.details["confirmation_phrase"] == "INSTALL_INACTIVE_AMD_MODEL_UNIT" && runner.commands.empty?, errors)
  check("plan discloses exact pinned scope without enable or start", plan.details["will_start"] == false && plan.details["will_enable"] == false && plan.details["commands"] == [["systemctl", "--user", "daemon-reload"]], errors)

  wrong = deployment.install(**options(server, model), confirmation: "INSTALL")
  unit_path = File.join(home, ".config/systemd/user/soul-model-amd.service")
  check("wrong confirmation writes nothing and runs nothing", wrong.lifecycle_state == "awaiting_input" && !File.exist?(unit_path) && runner.commands.empty?, errors)

  installed = deployment.install(**options(server, model), confirmation: "INSTALL_INACTIVE_AMD_MODEL_UNIT")
  unit = File.read(unit_path)
  mutations = runner.commands.select { |command| command[2] && !%w[show].include?(command[2]) && !command.first.end_with?("systemd-analyze") }
  check("verified install writes one managed inactive static unit", installed.ok && installed.details["active_state"] == "inactive" && installed.details["unit_file_state"] == "static" && unit.start_with?(SoulCore::ModelRuntimeProfileDeployment::MARKER), errors)
  check("unit uses fixed loopback Vulkan argv and has no install section", unit.include?(%Q(--host" "127.0.0.1")) && unit.include?(%Q(-dev" "Vulkan0")) && unit.include?("--metrics") && unit.include?("--slots") && !unit.include?("[Install]"), errors)
  check("installer runs daemon-reload but never service lifecycle commands", mutations == [[systemctl, "--user", "daemon-reload"]] && runner.commands.none? { |command| command.any? { |item| %w[start stop restart enable disable --now].include?(item) } }, errors)
  check("NVIDIA unit and drop-in remain byte-identical", nvidia_before.all? { |path, digest| Digest::SHA256.file(path).hexdigest == digest }, errors)

  command_count = runner.commands.length
  repeated = deployment.install(**options(server, model), confirmation: "INSTALL_INACTIVE_AMD_MODEL_UNIT")
  check("matching reinstall is idempotent and remains inactive", repeated.ok && File.read(unit_path) == unit && runner.commands.length > command_count, errors)

  runner.active_state = "active"
  blocked_remove = deployment.uninstall(confirmation: "REMOVE_INACTIVE_AMD_MODEL_UNIT")
  check("uninstall refuses to stop or remove an active unit", blocked_remove.lifecycle_state == "blocked_for_human_review" && File.file?(unit_path) && runner.commands.none? { |command| command.include?("stop") }, errors)
  runner.active_state = "inactive"
  removed = deployment.uninstall(confirmation: "REMOVE_INACTIVE_AMD_MODEL_UNIT")
  check("explicit inactive uninstall removes only the unit and reloads", removed.ok && !File.exist?(unit_path) && File.file?(nvidia) && File.file?(override), errors)

  bad_digest = deployment.plan(**options(server, model).merge(expected_model_sha256: "0" * 64))
  bad_host = deployment.plan(**options(server, model).merge(host: "0.0.0.0"))
  bad_alias = deployment.plan(**options(server, model).merge(model_alias: "bad alias"))
  check("digest, non-loopback host, and invalid alias fail closed", [bad_digest, bad_host, bad_alias].all? { |result| !result.ok && result.lifecycle_state == "failed" }, errors)

  FileUtils.mkdir_p(File.dirname(unit_path)); File.symlink(model, unit_path)
  symlinked = deployment.install(**options(server, model), confirmation: "INSTALL_INACTIVE_AMD_MODEL_UNIT")
  check("symlink unit destination fails closed", !symlinked.ok && File.symlink?(unit_path), errors)
end

source = File.read(File.join(__dir__, "../lib/soul_core/model_runtime_profile_deployment.rb"))
brief = File.read(File.join(__dir__, "../docs/soul/MODEL_RUNTIME_PORTABILITY_2B_AMD_UNIT_BRIEF.md"))
check("deployment source contains no automatic service lifecycle command", !source.match?(/"(?:start|stop|restart|enable|disable|--now)"/), errors)
check("approved brief explicitly authorizes only inactive unit persistence", brief.include?("persistent_unit_authorized: yes") && brief.include?("No AMD start, NVIDIA stop, or model switch"), errors)

if errors.empty?
  puts "Verification complete."
  puts "Inactive AMD unit deployment is candidate-complete for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
