#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_discovery_service"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class DiscoveryFakeRunner
  attr_reader :calls

  def initialize(address: "192.168.50.20")
    @address = address
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    if argv.first.end_with?("/nmap")
      return ok("Nmap scan report for 192.168.50.2\nHost is up.\nNmap scan report for #{@address}\nHost is up.\nNmap done\n")
    end
    return ok("64 bytes\n") if argv.first.end_with?("/ping")
    return ok("host #{@address}\nhostname #{@address}\nuser fixture\n") if argv[0, 2] == [argv.first, "-G"]

    target_index = argv.index("fixture-linux")
    return failed(127) unless target_index

    remote = argv[(target_index + 1)..]
    return ok("fixture-host\n") if remote == ["/usr/bin/hostname"]
    return ok("6.12.0-fixture\n") if remote == ["/usr/bin/uname", "-r"]
    return ok("PRETTY_NAME=\"Portable Linux Fixture\"\nID=fixture\n") if remote == ["/usr/bin/cat", "/etc/os-release"]
    return ok("") if remote == ["/usr/bin/test", "-x", "/usr/bin/test"]
    if remote.length == 3 && remote[0, 2] == ["/usr/bin/test", "-x"]
      supported = SoulCore::MaintenanceFleetDiscoveryService::PACKAGE_PATHS.values.flatten
      return supported.include?(remote.last) ? ok("") : failed(1)
    end

    failed(127)
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failed(code)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: "fixture failure", exit_status: code, status: "failed", truncated: false)
  end
end

def request(operation, parameters = {})
  {
    "schema_version" => "soul.application.v1",
    "request_id" => "request.discovery.#{operation.gsub(/[^a-z]+/, ".")}.0001",
    "operation" => operation,
    "parameters" => parameters,
    "context" => {"interface" => "dashboard_test"}
  }
end

puts "Portable fleet discovery A1 verification:"

