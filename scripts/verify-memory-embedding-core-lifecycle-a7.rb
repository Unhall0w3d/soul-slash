#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/memory_embedding_runtime_coordinator"
require_relative "../lib/soul_core/ollama_model_runtime_deployment"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class MemoryRuntimeRunner
  attr_reader :commands
  attr_accessor :state

  def initialize(state: "inactive")
    @state = state
    @commands = []
  end

  def which(name) = "/fixture/#{name}"

  def run(*command, **_options)
    @commands << command
    return result(true) if command.first.end_with?("systemd-analyze") || command[2] == "daemon-reload"
    if command[2] == "show"
      property = command.find { |part| part.start_with?("--property=") }&.delete_prefix("--property=")
      return result(true, property == "LoadState" ? "loaded" : { "ActiveState" => state, "UnitFileState" => "static" }.fetch(property))
    end
    return result(state == "active", state, state == "active" ? 0 : 3) if command[2] == "is-active"
    self.state = "active" if command[2] == "start"
    self.state = "inactive" if command[2] == "stop"
    result(true)
  end

  private

  def result(ok, stdout = "", exit_status = ok ? 0 : 1)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "#{stdout}\n", stderr: "", exit_status:, status: ok ? "ok" : "failed", truncated: false)
  end
end

def executable(path)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "fixture\n")
  File.chmod(0o700, path)
  path
end

puts "Soul memory embedding Core lifecycle A7 verification:"

Dir.mktmpdir("soul-memory-embedding-unit-") do |root|
  home = File.join(root, "home")
  runner = MemoryRuntimeRunner.new
  ollama = executable(File.join(root, "ollama"))
  systemctl = executable(File.join(root, "systemctl"))
  analyze = executable(File.join(root, "systemd-analyze"))
  deployment = SoulCore::OllamaModelRuntimeDeployment.new(
    home:, ollama_path: ollama, systemctl_path: systemctl, systemd_analyze_path: analyze, runner:,
    unit_name: "soul-memory-embedding.service", marker: "# Managed by Soul Memory Embedding Runtime Deployment",
    confirm_install: "INSTALL_MEMORY_EMBEDDING_RUNTIME", confirm_uninstall: "REMOVE_MEMORY_EMBEDDING_RUNTIME",
    display_name: "Memory Embedding", description: "Soul memory embedding NVIDIA Vulkan Ollama runtime",
    keep_alive: "5m", context_length: 1_024
  )
  args = {
    expected_ollama_sha256: Digest::SHA256.file(ollama).hexdigest,
    source_model: "qwen3-embedding:0.6b-q8_0", api_model: "qwen3-embedding:0.6b-q8_0",
    expected_model_digest: "ac6da0dfba84a81fdbfbaf330198c33cd77c4cdfc53e8bc50eb581914a15621d",
    port: 11_434, device: "1"
  }
  plan = deployment.plan(**args)
  check.call("plan remains inactive and unenabled", plan.ok && !plan.details["will_start"] && !plan.details["will_enable"])
  install = deployment.install(**args, confirmation: "INSTALL_MEMORY_EMBEDDING_RUNTIME")
  unit = File.read(File.join(home, ".config/systemd/user/soul-memory-embedding.service"))
  check.call("unit is exact loopback NVIDIA Vulkan", install.ok && unit.include?("OLLAMA_HOST=127.0.0.1:11434") && unit.include?("GGML_VK_VISIBLE_DEVICES=1"))
  check.call("unit fixes the qualified 1024 ceiling", unit.include?("OLLAMA_CONTEXT_LENGTH=1024") && !unit.include?("OLLAMA_CONTEXT_LENGTH=2048"))
  check.call("unit disables cloud and history", unit.include?("OLLAMA_NO_CLOUD=1") && unit.include?("OLLAMA_NOHISTORY=1"))
  check.call("unit cannot enable itself at login", !unit.include?("[Install]") && runner.commands.none? { |command| command.include?("enable") })
end

Dir.mktmpdir("soul-memory-embedding-coordinator-") do |root|
  systemctl = executable(File.join(root, "systemctl"))
  runner = MemoryRuntimeRunner.new
  coordinator = SoulCore::MemoryEmbeddingRuntimeCoordinator.new(runner:, systemctl_path: systemctl)
  %w[daily amd-free music dev].each do |core|
    result = coordinator.reconcile(core_id: core)
    check.call("#{core} Core permits the endpoint", result["ok"] && runner.state == "active")
  end
  stopped = coordinator.reconcile(core_id: "free")
  check.call("Free Core stops the endpoint", stopped["ok"] && runner.state == "inactive")
  rejected = coordinator.reconcile(core_id: "unknown")
  check.call("unknown Core fails closed", !rejected["ok"] && rejected["lifecycle_state"] == "blocked_for_human_review")
  mutations = runner.commands.select { |command| %w[start stop].include?(command[2]) }
  check.call("only the exact reviewed unit is mutated", mutations.all? { |command| command[3] == "soul-memory-embedding.service" })
end

core = File.read(File.join(__dir__, "../lib/soul_core/core_orchestration_service.rb"))
retrieval = File.read(File.join(__dir__, "../lib/soul_core/memory_retrieval_service.rb"))
startup = File.read(File.join(__dir__, "soul-model-runtime-start-selected"))
check.call("Core orchestration exposes and reconciles the memory lane", core.include?("memory_embedding_lane") && core.include?("reconcile_memory_runtime"))
check.call("selected startup reconciles the embedding runtime", startup.include?("MemoryEmbeddingRuntimeCoordinator") && startup.include?("active_core_id"))
check.call("unconfigured installs preserve existing startup", startup.include?("result.ok && embedding_configured"))
check.call("semantic request failure retains lexical fallback", retrieval.include?("embedding unavailable:") && retrieval.include?("lexical_query"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Memory embedding Core lifecycle A7 is candidate-ready for human review."
