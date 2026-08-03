#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/managed_switch_snmp_inventory_adapter"
require_relative "../lib/soul_core/maintenance_fleet_status_service"
require "tmpdir"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class SnmpFakeRunner
  attr_reader :calls, :config_modes

  def initialize(failure: false)
    @failure = failure
    @calls = []
    @config_modes = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    config = File.join(options.fetch(:env).fetch("SNMPCONFPATH"), "snmp.conf")
    @config_modes << (File.stat(config).mode & 0o777)
    return result("", "authentication failed", 1, "failed") if @failure

    stdout = if argv.include?(SoulCore::ManagedSwitchSnmpInventoryAdapter::SYSTEM_OIDS.first)
               <<~OUTPUT
                 NETGEAR GS724Tv4 ProSAFE 24-Port Gigabit Smart Switch, Software Version 6.3.1.47
                 .1.3.6.1.4.1.4526.100.4.28
                 (987654) 2:17:26.54
                 Lattice
               OUTPUT
             elsif argv.last == SoulCore::ManagedSwitchSnmpInventoryAdapter::INTERFACE_TABLE_OID
               <<~OUTPUT
                 .1.3.6.1.2.1.2.2.1.1.1 = INTEGER: 1
                 .1.3.6.1.2.1.2.2.1.2.1 = STRING: g1
                 .1.3.6.1.2.1.2.2.1.3.1 = INTEGER: 6
                 .1.3.6.1.2.1.2.2.1.5.1 = Gauge32: 1000000000
                 .1.3.6.1.2.1.2.2.1.7.1 = INTEGER: 1
                 .1.3.6.1.2.1.2.2.1.8.1 = INTEGER: 1
                 .1.3.6.1.2.1.2.2.1.10.1 = Counter32: 1250
                 .1.3.6.1.2.1.2.2.1.14.1 = Counter32: 0
                 .1.3.6.1.2.1.2.2.1.16.1 = Counter32: 2500
                 .1.3.6.1.2.1.2.2.1.20.1 = Counter32: 2
                 .1.3.6.1.2.1.2.2.1.1.2 = INTEGER: 2
                 .1.3.6.1.2.1.2.2.1.2.2 = STRING: l2vlan1
                 .1.3.6.1.2.1.2.2.1.3.2 = INTEGER: 53
               OUTPUT
             elsif argv.last == SoulCore::ManagedSwitchSnmpInventoryAdapter::IF_HIGH_SPEED_OID
               ".1.3.6.1.2.1.31.1.1.1.15.1 = Gauge32: 1000\n"
             else
               <<~OUTPUT
                 .1.3.6.1.2.1.47.1.1.1.1.5.100 = INTEGER: 3
                 .1.3.6.1.2.1.47.1.1.1.1.7.100 = STRING: "Lattice"
                 .1.3.6.1.2.1.47.1.1.1.1.8.100 = STRING: "B1.0.0.4"
                 .1.3.6.1.2.1.47.1.1.1.1.9.100 = STRING: ""
                 .1.3.6.1.2.1.47.1.1.1.1.10.100 = STRING: "6.3.1.47"
                 .1.3.6.1.2.1.47.1.1.1.1.13.100 = STRING: "GS724Tv4"
               OUTPUT
             end
    result(stdout, "", 0, "ok")
  end

  private

  def result(stdout, stderr, exit_status, status)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: stderr, exit_status: exit_status, status: status, truncated: false
    )
  end
end

class ManagedSwitchInventoryStub
  def collect(address:, community:)
    raise "unexpected target" unless %w[192.168.124.10 192.168.124.11].include?(address)
    raise "missing private credential" unless community == "stub-community-1234"

    loom = address.end_with?(".11")
    {
      "available" => true, "state" => "available", "system_name" => loom ? "loom" : "Lattice",
      "vendor" => loom ? "Cisco" : "Netgear",
      "object_id" => loom ? ".1.3.6.1.4.1.9.6.1.83.10.1" : ".1.3.6.1.4.1.4526.100.4.28",
      "model" => loom ? "SG300-10" : "GS724Tv4", "product_id" => loom ? "SRW2008-K9" : "GS724Tv4",
      "firmware_version" => loom ? "1.4.11.5" : "6.3.1.47", "boot_version" => loom ? "1.3.5.06" : "",
      "hardware_version" => loom ? "V02" : "B1.0.0.4", "uptime_seconds" => 1234,
      "port_count" => 1, "active_port_count" => 1, "error_port_count" => 0,
      "ports" => [{"index" => 1, "name" => "g1", "oper_status" => "up", "speed_mbps" => 1000}]
    }
  end
end

class FleetFailureRunner
  def run(*_command, **_options)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: "unavailable", exit_status: 1, status: "failed", truncated: false
    )
  end
end

puts "Managed-switch SNMP inventory A1 verification:"
community = 'test-"quoted"-community-1234'
runner = SnmpFakeRunner.new
adapter = SoulCore::ManagedSwitchSnmpInventoryAdapter.new(
  runner: runner,
  snmpget_path: "/usr/bin/true",
  snmpbulkwalk_path: "/usr/bin/true"
)
inventory = adapter.collect(address: "192.168.124.10", community: community)
check.call("standard SNMPv2-MIB and IF-MIB evidence is normalized",
           inventory["available"] && inventory["system_name"] == "Lattice" &&
             inventory["model"] == "GS724Tv4" && inventory["firmware_version"] == "6.3.1.47" &&
             inventory["active_port_count"] == 1 && inventory["error_port_count"] == 1)
