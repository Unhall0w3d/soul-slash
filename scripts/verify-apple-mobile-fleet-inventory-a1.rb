#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "../lib/soul_core/apple_mobile_inventory_adapter"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class AppleInventoryFakeRunner
  attr_reader :calls

  def initialize(
    locked: false,
    identifiers: %w[A1111111111111111111 B2222222222222222222],
    disconnected: false
  )
    @locked = locked
    @identifiers = identifiers
    @disconnected = disconnected
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return failed("ERROR: Unable to retrieve device list!", 255) if argv.last == "-l" && @disconnected
    return ok(@identifiers.join("\n") + "\n") if argv.last == "-l"

    identifier = argv.fetch(argv.index("-u") + 1)
    key = argv.fetch(argv.index("-k") + 1) if argv.include?("-k")
    return failed("locked", 255) if @locked

    if key == "InstanceName"
      return ok(identifier.end_with?("1") ? "02:11:22:33:44:55@fixture\n" : "02:aa:bb:cc:dd:ee@fixture\n")
    end
    values = {
      "DeviceName" => "Fixture iPhone",
      "ProductType" => "iPhone16,2",
      "ProductVersion" => "26.6",
      "BuildVersion" => "23G5043d",
      "CPUArchitecture" => "arm64e"
    }
    return ok("#{values.fetch(key)}\n") if values.key?(key)
    return ok(<<~BATTERY) if argv.include?("com.apple.mobile.battery")
      BatteryCurrentCapacity: 27
      BatteryIsCharging: true
      ExternalConnected: true
      FullyCharged: false
      SerialNumber: must-not-escape
    BATTERY

    failed("unexpected fixture command", 127)
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false
    )
  end

  def failed(stderr, exit_status)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: stderr, exit_status: exit_status, status: "failed", truncated: false
    )
  end
end

class AppleInventoryStub
  def initialize(result)
    @result = result
  end

  def discover(reviewed_macs:)
    raise "expected reviewed MAC" unless reviewed_macs.include?("02:11:22:33:44:55")

    @result
  end
end

puts "Apple mobile fleet inventory A1 verification:"

