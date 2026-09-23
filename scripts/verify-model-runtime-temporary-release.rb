#!/usr/bin/env ruby
require "tmpdir"
require_relative "../lib/soul_core/model_runtime_control_service"

class TemporaryReleaseFixture < SoulCore::ModelRuntimeControlService
  attr_reader :commands
  attr_accessor :stop_failure, :restore_failure, :gpu_mode, :busy

  def initialize(root)
    @tick = 0
    super(root: root, monotonic_clock: -> { @tick += 50 }, sleeper: ->(_) {})
    @commands = []
    @state = "active"
    @gpu_mode = :normal
  end

  def enabled? = true
  def configuration
    { "profiles" => [{ "id" => "nvidia-fallback", "service" => "fixture.service", "accelerator" => "NVIDIA CUDA" }] }
  end
  def status_unlocked = {}
  def mutation_blocker(*) = busy ? "active work" : nil
  def observe_service_state(*) = @state
  def observe_server(*) = { "health" => "ready" }
  def service_command(action, *)
    @commands << action
    @state = action == "stop" ? "inactive" : "active"
    failed = (action == "stop" && stop_failure) || (action == "start" && restore_failure)
    SoulCore::BoundedCommandRunner::Result.new(status: failed ? "failed" : "ok", exit_status: failed ? 1 : 0, stdout: "", stderr: "", truncated: false)
  end
  def observe_nvidia_allocation(*)
    return nil if gpu_mode == :missing || (gpu_mode == :cpu_after_restart && @commands.include?("start"))
    uuid = gpu_mode == :wrong_after_restart && @commands.include?("start") ? "GPU-bbbb" : "GPU-aaaa"
    { "pid" => 123, "gpu_uuid" => uuid, "memory_mib" => 5000 }
  end
end

def check(label)
  raise "FAIL #{label}" unless yield
  puts "PASS #{label}"
end

Dir.mktmpdir("soul-temporary-release-") do |root|
  runner_class = Class.new do
    attr_accessor :rows, :pid, :truncated
    def run(*command, **)
      SoulCore::BoundedCommandRunner::Result.new(status: "ok", exit_status: 0,
        stdout: command.first == "systemctl" ? (pid || "123\n") : rows,
        stderr: "", truncated: !!truncated)
    end
  end
  runner = runner_class.new
  probe = SoulCore::ModelRuntimeControlService.new(root: root, runner: runner)
  profile = { "service" => "fixture.service" }
  runner.rows = "123, GPU-aaaa, 5000\n"
  check("real allocation parser binds service PID and GPU UUID") { probe.send(:observe_nvidia_allocation, profile) == { "pid" => 123, "gpu_uuid" => "GPU-aaaa", "memory_mib" => 5000 } }
  ["999, GPU-aaaa, 5000\n", "123, GPU-aaaa, 0\n", "123, GPU-aaaa, N/A\n", "123, GPU-aaaa, 5000\n123, GPU-bbbb, 5000\n"].each do |rows|
    runner.rows = rows
    check("foreign empty unknown or ambiguous allocation is rejected") { probe.send(:observe_nvidia_allocation, profile).nil? }
  end
  runner.rows = "123, GPU-aaaa, 5000\n"
  ["999, GPU-aaaa, 200\n", "999, GPU-aaaa, 0\n", "invalid telemetry\n", "999, GPU-bbbb, N/A\n"].each do |other|
    runner.rows = "123, GPU-aaaa, 5000\n#{other}"
    check("same-GPU co-tenant or incomplete ownership evidence is rejected") { probe.send(:observe_nvidia_allocation, profile).nil? }
  end
  runner.rows = "123, GPU-aaaa, 5000\n999, GPU-bbbb, 200\n"
  check("verified unrelated GPU workload is not treated as a co-tenant") { probe.send(:observe_nvidia_allocation, profile)&.fetch("gpu_uuid") == "GPU-aaaa" }
  runner.rows = "123, GPU-aaaa, 5000\n"
  runner.truncated = true
  check("truncated allocation evidence is rejected") { probe.send(:observe_nvidia_allocation, profile).nil? }
  normal = TemporaryReleaseFixture.new(root)
  value, receipt = normal.with_temporary_release(profile_id: "nvidia-fallback") { :work }
  check("work occurs between stop and verified restore") { value == :work && receipt["restored"] && receipt["gpu_placement_verified"] && normal.commands == %w[stop start] }
  [:busy, :missing, :stop, :work, :cancel, :restore, :cpu_after_restart, :wrong_after_restart].each do |mode|
    fixture = TemporaryReleaseFixture.new(root)
    fixture.busy = mode == :busy
    fixture.gpu_mode = mode if [:missing, :cpu_after_restart, :wrong_after_restart].include?(mode)
    fixture.stop_failure = mode == :stop
    fixture.restore_failure = mode == :restore
    called = false
    error = nil
    begin
      fixture.with_temporary_release(profile_id: "nvidia-fallback") do
        called = true
        raise "work failed" if mode == :work
        raise Interrupt if mode == :cancel
      end
    rescue StandardError, Interrupt => caught
      error = caught
    end
    check("#{mode} has a visible terminal error") { !error.nil? }
    if [:busy, :missing].include?(mode)
      check("#{mode} does not mutate or run work") { !called && fixture.commands.empty? }
    else
      check("#{mode} attempts restoration") { fixture.commands == %w[stop start] }
    end
    check("failed stop cannot run specialist") { !called } if mode == :stop
    if [:restore, :cpu_after_restart, :wrong_after_restart].include?(mode)
      check("#{mode} cannot report successful recovery") { error.is_a?(SoulCore::ModelRuntimeControlService::TemporaryReleaseError) && error.receipt["restored"] == false }
    end
  end
end
