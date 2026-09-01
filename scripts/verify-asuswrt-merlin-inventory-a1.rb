#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/asuswrt_merlin_inventory_adapter"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_discovery_service"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class MerlinFakeRunner
  attr_reader :calls

  def initialize(missing_marker: false, missing_core: false, include_optional: true)
    @calls = []
    @missing_marker = missing_marker
    @missing_core = missing_core
    @include_optional = include_optional
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return ok(fixture) if argv[-2].to_s.match?(SoulCore::AsuswrtMerlinInventoryAdapter::SSH_ALIAS_PATTERN) && argv[-1] == SoulCore::AsuswrtMerlinInventoryAdapter::REMOTE_COMMAND

    failed
  end

  private

  def fixture
    output = <<~OUTPUT
      __SOUL_MERLIN__productid
      RT-AX-TEST
      __SOUL_MERLIN__firmver
      3.0.0.4
      __SOUL_MERLIN__buildno
      388
      __SOUL_MERLIN__extendno
      TEST
      __SOUL_MERLIN__bl_version
      1.0
      __SOUL_MERLIN__hostname
      merlin-router-fixture
      __SOUL_MERLIN__uname
      4.1.52
      __SOUL_MERLIN__uptime
      12345.67 54321.00
      __SOUL_MERLIN__loadavg
      0.12 0.08 0.04 1/90 123
      __SOUL_MERLIN__meminfo
      MemTotal:         512000 kB
      MemFree:          256000 kB
      Buffers:           10000 kB
      Cached:            50000 kB
      __SOUL_MERLIN__jffs_df
      Filesystem 1K-blocks Used Available Use% Mounted on
      /dev/mtdblock3 64000 2048 61952 4% /jffs
      __SOUL_MERLIN__temperatures
      CPU temperature: 73°C
      2.4GHz temperature: 53 C
      5GHz temperature: 66 C
      __SOUL_MERLIN__qos_enable
      1
      __SOUL_MERLIN__qos_type
      1
      __SOUL_MERLIN__qos_obw
      50000
      __SOUL_MERLIN__qos_ibw
      500000
      __SOUL_MERLIN__ctf_disable
      0
      __SOUL_MERLIN__jffs2_scripts
      1
      __SOUL_MERLIN__lsmod
      ctf 12345 0
      __SOUL_MERLIN__jffs_script_count
      #{@include_optional ? "1\n" : "0\n"}
      __SOUL_MERLIN__jffs_config_count
      #{@include_optional ? "1\n" : "0\n"}
      __SOUL_MERLIN__entware_present
      1
      __SOUL_MERLIN__entware_version
      opkg version fixture
      __SOUL_MERLIN__entware_installed_count
      39
      __SOUL_MERLIN__entware_upgradable_count
      0
      __SOUL_MERLIN__swap_summary
      1 1048572 0
      __SOUL_MERLIN__usb_storage_summary
      1 15480816 1177788 13516648
      __SOUL_MERLIN__firmware_state_flag
      0
      __SOUL_MERLIN__firmware_state_update
      1
      __SOUL_MERLIN__firmware_state_error
      0
      __SOUL_MERLIN__firmware_state_info
      3004_388_TEST
      __SOUL_MERLIN__tool_jq
      1
      __SOUL_MERLIN__tool_dig
      1
      __SOUL_MERLIN__tool_tcpdump
      1
      __SOUL_MERLIN__tool_htop
      1
      __SOUL_MERLIN__tool_iperf3
      1
      __SOUL_MERLIN__tool_bash
      1
      __SOUL_MERLIN__tool_tmux
      1
      __SOUL_MERLIN__complete
      1
    OUTPUT
    output = output.sub("RT-AX-TEST\n", "\n") if @missing_core
    output = output.sub("__SOUL_MERLIN__complete\n1\n", "") if @missing_marker
    output
  end

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failed
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: "fixture failure", exit_status: 255, status: "failed", truncated: false)
  end
end

puts "Asuswrt-Merlin inventory A1 verification:"