Dir.mktmpdir("soul-fleet-discovery-") do |root|
  bin = File.join(root, "bin")
  FileUtils.mkdir_p(bin)
  %w[nmap ssh ping].each do |name|
    path = File.join(bin, name)
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o700, path)
  end
  ssh_config = File.join(root, "ssh_config")
  File.write(ssh_config, "Host fixture-linux\n  HostName 192.168.50.20\n  User fixture\n")
  File.chmod(0o600, ssh_config)

  runner = DiscoveryFakeRunner.new
  service = SoulCore::MaintenanceFleetDiscoveryService.new(
    root: root,
    process_env: {"SOUL_FLEET_MAVEN_ADDRESS" => "192.168.50.2"},
    runner: runner,
    clock: -> { Time.utc(2026, 7, 28, 12, 0, 0) },
    ssh_config: ssh_config,
    nmap_path: File.join(bin, "nmap"),
    ssh_path: File.join(bin, "ssh"),
    ping_path: File.join(bin, "ping")
  )

  status = service.status
  check.call("prerequisite status is local, inert, and exposes no mutation authority",
             status.dig("data", "available") == true &&
               status.dig("data", "background_scanning") == false &&
               status.dig("data", "mutation_authority") == false)

  scan = service.discover(subnet: "192.168.50.7/24")
  scan_data = scan.fetch("data")
  check.call("one explicit private scan is canonical, bounded, and non-persisted",
             scan["lifecycle_state"] == "complete" &&
               scan_data["subnet"] == "192.168.50.0/24" &&
               scan_data["persisted"] == false &&
               scan_data["candidate_count"] == 2 &&
               !File.exist?(File.join(root, "Soul", "private", "host_maintenance", "discovery.json")))
  nmap_call = runner.calls.find { |call| call.dig("argv", 0).end_with?("/nmap") }
  check.call("discovery uses one fixed argv with timeout and no shell",
             nmap_call["argv"][1..] == %w[-sn -n --max-retries 1 --host-timeout 2s 192.168.50.0/24] &&
               nmap_call.dig("options", :timeout_seconds) == 30 &&
               !nmap_call["argv"].any? { |part| %w[sh bash zsh -c].include?(part) })
  known = scan_data["candidates"].find { |candidate| candidate["address"] == "192.168.50.2" }
  check.call("scan candidates remain untrusted and mark already represented addresses",
             known["state"] == "already_configured" &&
               known["known_device"] == "Maven" &&
               scan_data["candidates"].all? { |candidate| candidate["trusted"] == false && candidate["mutation_authority"] == false })

  rejected = [
    service.discover(subnet: "8.8.8.0/24"),
    service.discover(subnet: "127.0.0.1/32"),
    service.discover(subnet: "192.168.50.0/23"),
    service.discover(subnet: "192.168.50.0/24;id")
  ]
  check.call("public, loopback, oversized, and shell-shaped scopes fail before a scan",
             rejected.all? { |result| result["lifecycle_state"] == "failed" } &&
               runner.calls.count { |call| call.dig("argv", 0).end_with?("/nmap") } == 1)

  preview = service.enrollment_preview(
    address: "192.168.50.20", label: "Fixture Linux", mode: "ssh", ssh_alias: "fixture-linux"
  )
  preview_data = preview.fetch("data")
  managers = preview_data.dig("device", "facts", "package_managers")
  check.call("SSH enrollment verifies alias target and fingerprints capabilities independent of distro",
             preview["lifecycle_state"] == "complete" &&
               preview["mutation"] == "none" &&
               preview_data.dig("device", "control") == "inventory_only" &&
               preview_data.dig("device", "facts", "ssh_target_verified") == true &&
               managers == %w[pacman yay paru apt apt-get dnf zypper apk flatpak snap nix] &&
               preview_data.dig("device", "mutation_authority") == false)
  ssh_calls = runner.calls.select { |call| call.dig("argv", 0).end_with?("/ssh") }
  check.call("SSH fingerprint uses fixed BatchMode commands and bounded probes",
             ssh_calls.any? { |call| call["argv"][1] == "-G" } &&
               ssh_calls.reject { |call| call["argv"][1] == "-G" }.all? do |call|
                 call["argv"].include?("BatchMode=yes") &&
                   call["argv"].include?("ConnectionAttempts=1") &&
                   call.dig("options", :timeout_seconds) == 5 &&
                   !call["argv"].any? { |part| %w[sh bash zsh -c].include?(part) }
               end)

  stale = service.enroll(
    address: "192.168.50.20", label: "Changed Label", mode: "ssh", ssh_alias: "fixture-linux",
    confirmation: preview_data["confirmation_phrase"], expected_digest: preview_data["expected_digest"]
  )
  check.call("a stale enrollment digest is blocked without a write",
             stale["lifecycle_state"] == "blocked_for_human_review" &&
               service.registry.dig("data", "device_count").zero?)

  enrolled = service.enroll(
    address: "192.168.50.20", label: "Fixture Linux", mode: "ssh", ssh_alias: "fixture-linux",
    confirmation: preview_data["confirmation_phrase"], expected_digest: preview_data["expected_digest"]
  )
  registry_path = File.join(root, "Soul", "private", "host_maintenance", "discovered_devices.json")
  check.call("exact enrollment writes one owner-private ignored registry record only",
             enrolled["lifecycle_state"] == "complete" &&
               enrolled["mutation"] == "one_private_record" &&
               File.file?(registry_path) &&
               (File.stat(registry_path).mode & 0o077).zero? &&
               service.registry.dig("data", "device_count") == 1)

  os_release = File.join(root, "os-release")
  File.write(os_release, "PRETTY_NAME=\"Controller Fixture\"\n")
  fleet = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner, root: root, ssh_config: ssh_config, os_release_path: os_release,
    hostname_reader: -> { "controller" }, process_env: {}
  ).collect
  enrolled_card = fleet.dig("data", "devices").find { |device| device["id"] == enrolled.dig("data", "device", "id") }
  check.call("enrolled inventory appears in fleet status without maintenance controls or fake update counts",
             enrolled_card["control"] == "inventory_only" &&
               enrolled_card["reachable"] == true &&
               enrolled_card.dig("updates", "freshness") == "not_queried" &&
               enrolled_card.dig("updates", "total").zero? &&
               enrolled_card.dig("facts", "mutation_supported") == false)

  removal = service.removal_preview(device_id: enrolled.dig("data", "device", "id"))
  removed = service.remove(
    device_id: enrolled.dig("data", "device", "id"),
    confirmation: removal.dig("data", "confirmation_phrase"),
    expected_digest: removal.dig("data", "expected_digest")
  )
  check.call("reviewed removal deletes only one private registry record",
             removed["lifecycle_state"] == "complete" &&
               removed["mutation"] == "remove_one_private_record" &&
               service.registry.dig("data", "device_count").zero?)

  facade = SoulCore::ApplicationFacade.new(root: root, maintenance_fleet_discovery_service: service)
  envelope = facade.call(request("maintenance.discovery.scan", {"subnet" => "192.168.50.20/32"}))
  check.call("application contract exposes bounded discovery to Dashboard and Chat orchestration",
             envelope["lifecycle_state"] == "complete" &&
               envelope.dig("data", "subnet") == "192.168.50.20/32" &&
               envelope.dig("data", "mutation_authority") == false)

  dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
  html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
  check.call("Dashboard requires an explicit scan and suppresses actions for all inventory-only devices",
             html.include?('id="scan-maintenance-subnet"') &&
               html.include?("Candidate results are not persisted") &&
               dashboard.include?('const inventoryOnly = device.control !== "maintenance"') &&
               dashboard.include?("discovered capabilities grant no mutation authority") &&
               !dashboard.include?("setInterval(scanMaintenanceSubnet"))
end

if errors.empty?
  puts "Portable fleet discovery A1 verification passed."
  exit 0
end

warn "Portable fleet discovery A1 verification failed: #{errors.join(', ')}"
exit 1
