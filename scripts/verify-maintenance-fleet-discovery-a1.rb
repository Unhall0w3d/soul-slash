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
  identity_file = File.join(root, "fixture_identity")
  File.write(identity_file, "fixture private key material is never read\n")
  File.chmod(0o600, identity_file)
  mac_prefix_path = File.join(root, "nmap-mac-prefixes")
  File.write(mac_prefix_path, "001788 Philips Lighting BV\n")
  arp_path = File.join(root, "arp")
  File.write(arp_path, <<~ARP)
    IP address       HW type     Flags       HW address            Mask     Device
    192.168.50.20    0x1         0x2         00:17:88:aa:bb:cc     *        fixture0
  ARP

  runner = DiscoveryFakeRunner.new
  service = SoulCore::MaintenanceFleetDiscoveryService.new(
    root: root,
    process_env: {
      "SOUL_FLEET_WORKSTATION_ADDRESS" => "192.168.50.2",
      "SOUL_FLEET_WORKSTATION_LABEL" => "Atelier"
    },
    runner: runner,
    clock: -> { Time.utc(2026, 7, 28, 12, 0, 0) },
    ssh_config: ssh_config,
    nmap_path: File.join(bin, "nmap"),
    ssh_path: File.join(bin, "ssh"),
    ping_path: File.join(bin, "ping"),
    arp_path: arp_path,
    mac_prefix_path: mac_prefix_path
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
               scan["mutation"] == "last_subnet" &&
               scan_data["subnet"] == "192.168.50.0/24" &&
               scan_data["persisted"] == false &&
               scan_data["detected_count"] == 2 &&
               scan_data["candidate_count"] == 1 &&
               scan_data["represented_count"] == 1 &&
               !File.exist?(File.join(root, "Soul", "private", "host_maintenance", "discovery.json")))
  preferences_path = File.join(root, "Soul", "private", "host_maintenance", "fleet_discovery_preferences.json")
  preferences = JSON.parse(File.read(preferences_path))
  check.call("successful scan remembers only its canonical subnet in owner-private state",
             File.file?(preferences_path) &&
               (File.stat(preferences_path).mode & 0o077).zero? &&
               preferences["last_subnet"] == "192.168.50.0/24" &&
               (preferences.keys - %w[schema_version updated_at last_subnet]).empty? &&
               service.status.dig("data", "last_subnet") == "192.168.50.0/24")
  nmap_call = runner.calls.find { |call| call.dig("argv", 0).end_with?("/nmap") }
  check.call("discovery uses one fixed argv with timeout and no shell",
             nmap_call["argv"][1..] == %w[-sn -n --max-retries 1 --host-timeout 2s 192.168.50.0/24] &&
               nmap_call.dig("options", :timeout_seconds) == 30 &&
               !nmap_call["argv"].any? { |part| %w[sh bash zsh -c].include?(part) })
  known = scan_data["represented"].find { |candidate| candidate["address"] == "192.168.50.2" }
  check.call("scan candidates remain untrusted while already represented addresses are excluded",
             known["known_device"] == "Atelier" &&
               scan_data["candidates"].none? { |candidate| candidate["address"] == "192.168.50.2" } &&
               scan_data["candidates"].all? { |candidate| candidate["trusted"] == false && candidate["mutation_authority"] == false })
  candidate_hint = scan_data.dig("candidates", 0, "identity_hints")
  check.call("candidate identity hints come from one bounded local ARP read and OUI data",
             candidate_hint["mac_address"] == "00:17:88:aa:bb:cc" &&
               candidate_hint["vendor"] == "Philips Lighting BV" &&
               candidate_hint["interface"] == "fixture0" &&
               candidate_hint["neighbor_state"] == ["ARP cached"] &&
               runner.calls.none? { |call| call.dig("argv", 0).end_with?("/ip") })

  rejected = [
    service.discover(subnet: "8.8.8.0/24"),
    service.discover(subnet: "127.0.0.1/32"),
    service.discover(subnet: "192.168.50.0/23"),
    service.discover(subnet: "192.168.50.0/24;id")
  ]
  check.call("public, loopback, oversized, and shell-shaped scopes fail before a scan",
             rejected.all? { |result| result["lifecycle_state"] == "failed" } &&
               runner.calls.count { |call| call.dig("argv", 0).end_with?("/nmap") } == 1)

  ignore_preview = service.ignore_preview(
    address: "192.168.50.20",
    label: "Fixture lamp",
    subnet: "192.168.50.0/24",
    mac_address: "00:17:88:aa:bb:cc",
    vendor: "Philips Lighting BV"
  )
  ignored = service.ignore(
    address: "192.168.50.20",
    label: "Fixture lamp",
    subnet: "192.168.50.0/24",
    mac_address: "00:17:88:aa:bb:cc",
    vendor: "Philips Lighting BV",
    confirmation: ignore_preview.dig("data", "confirmation_phrase"),
    expected_digest: ignore_preview.dig("data", "expected_digest")
  )
  ignored_path = File.join(root, "Soul", "private", "host_maintenance", "ignored_devices.json")
  ignored_scan = service.discover(subnet: "192.168.50.0/24").fetch("data")
  check.call("reviewed ignore stores one private MAC-first identity and excludes it from candidates",
             ignored["lifecycle_state"] == "complete" &&
               ignored["mutation"] == "ignore_one_candidate" &&
               File.file?(ignored_path) &&
               (File.stat(ignored_path).mode & 0o077).zero? &&
               ignored_scan["candidate_count"].zero? &&
               ignored_scan["ignored_count"] == 1 &&
               service.ignored.dig("data", "device_count") == 1)
  restore_preview = service.restore_preview(identity_key: "mac:00:17:88:aa:bb:cc")
  restored = service.restore(
    identity_key: "mac:00:17:88:aa:bb:cc",
    confirmation: restore_preview.dig("data", "confirmation_phrase"),
    expected_digest: restore_preview.dig("data", "expected_digest")
  )
  restored_scan = service.discover(subnet: "192.168.50.0/24").fetch("data")
  check.call("reviewed restore removes only the ignored record and returns the address as a candidate",
             restored["lifecycle_state"] == "complete" &&
               restored["mutation"] == "restore_one_candidate" &&
               service.ignored.dig("data", "device_count").zero? &&
               restored_scan["candidate_count"] == 1 &&
               restored_scan["candidates"].first["address"] == "192.168.50.20")

  dhcp_preview = service.enrollment_preview(
    address: "192.168.50.20",
    label: "Fixture lamp",
    mode: "status_only",
    address_policy: "dhcp_tracked",
    subnet: "192.168.50.0/24",
    mac_address: "00:17:88:aa:bb:cc"
  )
  rejected_dhcp_ssh = service.enrollment_preview(
    address: "192.168.50.20",
    label: "Fixture Linux",
    mode: "ssh",
    ssh_alias: "fixture-linux",
    address_policy: "dhcp_tracked",
    subnet: "192.168.50.0/24",
    mac_address: "00:17:88:aa:bb:cc"
  )
  check.call("DHCP tracking is a reviewed MAC-bound option for status-only inventory and never broadens SSH authority",
             dhcp_preview["lifecycle_state"] == "complete" &&
               dhcp_preview.dig("data", "device", "address_policy") == "dhcp_tracked" &&
               dhcp_preview.dig("data", "device", "mac_address") == "00:17:88:aa:bb:cc" &&
               dhcp_preview.dig("data", "device", "subnet") == "192.168.50.0/24" &&
               rejected_dhcp_ssh["lifecycle_state"] == "failed")

  alias_preview = service.ssh_alias_preview(
    address: "192.168.50.21",
    ssh_alias: "guided-linux",
    ssh_user: "fixture",
    identity_file: identity_file
  )
  alias_data = alias_preview.fetch("data")
  check.call("missing SSH alias setup previews one fixed non-interactive stanza without reading key contents",
             alias_preview["lifecycle_state"] == "complete" &&
               alias_preview["mutation"] == "none" &&
               alias_data.dig("ssh_alias", "hostname") == "192.168.50.21" &&
               alias_data.dig("ssh_alias", "stanza").include?("Host guided-linux\n") &&
               alias_data.dig("ssh_alias", "stanza").include?("BatchMode yes") &&
               alias_data["credentials_stored"] == false)
  outside_identity_root = Dir.mktmpdir("soul-outside-identity-")
  outside_identity = File.join(outside_identity_root, "key")
  File.write(outside_identity, "outside fixture\n")
  File.chmod(0o600, outside_identity)
  rejected_identity = service.ssh_alias_preview(
    address: "192.168.50.21",
    ssh_alias: "outside-key-linux",
    ssh_user: "fixture",
    identity_file: outside_identity
  )
  FileUtils.remove_entry(outside_identity_root)
  check.call("SSH alias setup rejects identity paths outside the owner SSH directory",
             rejected_identity["lifecycle_state"] == "failed")
  stale_alias = service.add_ssh_alias(
    address: "192.168.50.21",
    ssh_alias: "guided-linux",
    ssh_user: "changed-user",
    identity_file: identity_file,
    confirmation: alias_data["confirmation_phrase"],
    expected_digest: alias_data["expected_digest"]
  )
  check.call("changed SSH alias input is rejected by the preview digest",
             stale_alias["lifecycle_state"] == "blocked_for_human_review" &&
               !File.read(ssh_config).include?("Host guided-linux"))
  added_alias = service.add_ssh_alias(
    address: "192.168.50.21",
    ssh_alias: "guided-linux",
    ssh_user: "fixture",
    identity_file: identity_file,
    confirmation: alias_data["confirmation_phrase"],
    expected_digest: alias_data["expected_digest"]
  )
  config_after_alias = File.read(ssh_config)
  check.call("approved SSH alias setup atomically appends only the reviewed literal Host block",
             added_alias["lifecycle_state"] == "complete" &&
               added_alias["mutation"] == "append_one_literal_host" &&
               config_after_alias.scan(/^Host guided-linux$/).length == 1 &&
               config_after_alias.include?("    HostName 192.168.50.21\n") &&
               config_after_alias.include?("    IdentityFile #{identity_file}\n") &&
               (File.stat(ssh_config).mode & 0o077).zero?)
  duplicate_alias = service.ssh_alias_preview(
    address: "192.168.50.21",
    ssh_alias: "guided-linux",
    ssh_user: "fixture",
    identity_file: identity_file
  )
  check.call("an existing literal alias cannot be overwritten or duplicated",
             duplicate_alias["lifecycle_state"] == "failed" &&
               File.read(ssh_config).scan(/^Host guided-linux$/).length == 1)

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
  check.call("exact enrollment writes one owner-private registry record only",
             enrolled["lifecycle_state"] == "complete" &&
               enrolled["mutation"] == "one_private_record" &&
               File.file?(registry_path) &&
               (File.stat(registry_path).mode & 0o077).zero? &&
               service.registry.dig("data", "device_count") == 1)
  rescanned = service.discover(subnet: "192.168.50.0/24").fetch("data")
  check.call("an enrolled address is excluded from subsequent candidate lists",
             rescanned["candidate_count"].zero? &&
               rescanned["represented_count"] == 2 &&
               rescanned["represented"].any? do |record|
                 record["address"] == "192.168.50.20" && record["known_device"] == "Fixture Linux"
               end)

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
  facade_alias = facade.call(request("maintenance.discovery.ssh_alias.preview", {
    "address" => "192.168.50.22",
    "ssh_alias" => "facade-linux",
    "ssh_user" => "fixture",
    "identity_file" => identity_file
  }))
  check.call("application contract exposes the separately gated SSH alias prerequisite",
             facade_alias["lifecycle_state"] == "complete" &&
               facade_alias.dig("data", "ssh_alias", "alias") == "facade-linux")

  dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
  html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
  check.call("Dashboard requires an explicit scan and suppresses actions for all inventory-only devices",
             html.include?('id="scan-maintenance-subnet"') &&
               html.include?("Candidate results are not persisted") &&
               dashboard.include?('const inventoryOnly = device.control !== "maintenance"') &&
               dashboard.include?("already represented and excluded") &&
               dashboard.include?("Enrollment complete.") &&
               dashboard.include?("no local identity hints available") &&
               dashboard.include?("dependency.last_subnet") &&
               dashboard.include?('address_policy: byId("maintenance-enrollment-policy").value') &&
               dashboard.include?('"maintenance.discovery.ssh_alias.preview"') &&
               dashboard.include?('"maintenance.discovery.ssh_alias.execute"') &&
               html.include?('id="maintenance-ssh-alias-setup"') &&
               dashboard.include?('card.classList.add("maintenance-device-card--status-only")') &&
               dashboard.include?('"Network reachability"') &&
               dashboard.include?("discovered capabilities grant no mutation authority") &&
               !dashboard.include?("setInterval(scanMaintenanceSubnet"))
  check.call("Dashboard preserves unacted-on scan candidates after enrollment, ignore, restore, and removal",
             dashboard.include?("function removeMaintenanceDiscoveryCandidate(candidate)") &&
               dashboard.include?('.filter((entry) => String(entry.address || "") !== address)') &&
               dashboard.include?("const remainingCount = mode === \"ignore\"") &&
               dashboard.include?("const remainingCount = removeMaintenanceDiscoveryCandidate(actedCandidate)") &&
               dashboard.include?("current candidate${remainingCount === 1 ? \"\" : \"s\"} preserved") &&
               dashboard.include?("renderMaintenanceDiscoveryCandidates(data.candidates || [])") &&
               !dashboard.include?("renderMaintenanceDiscoveryCandidates([])"))
end

if errors.empty?
  puts "Portable fleet discovery A1 verification passed."
  exit 0
end

warn "Portable fleet discovery A1 verification failed: #{errors.join(', ')}"
exit 1