check.call("only physical Ethernet interfaces enter the bounded port projection",
           inventory["ports"].length == 1 && inventory.dig("ports", 0, "speed_mbps") == 1000 &&
             inventory.dig("ports", 0, "out_errors") == 2)
check.call("credential never enters argv or command environment",
           runner.calls.length == 4 && runner.calls.none? do |call|
             call["argv"].include?(community) || call.fetch("options").fetch(:env).values.include?(community)
           end)
check.call("ephemeral Net-SNMP configuration is owner-private and removed",
           runner.config_modes == [0o600, 0o600, 0o600, 0o600] &&
             runner.calls.all? { |call| !File.exist?(call.fetch("options").fetch(:env).fetch("SNMPCONFPATH")) })
check.call("invalid target and absent credential fail before any command",
           adapter.collect(address: "8.8.8.8", community: community)["state"] == "invalid_target" &&
             adapter.collect(address: "192.168.124.10", community: "short")["state"] == "credential_not_configured" &&
             runner.calls.length == 4)

switch_env = {
    "SOUL_FLEET_LATTICE_ENABLED" => "true",
    "SOUL_FLEET_LATTICE_ADDRESS" => "192.168.124.10",
    "SOUL_FLEET_LATTICE_LABEL" => "Lattice",
    "SOUL_FLEET_LATTICE_WEB_URL" => "http://lattice.herz.soul",
    "SOUL_FLEET_LATTICE_EXPECTED_FIRMWARE" => "6.3.1.47",
    "SOUL_FLEET_LATTICE_SNMP_COMMUNITY" => "stub-community-1234",
    "SOUL_FLEET_LOOM_ENABLED" => "true",
    "SOUL_FLEET_LOOM_ADDRESS" => "192.168.124.11",
    "SOUL_FLEET_LOOM_LABEL" => "Loom",
    "SOUL_FLEET_LOOM_WEB_URL" => "http://loom.herz.soul",
    "SOUL_FLEET_LOOM_EXPECTED_FIRMWARE" => "1.4.11.5",
    "SOUL_FLEET_LOOM_SNMP_COMMUNITY" => "stub-community-1234"
}
fleet = SoulCore::MaintenanceFleetStatusService.new(
  runner: SnmpFakeRunner.new(failure: true),
  managed_switch_snmp_inventory_adapter: ManagedSwitchInventoryStub.new,
  process_env: switch_env
)
lattice = fleet.send(:collect_managed_switch, "lattice")
loom = fleet.send(:collect_managed_switch, "loom")
check.call("fleet card is inventory-only and reports reviewed firmware truth",
           lattice["id"] == "lattice" && lattice["control"] == "inventory_only" &&
             lattice["status"] == "healthy" && lattice.dig("facts", "firmware_status") == "current" &&
             lattice.dig("facts", "mutation_supported") == false && lattice.dig("facts", "snmp_set_authority") == false)
check.call("private management link is credential-free and fixed",
           lattice.dig("facts", "management_url") == "http://lattice.herz.soul")
check.call("Cisco switch uses the same inventory-only contract with boot evidence",
           loom["id"] == "loom" && loom["control"] == "inventory_only" &&
             loom["version"] == "1.4.11.5" && loom.dig("facts", "boot_version") == "1.3.5.06" &&
             loom.dig("facts", "status_adapter") == "managed_switch_snmp_read_only")
Dir.mktmpdir("soul-managed-switch-fleet-") do |root|
  persisted_fleet = SoulCore::MaintenanceFleetStatusService.new(
    root: root,
    runner: FleetFailureRunner.new,
    managed_switch_snmp_inventory_adapter: ManagedSwitchInventoryStub.new,
    process_env: switch_env
  )
  collected = persisted_fleet.collect
  switch_ids = Array(collected.dig("data", "devices")).map { |device| device["id"] }
  refreshed = persisted_fleet.refresh(device_id: "loom")
  check.call("both switches persist and Loom supports bounded one-card refresh",
             collected["ok"] && %w[lattice loom].all? { |id| switch_ids.include?(id) } &&
               refreshed["ok"] && refreshed.dig("data", "refreshed_device_id") == "loom")
end

source = File.read(File.join(__dir__, "../lib/soul_core/managed_switch_snmp_inventory_adapter.rb"))
check.call("adapter contains no SNMP SET executable or operation", !source.match?(/snmpset/i))
dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
fleet_source = File.read(File.join(__dir__, "../lib/soul_core/maintenance_fleet_status_service.rb"))
installer = File.read(File.join(__dir__, "soul-configure-managed-switch-snmp"))
check.call("dashboard exposes bounded port evidence and a credential-free management link",
           dashboard.include?("Physical interface inventory") &&
             dashboard.include?("bounded polling · traps not ingested") &&
             dashboard.include?("Open switch management"))
check.call("topology names the actual read-only SNMP relationship",
           fleet_source.include?('when "snmp_v2c_read_only" then "read-only SNMP inventory"'))
check.call("stdin-only installer never prints or interpolates the community",
           installer.include?("community = STDIN.read") &&
             !installer.match?(/puts\s+.*community/i) && !installer.match?(/warn\s+.*community/i))

abort("Managed-switch SNMP inventory verification failed: #{errors.join(', ')}") unless errors.empty?
puts "Managed-switch SNMP inventory verification passed."
