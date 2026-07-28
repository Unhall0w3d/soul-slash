#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class FleetFakeRunner
  attr_reader :calls

  def initialize(pihole_offline: false, phone_offline: false)
    @pihole_offline = pihole_offline
    @phone_offline = phone_offline
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return ok("7.1.4-1-cachyos-eevdf-lto\n") if argv == ["/usr/bin/uname", "-r"]
    return ok("linux-cachyos 7.1.4 -> 7.1.5\nruby 4.0 -> 4.1\n") if argv == ["/usr/bin/pacman", "-Qu"]
    return ok("fixture-aur 1 -> 2\n") if argv == ["/usr/bin/yay", "-Qua"]
    return ok("org.example.App\t2\tstable\n") if argv.include?("--user") && argv.include?("remote-ls")
    return ok("") if argv.include?("--system") && argv.include?("remote-ls")
    return ok("linux-cachyos 7.1.5-1\n") if argv == ["/usr/bin/pacman", "-Q", "linux-cachyos"]
    return ok("Hyprland 0.55.4 built from branch v0.55.4\n") if argv == ["/usr/bin/hyprland", "-v"]
    if argv[0, 5] == ["/usr/bin/ping", "-c", "1", "-W", "2"]
      return failed("unreachable", 1) if @phone_offline

      return ok("64 bytes from #{argv.fetch(5)}: time=0.4 ms\n")
    end

    target_index = argv.index { |value| %w[proxmox-maintenance pihole-maintenance].include?(value) }
    return failed("unexpected command", 127) unless target_index

    target = argv[target_index]
    remote = argv[(target_index + 1)..]
    return failed("network unavailable", 255) if @pihole_offline && target == "pihole-maintenance"
    return proxmox(remote) if target == "proxmox-maintenance"
    return pihole(remote) if target == "pihole-maintenance"

    failed("unexpected target", 127)
  end

  private

  def proxmox(remote)
    return ok("forge\n") if remote == ["/usr/bin/hostname"]
    return ok("pve-manager/9.2.5/fixture (running kernel: 7.0.2-6-pve)\n") if remote == ["/usr/bin/pveversion"]
    return ok("7.0.2-6-pve\n") if remote == ["/usr/bin/uname", "-r"]
    if remote == ["/usr/sbin/proxmox-boot-tool", "kernel", "list"]
      return ok("Automatically selected kernels:\n7.0.14-6-pve\n7.0.2-6-pve\n")
    end
    return ok("Inst pve-manager [9.2.5] (9.2.6 fixture)\n1 upgraded, 0 newly installed\n") if remote.include?("dist-upgrade")
    return failed("", 1) if remote == ["/usr/bin/test", "-e", "/var/run/reboot-required"]
    if remote == ["/usr/bin/pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"]
      return ok(JSON.generate([{
        "vmid" => 100, "type" => "lxc", "node" => "forge", "name" => "pihole", "status" => "running", "tags" => "adblock;community-script",
        "mem" => 64 * 1024 * 1024, "maxmem" => 512 * 1024 * 1024, "uptime" => 7200
      }]))
    end
    failed("unexpected Proxmox command", 127)
  end

  def pihole(remote)
    return ok("pihole\n") if remote == ["/usr/bin/hostname"]
    if remote == ["/usr/local/bin/pihole", "-v"]
      return ok("Core version is v6.4.3 (Latest: v6.4.3)\nWeb version is v6.6 (Latest: v6.6)\nFTL version is v6.7 (Latest: v6.7)\n")
    end
    return ok("[✓] FTL is listening on port 53\n[✓] Pi-hole blocking is enabled\n") if remote == ["/usr/local/bin/pihole", "status"]
    return ok("active\n") if remote[0, 2] == ["/usr/bin/systemctl", "is-active"]
    return ok("127.0.0.1\n") if remote.first == "/usr/bin/dig"
    return ok("Inst openssh-server [1] (2 fixture)\nInst unbound [1] (2 fixture)\n") if remote.include?("dist-upgrade")
    return failed("", 1) if remote == ["/usr/bin/test", "-e", "/var/run/reboot-required"]
    failed("unexpected Pi-hole command", 127)
  end

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

class FleetFacadeStub
  def collect
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "mutation" => "none",
      "data" => {
        "schema_version" => "soul.maintenance.fleet_status.v1",
        "devices" => []
      }
    }
  end
