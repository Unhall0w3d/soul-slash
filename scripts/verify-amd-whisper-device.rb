#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/amd_whisper_device"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

class AmdWhisperVulkanFixtureRunner
  attr_accessor :result
  attr_reader :calls

  def initialize(result)
    @result = result
    @calls = []
  end

  def run(*command, **options)
    @calls << { command: command.flatten.map(&:to_s), options: options }
    @result
  end
end

class AmdWhisperDeviceFixture < SoulCore::AmdWhisperDevice
  attr_reader :client_calls

  def initialize(total:, used:, client_snapshots:, runner: nil)
    super(runner: runner || AmdWhisperVulkanFixtureRunner.new(nil))
    @device_reading = [total, used]
    @client_snapshots = client_snapshots
    @client_calls = 0
  end

  def read_device
    @device_reading
  end

  def clients(_services)
    snapshot = @client_snapshots.fetch(@client_calls, @client_snapshots.last)
    @client_calls += 1
    snapshot
  end

  def sleep(_seconds)
    nil
  end
end

def command_result(stdout:, status: "ok", truncated: false)
  SoulCore::BoundedCommandRunner::Result.new(
    stdout: stdout, stderr: "", exit_status: status == "ok" ? 0 : 1,
    status: status, truncated: truncated
  )
end

valid_vulkan_summary = <<~TEXT
  GPU0:
  deviceUUID = 00000000-0a00-0000-0000-000000000000
  deviceName = AMD Radeon RX 6900 XT (RADV NAVI21)
TEXT

vulkan_runner = AmdWhisperVulkanFixtureRunner.new(command_result(stdout: valid_vulkan_summary))
vulkan_device = SoulCore::AmdWhisperDevice.new(runner: vulkan_runner)
begin
  vulkan_device.verify_vulkan!
  check.call("Vulkan proof accepts exactly one reviewed RX 6900 XT as Vulkan0", true)
rescue StandardError => error
  check.call("Vulkan proof accepts exactly one reviewed RX 6900 XT as Vulkan0", false)
  warn "unexpected Vulkan proof error: #{error.message}"
end
check.call(
  "Vulkan proof uses the isolated driver and visible-device environment",
  vulkan_runner.calls.one? && vulkan_runner.calls.first[:command] == ["vulkaninfo", "--summary"] &&
    vulkan_runner.calls.first[:options][:env] == SoulCore::AmdWhisperDevice::VULKAN_ENV
)

[
  ["multiple Vulkan GPUs", "GPU0:\ndeviceUUID = 00000000-0a00-0000-0000-000000000000\ndeviceName = AMD Radeon RX 6900 XT (RADV NAVI21)\nGPU1:\ndeviceUUID = other\ndeviceName = other\n", "Vulkan0 identity"],
  ["wrong Vulkan UUID", valid_vulkan_summary.sub("00000000-0a00-0000-0000-000000000000", "11111111-1111-1111-1111-111111111111"), "Vulkan0 identity"],
  ["wrong Vulkan GPU name", valid_vulkan_summary.sub("AMD Radeon RX 6900 XT (RADV NAVI21)", "AMD Radeon RX 6800 XT (RADV NAVI21)"), "Vulkan0 identity"],
  ["truncated Vulkan proof", valid_vulkan_summary, "Vulkan0 identity"]
].each do |name, stdout, expected_message|
  truncated = name == "truncated Vulkan proof"
  runner = AmdWhisperVulkanFixtureRunner.new(command_result(stdout: stdout, truncated: truncated))
  begin
    SoulCore::AmdWhisperDevice.new(runner: runner).verify_vulkan!
    check.call("#{name} is refused", false)
  rescue ArgumentError => error
    check.call("#{name} is refused", error.message.include?(expected_message))
  end
end

minimum_total = 16 * SoulCore::AmdWhisperDevice::GIB
row = lambda do |owner: nil, desktop: false, bytes: nil, compute: 0|
  bytes ||= 128 * 1024**2
  { "owner" => owner, "desktop" => desktop, "bytes" => bytes, "compute" => compute }
end

expect_snapshot_failure = lambda do |name, total:, used:, first:, second:, message:, services: []|
  device = AmdWhisperDeviceFixture.new(total: total, used: used, client_snapshots: [first, second])
  begin
    device.snapshot(services: services)
    check.call(name, false)
  rescue ArgumentError => error
    check.call(name, error.message.include?(message))
  end
