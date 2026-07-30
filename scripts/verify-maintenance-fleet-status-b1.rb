#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
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

    target_index = argv.index { |value| %w[proxmox-maintenance pihole-maintenance foundry].include?(value) }
    return failed("unexpected command", 127) unless target_index

    target = argv[target_index]
    remote = argv[(target_index + 1)..]
    return failed("network unavailable", 255) if @pihole_offline && target == "pihole-maintenance"
    return proxmox(remote, target == "foundry" ? "foundry" : "forge") if %w[proxmox-maintenance foundry].include?(target)
    return pihole(remote) if target == "pihole-maintenance"

    failed("unexpected target", 127)
  end

  private

  def proxmox(remote, node_name)
    return ok("#{node_name}\n") if remote == ["/usr/bin/hostname"]
    return ok("") if remote == ["/usr/bin/test", "-x", "/usr/bin/pveversion"]
    return ok("pve-manager/9.2.5/fixture (running kernel: 7.0.2-6-pve)\n") if remote == ["/usr/bin/pveversion"]
    return ok("7.0.2-6-pve\n") if remote == ["/usr/bin/uname", "-r"]
    if remote == ["/usr/sbin/proxmox-boot-tool", "kernel", "list"]
      return ok("Automatically selected kernels:\n7.0.14-6-pve\n7.0.2-6-pve\n")
    end
    return ok("Inst pve-manager [9.2.5] (9.2.6 fixture)\n1 upgraded, 0 newly installed\n") if remote.include?("dist-upgrade")
    return failed("", 1) if remote == ["/usr/bin/test", "-e", "/var/run/reboot-required"]
    if remote == ["/usr/bin/pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"]
      return ok(JSON.generate([{
        "vmid" => node_name == "foundry" ? 201 : 100, "type" => node_name == "foundry" ? "qemu" : "lxc", "node" => node_name,
        "name" => node_name == "foundry" ? "lab-fixture" : "pihole", "status" => "running", "tags" => node_name == "foundry" ? "lab" : "adblock;community-script",
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

  def refresh(device_id:)
    collect.tap { |result| result["data"]["refreshed_device_id"] = device_id }
  end
end

puts "Maintenance fleet status B1 verification:"

Dir.mktmpdir("soul-fleet-status-") do |root|
  os_release = File.join(root, "os-release")
  File.write(os_release, "PRETTY_NAME=\"CachyOS fixture\"\n")
  route_path = File.join(root, "route")
  File.write(route_path, <<~ROUTES)
    Iface	Destination	Gateway	Flags	RefCnt	Use	Metric	Mask	MTU	Window	IRTT
    eth0	00000000	0132A8C0	0003	0	0	100	00000000	0	0	0
    eth0	0032A8C0	00000000	0001	0	0	100	00FFFFFF	0	0	0
  ROUTES
  runner = FleetFakeRunner.new
  service = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    clock: -> { Time.utc(2026, 7, 27, 21, 0, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "atelier" },
    process_env: {
      "SOUL_FLEET_WORKSTATION_ADDRESS" => "atelier.example.test",
      "SOUL_FLEET_WORKSTATION_LABEL" => "Atelier",
      "SOUL_FLEET_MAVEN_ADDRESS" => "legacy.example.test",
      "SOUL_FLEET_MAVEN_LABEL" => "Legacy Maven",
      "SOUL_FLEET_PIHOLE_LABEL" => "Warden"
    },
    route_path: route_path
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
             devices.dig("workstation", "label") == "Atelier" &&
               devices.dig("workstation", "address") == "atelier.example.test" &&
               devices.dig("workstation", "updates", "total") == 4 &&
               devices.dig("workstation", "updates", "freshness") == "cached_pacman_metadata" &&
               devices.dig("workstation", "kernel", "running") == "7.1.4-1-cachyos-eevdf-lto" &&
               devices.dig("workstation", "kernel", "available") == "7.1.5-1" &&
               devices.dig("workstation", "kernel", "update_required") == true)
  check.call("Proxmox discovers Forge and exposes cached package, kernel, and LXC 100 evidence",
             devices.dig("forge", "label") == "Forge" &&
               devices.dig("forge", "updates", "native") == 1 &&
               devices.dig("forge", "kernel", "available") == "7.0.14-6-pve" &&
               devices.dig("forge", "kernel", "update_required") == true &&
               devices.dig("forge", "facts", "pihole_container", "id") == 100 &&
               devices.dig("forge", "facts", "pihole_container", "status") == "running")
  check.call("Pi-hole exposes versions, DNS health, services, and package evidence",
             devices.dig("pihole", "label") == "Warden" &&
               devices.dig("pihole", "role").include?("Pi-hole DNS filtering") &&
               devices.dig("pihole", "version").include?("Core v6.4.3") &&
               devices.dig("pihole", "updates", "native") == 2 &&
               devices.dig("pihole", "facts", "blocking_enabled") == true &&
               devices.dig("pihole", "services").all? { |service_record| service_record["state"] == "active" })
  check.call("summary and network-map topology derive from the same device and route evidence",
             data.dig("summary", "reachable_count") == 3 &&
               data.dig("summary", "updates_available") == 7 &&
               data.dig("summary", "kernel_attention_count") == 2 &&
               data.dig("topology", "layout") == "network_map" &&
               data.dig("topology", "network", "interface") == "eth0" &&
               data.dig("topology", "network", "gateway_address") == "192.168.50.1" &&
               data.dig("topology", "network", "subnet") == "192.168.50.0/24" &&
               data.dig("topology", "network", "gateway_node_id") == "default-gateway" &&
               data.dig("topology", "edges").any? { |edge| edge["kind"] == "wan" && edge["from"] == "default-gateway" } &&
               data.dig("topology", "edges").any? { |edge| edge["kind"] == "route" && edge["from"] == "workstation" && edge["to"] == "default-gateway" } &&
               data.dig("topology", "edges").any? { |edge| edge["kind"] == "backup_planned" } &&
               data.dig("topology", "nodes").map { |node| node["id"] }.include?("pihole"))
  crucible_topology = service.send(
    :build_topology,
    data.fetch("devices") + [{
      "id" => "managed_0123456789abcdef",
      "label" => "Crucible",
      "role" => "Fedora backup target",
      "address" => "192.168.50.2",
      "status" => "healthy",
      "control" => "maintenance",
      "facts" => {"control_target_id" => "crucible"}
    }]
  )
  check.call("an enrolled Crucible replaces the planned Proxmox backup edge with its active encrypted second-copy path",
             crucible_topology.fetch("edges").any? do |edge|
               edge["kind"] == "backup" &&
                 edge["from"] == "workstation" &&
                 edge["to"] == "managed_0123456789abcdef" &&
                 edge["label"] == "encrypted second copy · active"
             end &&
               crucible_topology.fetch("edges").none? { |edge| edge["kind"] == "backup_planned" })
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
    "SOUL_FLEET_MAVEN_LABEL" => "Workstation",
    "SOUL_FLEET_FORGE_ADDRESS" => "forge.example.test",
    "SOUL_FLEET_PIHOLE_ADDRESS" => "pihole.example.test",
    "SOUL_FLEET_PIHOLE_LABEL" => "DNS Warden",
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
    hostname_reader: -> { "legacy-hostname" },
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
  check.call("legacy Maven environment variables remain read-compatible while output stays canonical",
             phone_data.fetch("devices").find { |device| device["id"] == "workstation" }["address"] == "maven.example.test" &&
               phone_data.fetch("devices").none? { |device| device["id"] == "maven" })
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
    hostname_reader: -> { "atelier" },
    process_env: phone_env
  ).collect.dig("data", "devices").find { |device| device["id"] == "cisco-8851" }
  check.call("unreachable Cisco phone remains visible and status-only",
             unavailable_phone["status"] == "offline" &&
               unavailable_phone["control"] == "status_only" &&
               unavailable_phone.dig("facts", "reachability") == "unreachable")

  source = File.read(File.join(__dir__, "../lib/soul_core/maintenance_fleet_status_service.rb"))
  dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
  stylesheet = File.read(File.join(__dir__, "../assets/dashboard/dashboard.css"))
  check.call("public service defaults contain no operator-specific RFC1918 addresses",
             !source.match?(/\b192\.168\.\d{1,3}\.\d{1,3}\b/))
  check.call("dashboard suppresses mutation controls for status-only and inventory-only devices",
             dashboard.include?('const inventoryOnly = device.control !== "maintenance"') &&
               dashboard.include?("Status only · lifecycle and mutation remain provider-managed") &&
               dashboard.include?("discovered capabilities grant no mutation authority"))
  check.call("dashboard exposes one-device refresh with a visible observation timestamp",
             dashboard.include?('callSoul("maintenance.fleet.device.refresh", { device_id: deviceId }') &&
               dashboard.include?('["Checked", observedLabel]') &&
               dashboard.include?("only this device was probed"))
  html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
  check.call("dashboard separates SSH-integrated systems from compact status-only presence",
             html.include?('id="maintenance-managed-device-grid"') &&
               html.include?('id="maintenance-status-device-grid"') &&
               dashboard.include?("const managedDevices = (data.devices || []).filter") &&
               dashboard.include?("const statusDevices = (data.devices || []).filter(maintenanceDeviceIsStatusOnly)") &&
               stylesheet.match?(/\.maintenance-device-card--status-only\s*\{[^}]*align-self:start/))
  check.call("dashboard presents route flow as WAN to gateway to LAN and keeps secondary relationships below",
             dashboard.include?("maintenance-network-map") &&
               dashboard.include?("WAN & provider cloud") &&
               dashboard.include?("Default gateway") &&
               dashboard.include?("Local switching & routing") &&
               dashboard.include?("Management, services & data paths") &&
               dashboard.include?('!["route", "wan"].includes(edge.kind)'))

  missing_route_data = SoulCore::MaintenanceFleetStatusService.new(
    runner: FleetFakeRunner.new,
    clock: -> { Time.utc(2026, 7, 27, 21, 2, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "atelier" },
    route_path: File.join(root, "missing-route")
  ).collect.fetch("data")
  check.call("missing route evidence degrades safely without hiding known devices",
             missing_route_data.dig("topology", "network", "evidence") == "unavailable" &&
               missing_route_data.dig("topology", "network", "gateway_address").nil? &&
               missing_route_data.dig("topology", "nodes").any? { |node| node["id"] == "workstation" })

  private_root = File.join(root, "private-root")
  registry_directory = File.join(private_root, "Soul", "private", "host_maintenance")
  FileUtils.mkdir_p(registry_directory, mode: 0o700)
  registry_path = File.join(registry_directory, "discovered_devices.json")
  File.write(registry_path, JSON.pretty_generate({
    "schema_version" => "soul.maintenance.fleet_registry.v1",
    "devices" => [{
      "id" => "managed_0123456789abcdef",
      "label" => "Test Router",
      "role" => "Discovered local appliance · status only",
      "address" => "192.0.2.1",
      "connection_mode" => "status_only",
      "control" => "inventory_only",
      "facts" => {"capability_probe" => "status_only"}
    }, {
      "id" => "managed_1111111111111111",
      "label" => "Foundry",
      "role" => "Discovered Linux device · inventory only",
      "address" => "192.0.2.7",
      "connection_mode" => "ssh",
      "ssh_alias" => "foundry",
      "control" => "inventory_only",
      "facts" => {
        "platform" => "linux",
        "os_id" => "debian",
        "os_pretty_name" => "Debian GNU/Linux 13 (trixie)",
        "kernel" => "7.0.2-6-pve",
        "package_managers" => ["apt", "apt-get"]
      }
    }]
  }))
  File.chmod(0o600, registry_path)
  refresh_runner = FleetFakeRunner.new
  clock_values = [
    Time.utc(2026, 7, 27, 21, 6, 0),
    Time.utc(2026, 7, 27, 21, 6, 15),
    Time.utc(2026, 7, 27, 21, 6, 30),
    Time.utc(2026, 7, 27, 21, 7, 0)
  ].each
  refresh_service = SoulCore::MaintenanceFleetStatusService.new(
    runner: refresh_runner,
    clock: -> { clock_values.next },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "atelier" },
    root: private_root
  )
  initial = refresh_service.collect
  foundry = initial.dig("data", "devices").find { |device| device["id"] == "managed_1111111111111111" }
  check.call("an enrolled PVE kernel and executable promote one SSH record to rich read-only Proxmox inventory",
             foundry["label"] == "Foundry" &&
               foundry["control"] == "inventory_only" &&
               foundry["role"] == "Proxmox VE hypervisor · inventory only" &&
               foundry["version"].include?("pve-manager/9.2.5") &&
               foundry.dig("updates", "freshness") == "cached_apt_metadata" &&
               foundry.dig("kernel", "available") == "7.0.14-6-pve" &&
               foundry.dig("facts", "platform") == "proxmox" &&
               foundry.dig("facts", "status_adapter") == "proxmox_read_only" &&
               foundry.dig("facts", "mutation_supported") == false &&
               foundry.dig("facts", "guests", 0, "type") == "qemu")
  calls_before_foundry_refresh = refresh_runner.calls.length
  foundry_refresh = refresh_service.refresh(device_id: "managed_1111111111111111")
  refreshed_foundry = foundry_refresh.dig("data", "devices").find { |device| device["id"] == "managed_1111111111111111" }
  foundry_refresh_calls = refresh_runner.calls.drop(calls_before_foundry_refresh)
  check.call("one-device refresh retains the enrolled Foundry identity instead of substituting Forge",
             foundry_refresh["lifecycle_state"] == "complete" &&
               refreshed_foundry["label"] == "Foundry" &&
               refreshed_foundry["id"] == "managed_1111111111111111" &&
               foundry_refresh_calls.all? { |call| call["argv"].include?("foundry") } &&
               foundry_refresh_calls.none? { |call| call["argv"].include?("proxmox-maintenance") })
  legacy_workstation_refresh = refresh_service.refresh(device_id: "maven")
  check.call("legacy Maven refresh requests resolve to the canonical workstation identity",
             legacy_workstation_refresh["lifecycle_state"] == "complete" &&
               legacy_workstation_refresh.dig("data", "refreshed_device_id") == "workstation" &&
               legacy_workstation_refresh.dig("data", "devices").none? { |device| device["id"] == "maven" })
  calls_before_refresh = refresh_runner.calls.length
  refreshed = refresh_service.refresh(device_id: "managed_0123456789abcdef")
  refreshed_router = refreshed.dig("data", "devices").find { |device| device["id"] == "managed_0123456789abcdef" }
  refresh_calls = refresh_runner.calls.drop(calls_before_refresh)
  check.call("one-device refresh probes only the selected status-only appliance and replaces its persisted card",
             initial["lifecycle_state"] == "complete" &&
               refreshed["lifecycle_state"] == "complete" &&
               refreshed["mutation"] == "status_cache" &&
               refreshed.dig("data", "freshness") == "on_demand_device" &&
               refreshed.dig("data", "refreshed_device_id") == "managed_0123456789abcdef" &&
               refreshed_router["observed_at"] == "2026-07-27T21:07:00Z" &&
               refresh_calls.length == 1 &&
               refresh_calls.first.dig("argv", 0) == "/usr/bin/ping" &&
               refresh_calls.first.dig("argv", 5) == "192.0.2.1")
  persisted = JSON.parse(File.read(File.join(registry_directory, "fleet_status.json")))
  check.call("one-device refresh preserves the fleet and stores its bounded observation",
             persisted.fetch("devices").length == initial.dig("data", "devices").length &&
               persisted["refreshed_device_id"] == "managed_0123456789abcdef" &&
               persisted.fetch("devices").find { |device| device["id"] == "managed_0123456789abcdef" }["observed_at"] == "2026-07-27T21:07:00Z")
  stale_refresh = refresh_service.refresh(device_id: "managed_ffffffffffffffff")
  check.call("unknown device refresh fails without probing or changing the snapshot",
             stale_refresh["lifecycle_state"] == "failed" &&
               stale_refresh["mutation"] == "none" &&
               refresh_runner.calls.length == calls_before_refresh + 1 &&
               JSON.parse(File.read(File.join(registry_directory, "fleet_status.json"))) == persisted)

  offline_runner = FleetFakeRunner.new(pihole_offline: true)
  offline = SoulCore::MaintenanceFleetStatusService.new(
    runner: offline_runner,
    clock: -> { Time.utc(2026, 7, 27, 21, 5, 0) },
    ssh_config: File.join(root, "ssh_config"),
    os_release_path: os_release,
    hostname_reader: -> { "atelier" }
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
  refresh_envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "request.fleet.refresh.0001",
    "operation" => "maintenance.fleet.device.refresh",
    "parameters" => {"device_id" => "managed_0123456789abcdef"},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call("application contract exposes bounded one-device fleet refresh",
             refresh_envelope["lifecycle_state"] == "complete" &&
               refresh_envelope.dig("data", "refreshed_device_id") == "managed_0123456789abcdef")
end

if errors.empty?
  puts "Maintenance fleet status B1 verification passed."
  exit 0
end

warn "Maintenance fleet status B1 verification failed: #{errors.join(', ')}"
exit 1
