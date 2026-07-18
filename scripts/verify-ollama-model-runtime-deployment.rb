#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/ollama_model_runtime_deployment"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class OllamaDeploymentRunner
  attr_accessor :active_state
  attr_reader :commands
  def initialize = (@active_state = "inactive"; @commands = [])
  def run(*command, **_options)
    @commands << command
    return result(true) if command.first.end_with?("systemd-analyze") || command[2] == "daemon-reload"
    if command[2] == "show"
      property = command.find { |item| item.start_with?("--property=") }.delete_prefix("--property=")
      return result(true, { "LoadState" => "loaded", "ActiveState" => active_state, "UnitFileState" => "static" }.fetch(property))
    end
    result(false)
  end
  private
  def result(ok, stdout = "") = SoulCore::BoundedCommandRunner::Result.new(stdout: "#{stdout}\n", stderr: "", exit_status: ok ? 0 : 1, status: ok ? "ok" : "failed", truncated: false)
end

def executable(path)
  File.write(path, "fixture\n"); File.chmod(0o700, path); path
end

puts "Soul Gemma Ollama inactive-unit deployment verification:"
Dir.mktmpdir("soul-gemma-unit-") do |root|
  home = File.join(root, "home"); FileUtils.mkdir_p(home)
  ollama = executable(File.join(root, "ollama")); systemctl = executable(File.join(root, "systemctl")); analyze = executable(File.join(root, "systemd-analyze"))
  runner = OllamaDeploymentRunner.new
  service = SoulCore::OllamaModelRuntimeDeployment.new(home:, ollama_path: ollama, systemctl_path: systemctl, systemd_analyze_path: analyze, runner:)
  options = { expected_ollama_sha256: Digest::SHA256.file(ollama).hexdigest, source_model: "gemma4:12b-it-q4_K_M", api_model: "soul-local-chat", expected_model_digest: "a" * 64 }
  plan = service.plan(**options)
  check.call("plan is review-blocked and discloses no start enable or selection", plan.ok && plan.lifecycle_state == "blocked_for_human_review" && !plan.details["will_start"] && !plan.details["will_enable"] && !plan.details["will_select"] && runner.commands.empty?)
  wrong = service.install(**options, confirmation: "INSTALL")
  unit_path = File.join(home, ".config/systemd/user/soul-model-gemma.service")
  check.call("wrong confirmation writes and executes nothing", wrong.lifecycle_state == "awaiting_input" && !File.exist?(unit_path) && runner.commands.empty?)
  installed = service.install(**options, confirmation: SoulCore::OllamaModelRuntimeDeployment::CONFIRM_INSTALL)
  unit = File.read(unit_path)
  check.call("exact install creates one inactive static managed unit", installed.ok && installed.details["active_state"] == "inactive" && installed.details["enabled"] == false && unit.start_with?(SoulCore::OllamaModelRuntimeDeployment::MARKER))
  check.call("unit is loopback Vulkan one-model no-cloud and has no install section", unit.include?("OLLAMA_HOST=127.0.0.1:8082") && unit.include?("OLLAMA_VULKAN=1") && unit.include?("OLLAMA_MAX_LOADED_MODELS=1") && unit.include?("OLLAMA_NO_CLOUD=1") && !unit.include?("[Install]"))
  check.call("installer never starts stops enables or selects a runtime", runner.commands.none? { |command| command.any? { |part| %w[start stop restart enable disable --now].include?(part) } })
  runner.active_state = "active"
  blocked = service.uninstall(confirmation: SoulCore::OllamaModelRuntimeDeployment::CONFIRM_UNINSTALL)
  check.call("active unit cannot be removed or implicitly stopped", blocked.lifecycle_state == "blocked_for_human_review" && File.file?(unit_path))
  runner.active_state = "inactive"
  removed = service.uninstall(confirmation: SoulCore::OllamaModelRuntimeDeployment::CONFIRM_UNINSTALL)
  check.call("exact inactive removal deletes only the managed unit", removed.ok && !File.exist?(unit_path))
  bad = service.plan(**options.merge(expected_ollama_sha256: "0" * 64))
  public_bind = service.plan(**options.merge(host: "0.0.0.0"))
  check.call("binary digest and loopback binding fail closed", [bad, public_bind].all? { |result| !result.ok && result.lifecycle_state == "failed" })
end

brief = File.read(File.join(__dir__, "../docs/soul/GEMMA_AMD_CORE_INTEGRATION_BRIEF.md"))
check.call("approved brief authorizes only a gated inactive unit candidate", brief.include?("persistent_unit_candidate_authorized: yes") && brief.include?("automatic_cutover_authorized: no"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Gemma Ollama inactive-unit deployment is candidate-ready."