end

expect_snapshot_failure.call(
  "VRAM below the reviewed minimum is refused",
  total: 14 * SoulCore::AmdWhisperDevice::GIB, used: 0, first: {}, second: {}, message: "VRAM telemetry is invalid"
)
expect_snapshot_failure.call(
  "VRAM used beyond total is refused",
  total: minimum_total, used: minimum_total + 1, first: {}, second: {}, message: "VRAM telemetry is invalid"
)

large_foreign = row.call(bytes: 512 * 1024**2)
expect_snapshot_failure.call(
  "a large foreign VRAM client blocks admission",
  total: minimum_total, used: large_foreign["bytes"], first: { "foreign" => large_foreign }, second: { "foreign" => large_foreign }, message: "foreign AMD allocation"
)

new_compute = row.call(compute: 1)
expect_snapshot_failure.call(
  "a newly computing foreign client blocks admission",
  total: minimum_total, used: new_compute["bytes"], first: {}, second: { "foreign" => new_compute }, message: "foreign AMD compute"
)

managed_before = row.call(owner: "ollama.service", compute: 10_000_000)
managed_after = row.call(owner: "ollama.service", compute: 10_000_001)
expect_snapshot_failure.call(
  "an actively computing managed client blocks release",
  total: minimum_total, used: managed_after["bytes"], first: { "model" => managed_before }, second: { "model" => managed_after }, message: "managed AMD model is computing", services: ["ollama.service"]
)

stale_compute = row.call(compute: 50_000_000)
stale_device = AmdWhisperDeviceFixture.new(
  total: minimum_total, used: stale_compute["bytes"],
  client_snapshots: [{ "browser" => stale_compute }, { "browser" => stale_compute }]
)
begin
  stale_snapshot = stale_device.snapshot
  check.call("stale cumulative foreign compute is allowed when the counter does not advance", stale_snapshot["allocations"].empty? && stale_snapshot["used"] == stale_compute["bytes"])
rescue StandardError => error
  check.call("stale cumulative foreign compute is allowed when the counter does not advance", false)
  warn "unexpected stale-compute error: #{error.message}"
end

desktop_large = row.call(desktop: true, bytes: 1024**3)
desktop_device = AmdWhisperDeviceFixture.new(
  total: minimum_total, used: desktop_large["bytes"],
  client_snapshots: [{ "compositor" => desktop_large }, { "compositor" => desktop_large }]
)
begin
  desktop_snapshot = desktop_device.snapshot
  check.call("known desktop large allocation is allowed", desktop_snapshot["allocations"].empty? && desktop_snapshot["used"] == desktop_large["bytes"])
rescue StandardError => error
  check.call("known desktop large allocation is allowed", false)
  warn "unexpected desktop-allocation error: #{error.message}"
end

owned = row.call(owner: "ollama.service", bytes: 2 * SoulCore::AmdWhisperDevice::GIB)
desktop_small = row.call(desktop: true, bytes: 256 * 1024**2)
owned_used = owned["bytes"] + desktop_small["bytes"]
owned_device = AmdWhisperDeviceFixture.new(
  total: minimum_total, used: owned_used,
  client_snapshots: [{ "model" => owned, "desktop" => desktop_small }, { "model" => owned, "desktop" => desktop_small }]
)
begin
  owned_snapshot = owned_device.snapshot(services: ["ollama.service"])
  check.call(
    "owned allocations are summed by managed service",
    owned_snapshot["allocations"] == { "ollama.service" => owned["bytes"] } &&
      owned_snapshot["free"] == minimum_total - owned_used
  )
rescue StandardError => error
  check.call("owned allocations are summed by managed service", false)
  warn "unexpected owned-allocation error: #{error.message}"
end

unknown_used = 2 * SoulCore::AmdWhisperDevice::GIB
visible = row.call(bytes: 128 * 1024**2)
expect_snapshot_failure.call(
  "unexplained VRAM fails ownership reconciliation",
  total: minimum_total, used: unknown_used, first: { "visible" => visible }, second: { "visible" => visible }, message: "ownership is incomplete"
)

abort "AMD Whisper device verification failed: #{errors.join(', ')}" unless errors.empty?
puts "AMD Whisper device verification passed."