end

puts "Maintenance fleet status B1 verification:"

Dir.mktmpdir("soul-fleet-status-") do |root|
  os_release = File.join(root, "os-release")
  File.write(os_release, "PRETTY_NAME=\"CachyOS fixture\"\n")
  runner = FleetFakeRunner.new
  service = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    clock: -> { Time.utc(2026, 7, 27, 21, 0, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "maven" }
  )
  result = service.collect
  data = result.dig("data")
  devices = data.fetch("devices").to_h { |device| [device.fetch("id"), device] }

  check.call("collector returns one terminal read-only lifecycle with no mutation",
             result["ok"] &&
               result["lifecycle_state"] == "complete" &&
               result["mutation"] == "none" &&
               data["read_only"] == true &&
               data.dig("verification", "background_polling") == false)
  check.call("workstation update and kernel evidence is normalized",
             devices.dig("maven", "updates", "total") == 4 &&
               devices.dig("maven", "updates", "freshness") == "cached_pacman_metadata" &&
               devices.dig("maven", "kernel", "running") == "7.1.4-1-cachyos-eevdf-lto" &&
               devices.dig("maven", "kernel", "available") == "7.1.5-1" &&
               devices.dig("maven", "kernel", "update_required") == true)
  check.call("Proxmox discovers Forge and exposes cached package, kernel, and LXC 100 evidence",
             devices.dig("forge", "label") == "Forge" &&
               devices.dig("forge", "updates", "native") == 1 &&
               devices.dig("forge", "kernel", "available") == "7.0.14-6-pve" &&
               devices.dig("forge", "kernel", "update_required") == true &&
               devices.dig("forge", "facts", "pihole_container", "id") == 100 &&
               devices.dig("forge", "facts", "pihole_container", "status") == "running")
  check.call("Pi-hole exposes versions, DNS health, services, and package evidence",
             devices.dig("pihole", "version").include?("Core v6.4.3") &&
               devices.dig("pihole", "updates", "native") == 2 &&
               devices.dig("pihole", "facts", "blocking_enabled") == true &&
               devices.dig("pihole", "services").all? { |service_record| service_record["state"] == "active" })
  check.call("summary and Visio-style topology derive from the same device evidence",
             data.dig("summary", "reachable_count") == 3 &&
               data.dig("summary", "updates_available") == 7 &&
               data.dig("summary", "kernel_attention_count") == 2 &&
               data.dig("topology", "edges").any? { |edge| edge["kind"] == "backup_planned" } &&
               data.dig("topology", "nodes").map { |node| node["id"] }.include?("pihole"))
  check.call("only fixed aliases and bounded no-password SSH options are used",
             runner.calls.select { |call| call.dig("argv", 0) == "/usr/bin/ssh" }.all? do |call|
               argv = call["argv"]
               (argv.include?("proxmox-maintenance") || argv.include?("pihole-maintenance")) &&
                 argv.include?("BatchMode=yes") &&
                 argv.include?("ConnectTimeout=5") &&
                 !argv.any? { |part| %w[sh bash zsh -c].include?(part) } &&
                 call.dig("options", :timeout_seconds).to_i.between?(1, 30)
             end)
  check.call("collector stores bounded command outcomes but no command output or credentials",
             data.fetch("evidence").all? { |record| (record.keys - %w[adapter status exit_status truncated]).empty? } &&
               data.fetch("evidence").select { |record| record["adapter"].end_with?("reboot_required") }.all? { |record| record["status"] == "ok" } &&
               !JSON.generate(data.fetch("evidence")).include?("IdentityFile"))

  phone_env = {
    "SOUL_FLEET_MAVEN_ADDRESS" => "maven.example.test",
    "SOUL_FLEET_FORGE_ADDRESS" => "forge.example.test",
    "SOUL_FLEET_PIHOLE_ADDRESS" => "pihole.example.test",
    "SOUL_FLEET_CISCO_PHONE_ENABLED" => "true",
    "SOUL_FLEET_CISCO_PHONE_ADDRESS" => "phone.example.test",
    "SOUL_FLEET_CISCO_PHONE_LABEL" => "Desk Phone"
  }
  phone_runner = FleetFakeRunner.new
  with_phone = SoulCore::MaintenanceFleetStatusService.new(
    runner: phone_runner,
    clock: -> { Time.utc(2026, 7, 27, 21, 3, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "maven" },
    process_env: phone_env
  ).collect
  phone_data = with_phone.fetch("data")
  phone = phone_data.fetch("devices").find { |device| device["id"] == "cisco-8851" }
  check.call("optional Cisco phone is one bounded status-only reachability probe",
             phone["label"] == "Desk Phone" &&
               phone["address"] == "phone.example.test" &&
               phone["reachable"] == true &&
               phone["control"] == "status_only" &&
               phone.dig("facts", "mutation_supported") == false &&
               phone.dig("facts", "registration_status") == "not assessed" &&
               phone_runner.calls.count { |call| call.dig("argv", 0) == "/usr/bin/ping" } == 1 &&
               phone_runner.calls.find { |call| call.dig("argv", 0) == "/usr/bin/ping" }.dig("options", :timeout_seconds) == 5)
  check.call("phone topology distinguishes local reachability from unasserted Webex state",
             phone_data.dig("summary", "device_count") == 4 &&
               phone_data.dig("topology", "nodes").any? { |node| node["id"] == "webex-calling" && node["status"] == "external" } &&
               phone_data.dig("topology", "edges").any? do |edge|
                 edge["from"] == "cisco-8851" &&
                   edge["to"] == "webex-calling" &&
                   edge["label"].include?("status not asserted")
               end)
  check.call("phone evidence excludes device identity, credentials, and raw probe output",
             !JSON.generate(phone).match?(/serial|mac.address|directory.number|call.history|credential/i) &&
               phone_data.fetch("evidence").all? { |record| (record.keys - %w[adapter status exit_status truncated]).empty? })

  unavailable_phone = SoulCore::MaintenanceFleetStatusService.new(
    runner: FleetFakeRunner.new(phone_offline: true),
    clock: -> { Time.utc(2026, 7, 27, 21, 4, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "maven" },
    process_env: phone_env
  ).collect.dig("data", "devices").find { |device| device["id"] == "cisco-8851" }
  check.call("unreachable Cisco phone remains visible and status-only",
             unavailable_phone["status"] == "offline" &&
               unavailable_phone["control"] == "status_only" &&
               unavailable_phone.dig("facts", "reachability") == "unreachable")

  source = File.read(File.join(__dir__, "../lib/soul_core/maintenance_fleet_status_service.rb"))
  dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
  check.call("public service defaults contain no operator-specific RFC1918 addresses",
             !source.match?(/\b192\.168\.\d{1,3}\.\d{1,3}\b/))
  check.call("dashboard suppresses mutation controls for status-only and inventory-only devices",
             dashboard.include?('const inventoryOnly = device.control !== "maintenance"') &&
               dashboard.include?("Status only · lifecycle and mutation remain provider-managed") &&
               dashboard.include?("discovered capabilities grant no mutation authority"))

  offline_runner = FleetFakeRunner.new(pihole_offline: true)
  offline = SoulCore::MaintenanceFleetStatusService.new(
    runner: offline_runner,
    clock: -> { Time.utc(2026, 7, 27, 21, 5, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "maven" }
  ).collect
  offline_pihole = offline.dig("data", "devices").find { |device| device["id"] == "pihole" }
  check.call("one unreachable device remains visible without hiding healthy-device evidence or retrying",
             offline["lifecycle_state"] == "complete" &&
               offline_pihole["status"] == "offline" &&
               offline.dig("data", "summary", "reachable_count") == 2 &&
               offline_runner.calls.count { |call| call["argv"].include?("pihole-maintenance") } == 1)

  facade = SoulCore::ApplicationFacade.new(
    root: root,
    maintenance_fleet_status_service: FleetFacadeStub.new
  )
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "request.fleet.status.0001",
    "operation" => "maintenance.fleet.status",
    "parameters" => {},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call("application contract exposes only the parameterless fleet status operation",
             envelope["lifecycle_state"] == "complete" &&
               envelope.dig("data", "schema_version") == "soul.maintenance.fleet_status.v1")
end

if errors.empty?
  puts "Maintenance fleet status B1 verification passed."
  exit 0
end

warn "Maintenance fleet status B1 verification failed: #{errors.join(', ')}"
exit 1