Dir.mktmpdir("soul-apple-mobile-a1-") do |root|
  idevice_id = File.join(root, "idevice_id")
  ideviceinfo = File.join(root, "ideviceinfo")
  [idevice_id, ideviceinfo].each do |path|
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o700, path)
  end

  runner = AppleInventoryFakeRunner.new
  adapter = SoulCore::AppleMobileInventoryAdapter.new(
    runner: runner,
    idevice_id_path: idevice_id,
    ideviceinfo_path: ideviceinfo
  )
  available = adapter.discover(reviewed_macs: ["02:11:22:33:44:55"])
  projection = available.dig("devices", "02:11:22:33:44:55")
  serialized = JSON.generate(available)
  check.call("exact reviewed private Wi-Fi MAC produces the allowlisted trusted-USB projection",
             available["state"] == "available" &&
               available["inspected_usb_device_count"] == 2 &&
               projection["connection"] == "trusted_usb" &&
               projection["device_name"] == "Fixture iPhone" &&
               projection["product_type"] == "iPhone16,2" &&
               projection["product_version"] == "26.6" &&
               projection["battery_percent"] == 27 &&
               projection["battery_is_charging"] == true)
  check.call("adapter output excludes ephemeral identifiers, raw output, and sensitive phone identity",
             !serialized.include?("A1111111111111111111") &&
               !serialized.include?("must-not-escape") &&
               !serialized.match?(/serial|imei|iccid|phone.number|apple.id/i))
  check.call("every command is fixed, bounded, shell-free, and captures no more than 64 KiB",
             runner.calls.all? do |call|
               argv = call.fetch("argv")
               [idevice_id, ideviceinfo].include?(argv.first) &&
                 !argv.any? { |part| %w[sh bash zsh -c].include?(part) } &&
                 call.dig("options", :timeout_seconds) == 3 &&
                 call.dig("options", :max_output_bytes) == 64 * 1024
             end)

  no_match = adapter.discover(reviewed_macs: ["02:99:88:77:66:55"])
  check.call("a nonmatching attached phone cannot enrich another reviewed fleet record",
             no_match["state"] == "no_reviewed_match" && no_match["devices"].empty?)

  locked = SoulCore::AppleMobileInventoryAdapter.new(
    runner: AppleInventoryFakeRunner.new(locked: true),
    idevice_id_path: idevice_id,
    ideviceinfo_path: ideviceinfo
  ).discover(reviewed_macs: ["02:11:22:33:44:55"])
  check.call("locked or untrusted phone terminates with explicit unavailable state",
             locked["state"] == "locked_or_untrusted" && locked["devices"].empty?)

  disconnected = SoulCore::AppleMobileInventoryAdapter.new(
    runner: AppleInventoryFakeRunner.new(disconnected: true),
    idevice_id_path: idevice_id,
    ideviceinfo_path: ideviceinfo
  ).discover(reviewed_macs: ["02:11:22:33:44:55"])
  check.call("libimobiledevice's disconnected exit is normalized to not connected",
             disconnected["state"] == "not_connected" &&
               disconnected["inspected_usb_device_count"] == 0 &&
               disconnected["devices"].empty?)

  many_runner = AppleInventoryFakeRunner.new(
    identifiers: (1..6).map { |index| "F000000000000000000#{index}" }
  )
  SoulCore::AppleMobileInventoryAdapter.new(
    runner: many_runner,
    idevice_id_path: idevice_id,
    ideviceinfo_path: ideviceinfo
  ).discover(reviewed_macs: ["02:99:88:77:66:55"])
  inspected_identifiers = many_runner.calls.filter_map do |call|
    argv = call["argv"]
    argv[argv.index("-u") + 1] if argv.include?("-u")
  end.uniq
  check.call("attached-device inspection stops at the four-device bound",
             inspected_identifiers.length == 4 &&
               inspected_identifiers.none? { |identifier| identifier.end_with?("5") || identifier.end_with?("6") })

  missing = SoulCore::AppleMobileInventoryAdapter.new(
    runner: runner,
    idevice_id_path: File.join(root, "missing-id"),
    ideviceinfo_path: File.join(root, "missing-info")
  ).discover(reviewed_macs: ["02:11:22:33:44:55"])
  check.call("missing optional dependencies fail without running a command",
             missing["state"] == "dependency_unavailable")

  private_root = File.join(root, "private")
  state_root = File.join(private_root, "Soul", "private", "host_maintenance")
  FileUtils.mkdir_p(state_root, mode: 0o700)
  record = {
    "id" => "managed_0123456789abcdef",
    "label" => "Reviewed iPhone",
    "role" => "Discovered local appliance · status only",
    "address" => "192.168.50.22",
    "connection_mode" => "status_only",
    "address_policy" => "dhcp_tracked",
    "mac_address" => "02:11:22:33:44:55",
    "subnet" => "192.168.50.0/24",
    "address_history" => [],
    "ssh_alias" => "",
    "inventory_adapter" => "",
    "control" => "inventory_only",
    "facts" => {"capability_probe" => "status_only"},
    "mutation_authority" => false
  }
  registry_path = File.join(state_root, "discovered_devices.json")
  File.write(registry_path, JSON.pretty_generate(
    "schema_version" => "soul.maintenance.fleet_registry.v1",
    "devices" => [record]
  ))
  File.chmod(0o600, registry_path)
  matched_projection = projection.merge("state" => "available")
  service = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    root: private_root,
    apple_mobile_inventory_adapter: AppleInventoryStub.new(
      "state" => "available",
      "devices" => {"02:11:22:33:44:55" => matched_projection}
    )
  )
  enriched = service.send(:apple_mobile_inventory_for, record)
  persisted_registry = JSON.parse(File.read(registry_path))
  check.call("first exact match privately binds only the reviewed record to the Apple adapter",
             enriched["identity_match"] == "reviewed_private_wifi_mac" &&
               persisted_registry.dig("devices", 0, "inventory_adapter") == "apple_mobile" &&
               persisted_registry.dig("devices", 0, "mutation_authority") == false)

  bound_record = record.merge("inventory_adapter" => "apple_mobile")
  unavailable_service = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    root: private_root,
    apple_mobile_inventory_adapter: AppleInventoryStub.new(
      "state" => "not_connected",
      "devices" => {}
    )
  )
  unavailable = unavailable_service.send(:apple_mobile_inventory_for, bound_record)
  check.call("previously bound device keeps truthful LAN identity when wired inventory is absent",
             unavailable["state"] == "not_connected" &&
               unavailable["connection"] == "unavailable" &&
               unavailable["identity_match"] == "previously_reviewed")
end

if errors.empty?
  puts "Apple mobile fleet inventory A1 verification passed."
  exit 0
end

warn "Apple mobile fleet inventory A1 verification failed: #{errors.join(', ')}"
exit 1