Dir.mktmpdir("soul-merlin-inventory-") do |root|
  ssh_path = File.join(root, "ssh")
  File.write(ssh_path, "#!/bin/sh\nexit 0\n")
  File.chmod(0o700, ssh_path)
  ssh_config = File.join(root, "ssh_config")
  File.write(ssh_config, "Host router-fixture\n  HostName router.example.invalid\n  User router-admin\n")
  File.chmod(0o600, ssh_config)

  runner = MerlinFakeRunner.new
  adapter = SoulCore::AsuswrtMerlinInventoryAdapter.new(runner: runner, ssh_path: ssh_path, ssh_config: ssh_config)
  inventory = adapter.collect(ssh_alias: "router-fixture")
  call = runner.calls.fetch(0)

  check.call("reviewed registry alias is collected through bounded SSH", inventory["available"] && call["argv"].include?("router-fixture") && call["argv"].last == SoulCore::AsuswrtMerlinInventoryAdapter::REMOTE_COMMAND && call.dig("options", :timeout_seconds) == 8 && call.dig("options", :max_output_bytes) == 32 * 1024)
  check.call("inventory facts are sanitized and useful", inventory["model"] == "RT-AX-TEST" && inventory["firmware_version"] == "3.0.0.4 · 388 · TEST" && inventory["kernel"] == "4.1.52" && inventory["hostname"] == "merlin-router-fixture" && inventory["uptime_seconds"] == 12345)
  check.call("memory, JFFS, temperatures, QoS, and acceleration are parsed", inventory.dig("memory", "total_kb") == 512000 && inventory.dig("jffs", "available_kb") == 61952 && inventory.dig("jffs", "custom_scripts") == 1 && inventory.dig("temperatures", 0, "celsius") == 73.0 && inventory.dig("qos", "configured_upload_kbps") == 50000 && inventory.dig("qos", "configured_download_kbps") == 500000 && inventory.dig("ctf", "active") == true && inventory["custom_scripts_configured"] == true)
  check.call("Entware, swap, storage, firmware signals, toolbox, and diagnostics are bounded", inventory.dig("entware", "installed_count") == 39 && inventory.dig("entware", "upgradable_count") == 0 && inventory.dig("swap", "total_kb") == 1048572 && inventory.dig("usb_storage", "filesystem_count") == 1 && inventory.dig("firmware_check", "update_available").nil? && inventory.dig("firmware_check", "interpretation") == "raw_vendor_state_only" && inventory.dig("toolbox", "tcpdump") == true && inventory.dig("diagnostics", "state") == "healthy")
  check.call("no secrets, filenames, package names, paths, or unbounded NVRAM data are requested", !SoulCore::AsuswrtMerlinInventoryAdapter::REMOTE_SCRIPT.match?(/nvram\s+(show|dump)|wan_ip|wl.*(key|pass)|ssh.*key|opkg\s+update/i) && SoulCore::AsuswrtMerlinInventoryAdapter::REMOTE_SCRIPT.match?(/find .*\| \/usr\/bin\/wc -l/) && call["argv"].none? { |part| part.match?(/nvram\s+(show|dump)/i) })
  before = runner.calls.length
  rejected = adapter.collect(ssh_alias: "-oProxyCommand=fixture")
  check.call("unsafe aliases are rejected without a probe", !rejected["available"] && rejected["reason"] == "invalid_ssh_alias" && runner.calls.length == before)
  missing_marker = SoulCore::AsuswrtMerlinInventoryAdapter.new(
    runner: MerlinFakeRunner.new(missing_marker: true), ssh_path: ssh_path, ssh_config: ssh_config
  ).collect(ssh_alias: "router-fixture")
  missing_core = SoulCore::AsuswrtMerlinInventoryAdapter.new(
    runner: MerlinFakeRunner.new(missing_core: true), ssh_path: ssh_path, ssh_config: ssh_config
  ).collect(ssh_alias: "router-fixture")
  check.call("incomplete remote output fails closed", !missing_marker["available"] && missing_marker["reason"] == "incomplete_inventory" && !missing_core["available"] && missing_core["reason"] == "incomplete_inventory")
  optional_empty = SoulCore::AsuswrtMerlinInventoryAdapter.new(
    runner: MerlinFakeRunner.new(include_optional: false), ssh_path: ssh_path, ssh_config: ssh_config
  ).collect(ssh_alias: "router-fixture")
  check.call("missing optional JFFS directories do not fail collection", optional_empty["available"] && optional_empty.dig("jffs", "custom_scripts") == 0 && optional_empty.dig("jffs", "custom_configs") == 0 && optional_empty["custom_scripts_configured"] == true)

  discovery = SoulCore::MaintenanceFleetDiscoveryService.allocate
  check.call("registry normalization preserves only reviewed adapter tokens", discovery.send(:normalized_inventory_adapter, "asuswrt_merlin") == "asuswrt_merlin" && discovery.send(:normalized_inventory_adapter, "untrusted") == "")

  status_service = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    ssh_config: ssh_config,
    process_env: {},
    asuswrt_merlin_inventory_adapter: adapter
  )
  record = {
    "id" => "managed_0123456789abcdef", "label" => "ASUSWRT-Merlin fixture", "role" => "LAN gateway · inventory only",
    "address" => "192.0.2.1", "connection_mode" => "ssh", "address_policy" => "fixed",
    "ssh_alias" => "router-fixture", "facts" => {}, "inventory_adapter" => "asuswrt_merlin"
  }
  projected = status_service.send(:collect_enrolled_device, record, schedule_recovery: false)
  check.call("SSH inventory projection remains inventory-only", projected["control"] == "inventory_only" && projected.dig("facts", "mutation_supported") == false && projected.dig("facts", "status_adapter") == "asuswrt_merlin_read_only" && projected.dig("reboot", "required") == false && projected.dig("updates", "freshness") == "cached_entware_metadata" && projected.dig("updates", "total") == 0)
end

if errors.empty?
  puts "PASS"
else
  warn "FAIL: #{errors.join(', ')}"
  exit 1
end
