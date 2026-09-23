#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/external_amd_workload_gate"

def check(name, condition)
  raise "FAIL: #{name}" unless condition
  puts "PASS: #{name}"
end

class FakeDevice
  attr_accessor :free, :error, :fail_on_snapshot
  def initialize
    @free = 8 * 1024**3
    @snapshot_count = 0
  end
  def verify_vulkan! = true
  def snapshot(services: [])
    @snapshot_count += 1
    raise ArgumentError, "allocation changed after lease" if @fail_on_snapshot == @snapshot_count
    raise @error if @error
    raise "unexpected managed services" unless services.empty?
    { "pci" => "0000:0a:00.0", "free" => @free }
  end
end

class FakeLeases
  attr_reader :acquired, :released
  def acquire_exclusive(**args)
    @acquired = args
    { "lease_id" => "lease-1" }
  end
  def release(id) = (@released = id)
end

class FakeRunner
  attr_reader :called
  attr_accessor :result
  def run(*args, **options)
    @called = [args, options]
    @result || SoulCore::BoundedCommandRunner::Result.new(status: "ok", exit_status: 0, truncated: false)
  end
end

device = FakeDevice.new
leases = FakeLeases.new
runner = FakeRunner.new
gate = SoulCore::ExternalAmdWorkloadGate.new(device: device, leases: leases, runner: runner)
check("status is advisory", gate.status(min_free_bytes: 4 * 1024**3)["advisory_only"])
result = gate.run(command: ["/usr/bin/true"], timeout_seconds: 30, min_free_bytes: 4 * 1024**3)
check("foreground result", result["ok"] && runner.called[0] == ["/usr/bin/true"])
check("shared AMD resource group", leases.acquired[:resource_group] == "amd-vulkan-generation")
check("lease released after success", leases.released == "lease-1")

runner.result = SoulCore::BoundedCommandRunner::Result.new(status: "timeout", exit_status: nil, truncated: false)
leases = FakeLeases.new
gate = SoulCore::ExternalAmdWorkloadGate.new(device: device, leases: leases, runner: runner)
check("timed-out child is not a success", !gate.run(command: ["/usr/bin/true"], timeout_seconds: 30, min_free_bytes: 0)["ok"])
check("lease released after timeout", leases.released == "lease-1")

device = FakeDevice.new
device.fail_on_snapshot = 2
runner = FakeRunner.new
leases = FakeLeases.new
gate = SoulCore::ExternalAmdWorkloadGate.new(device: device, leases: leases, runner: runner)
check("post-lease allocation change blocks child", gate.run(command: ["/usr/bin/true"], timeout_seconds: 30, min_free_bytes: 0)["status"] == "blocked" && runner.called.nil?)
check("lease released after post-lease rejection", leases.released == "lease-1")
device = FakeDevice.new

device.free = 2 * 1024**3
runner = FakeRunner.new
leases = FakeLeases.new
gate = SoulCore::ExternalAmdWorkloadGate.new(device: device, leases: leases, runner: runner)
result = gate.run(command: ["/usr/bin/true"], timeout_seconds: 30, min_free_bytes: 4 * 1024**3)
check("insufficient VRAM blocks before child", result["status"] == "blocked" && runner.called.nil?)
check("insufficient VRAM does not touch leases", leases.acquired.nil?)

device.error = ArgumentError.new("foreign AMD allocation is present")
leases = FakeLeases.new
gate = SoulCore::ExternalAmdWorkloadGate.new(device: device, leases: leases, runner: FakeRunner.new)
check("foreign work blocks admission", gate.run(command: ["/usr/bin/true"], timeout_seconds: 30, min_free_bytes: 0)["status"] == "blocked")
check("foreign work does not touch leases", leases.acquired.nil?)

device.error = nil
leases = FakeLeases.new
gate = SoulCore::ExternalAmdWorkloadGate.new(device: device, leases: leases, runner: FakeRunner.new)
check("invalid timeout rejected", gate.run(command: ["/usr/bin/true"], timeout_seconds: 3_601, min_free_bytes: 0)["status"] == "blocked")
check("invalid request never leases", leases.acquired.nil?)
