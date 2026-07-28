#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class DhcpIdentityRunner
  attr_accessor :resolved_address
  attr_reader :calls

  def initialize(arp_path:, current_address:, resolved_address: nil)
    @arp_path = arp_path
    @current_address = current_address
    @resolved_address = resolved_address
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    if argv.first.end_with?("/ping")
      return result(@resolved_address && argv.last == @resolved_address ? "ok" : "failed")
    end
    if argv.first.end_with?("/nmap")
      write_arp
      return result("ok")
    end

    result("failed")
  end

  private

  def write_arp
    rows = ["IP address       HW type     Flags       HW address            Mask     Device"]
    if @resolved_address
      rows << "#{@resolved_address}    0x1         0x2         00:17:88:aa:bb:cc     *        fixture0"
    end
    File.write(@arp_path, "#{rows.join("\n")}\n")
  end

  def result(status)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: status == "ok" ? "fixture\n" : "",
      stderr: status == "ok" ? "" : "unreachable",
      exit_status: status == "ok" ? 0 : 1,
      status: status,
      truncated: false
    )
  end
end

puts "Maintenance fleet DHCP identity A3 verification:"

Dir.mktmpdir("soul-fleet-dhcp-") do |root|
  state_root = File.join(root, "Soul", "private", "host_maintenance")
  FileUtils.mkdir_p(state_root, mode: 0o700)
  registry_path = File.join(state_root, "discovered_devices.json")
  snapshot_path = File.join(state_root, "fleet_status.json")
  arp_path = File.join(root, "arp")
  nmap_path = File.join(root, "nmap")
  File.write(nmap_path, "#!/bin/sh\nexit 0\n")
  File.chmod(0o700, nmap_path)
  File.write(arp_path, "IP address       HW type     Flags       HW address            Mask     Device\n")

  device_id = "managed_0123456789abcdef"
  old_address = "192.168.50.20"
  record = {
    "id" => device_id,
    "label" => "Tracked fixture",
    "role" => "Discovered local appliance · status only",
    "address" => old_address,
    "connection_mode" => "status_only",
    "address_policy" => "dhcp_tracked",
    "mac_address" => "00:17:88:aa:bb:cc",
    "subnet" => "192.168.50.0/24",
    "address_history" => [],
    "control" => "inventory_only",
    "facts" => {"capability_probe" => "status_only"}
  }
  second_record = record.merge(
    "id" => "managed_fedcba9876543210",
    "label" => "Second tracked fixture",
    "address" => "192.168.50.21",
    "mac_address" => "00:17:88:dd:ee:ff"
  )
  File.write(registry_path, JSON.pretty_generate(
    "schema_version" => "soul.maintenance.fleet_registry.v1",
    "updated_at" => "2026-07-28T12:00:00Z",
    "devices" => [record, second_record]
  ))
  File.chmod(0o600, registry_path)
  File.write(snapshot_path, JSON.pretty_generate(
    "schema_version" => "soul.maintenance.fleet_status.v1",
    "collected_at" => "2026-07-28T12:00:00Z",
    "devices" => [record, second_record].map { |source| {
      "id" => source["id"],
      "label" => source["label"],
      "role" => source["role"],
      "address" => source["address"],
      "control" => "inventory_only",
      "status" => "reachable",
      "reachable" => true,
      "facts" => {}
    } },
    "summary" => {},
    "topology" => {"nodes" => [], "edges" => []},
    "evidence" => []
  ))
  File.chmod(0o600, snapshot_path)

  scheduled = 0
  runner = DhcpIdentityRunner.new(arp_path: arp_path, current_address: old_address)
  service = SoulCore::MaintenanceFleetStatusService.new(
    root: root,
    runner: runner,
    clock: -> { Time.utc(2026, 7, 28, 12, 5, 0) },
    nmap_path: nmap_path,
    arp_path: arp_path,
    recovery_scheduler: -> { scheduled += 1; true }
  )
  first = service.refresh(device_id: device_id)
  first_card = first.dig("data", "devices", 0)
  pending_path = File.join(state_root, "dhcp_recovery.json")
  check.call("a missing reviewed MAC keeps the old address, marks the card unreachable, and schedules exactly one delayed retry",
             first["lifecycle_state"] == "complete" &&
               first_card["address"] == old_address &&
               first_card["reachable"] == false &&
               first_card.dig("facts", "identity_state") == "offline" &&
               first_card.dig("facts", "dhcp_recovery") == "retry_scheduled_for_ten_minutes" &&
               scheduled == 1 &&
               File.file?(pending_path) &&
               (File.stat(pending_path).mode & 0o077).zero?)
  first_commands = runner.calls.map { |call| call["argv"] }
  check.call("recovery uses one bounded subnet scan with no shell or unreviewed mutation",
             first_commands.any? { |argv| argv[1..] == %w[-sn -n --max-retries 1 --host-timeout 2s 192.168.50.0/24] } &&
               first_commands.none? { |argv| %w[sh bash zsh].include?(File.basename(argv.first.to_s)) })

  pending = JSON.parse(File.read(pending_path))
  pending["devices"] << pending.fetch("devices").first.merge(
    "device_id" => second_record["id"],
    "mac_address" => second_record["mac_address"],
    "address" => second_record["address"]
  )
  File.write(pending_path, JSON.pretty_generate(pending))
  File.chmod(0o600, pending_path)
  runner.resolved_address = "192.168.50.73"
  nmap_calls_before_retry = runner.calls.count { |call| call.dig("argv", 0).end_with?("/nmap") }
  retried = service.retry_pending
  retried_card = retried.dig("data", "devices").find { |device| device["id"] == device_id }
  second_card = retried.dig("data", "devices").find { |device| device["id"] == second_record["id"] }
  persisted_registry = JSON.parse(File.read(registry_path)).fetch("devices").find { |device| device["id"] == device_id }
  nmap_calls_after_retry = runner.calls.count { |call| call.dig("argv", 0).end_with?("/nmap") }
  check.call("the single delayed retry retargets status-only inventory only after one exact reviewed-MAC match",
             retried["lifecycle_state"] == "complete" &&
               retried.dig("data", "freshness") == "delayed_dhcp_recovery" &&
               retried_card["address"] == "192.168.50.73" &&
               retried_card["reachable"] == true &&
               retried_card.dig("facts", "identity_state") == "retargeted" &&
               persisted_registry["address"] == "192.168.50.73" &&
               persisted_registry.dig("address_history", 0, "from") == old_address &&
               persisted_registry.dig("address_history", 0, "to") == "192.168.50.73" &&
               !File.exist?(pending_path) &&
               scheduled == 1)
  check.call("multiple tracked identities on one subnet share one bounded recovery scan",
             retried.dig("data", "dhcp_recovery", "retried_device_ids").sort == [device_id, second_record["id"]].sort &&
               nmap_calls_after_retry - nmap_calls_before_retry == 1 &&
               second_card["address"] == second_record["address"] &&
               second_card["reachable"] == false)

  no_pending = service.retry_pending
  check.call("the delayed recovery terminates and never becomes a repeating poll",
             no_pending["lifecycle_state"] == "complete" &&
               no_pending.dig("data", "retried_device_count").zero? &&
               scheduled == 1)

  source = File.read(File.join(__dir__, "../lib/soul_core/maintenance_fleet_status_service.rb"))
  dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
  css = File.read(File.join(__dir__, "../assets/dashboard/dashboard.css"))
  check.call("the fixed delayed command is one hardened user oneshot with a ten-minute bound",
             source.include?('"--on-active=10m"') &&
               source.include?('"--property=Type=oneshot"') &&
             source.include?('"--property=TimeoutStartSec=120"') &&
               source.include?("MAX_DHCP_RECOVERY_SCANS = 4") &&
               source.include?('"automatic_retry" => "complete_no_repeat"'))
  check.call("Dashboard status semantics distinguish healthy, updates, offline, and reboot-required cards",
             dashboard.include?('if (rebootRequired) return "Reboot required"') &&
               dashboard.include?('reachable: "Online"') &&
               dashboard.include?('updates_available: "Updates available"') &&
               dashboard.include?('offline: "Offline"') &&
               css.include?('[data-state="healthy"]') &&
               css.include?('[data-state="updates_available"]') &&
               css.include?('[data-state="reboot_required"]'))
end

if errors.empty?
  puts "Maintenance fleet DHCP identity A3 verification passed."
  exit 0
end

warn "Maintenance fleet DHCP identity A3 verification failed: #{errors.join(', ')}"
exit 1
