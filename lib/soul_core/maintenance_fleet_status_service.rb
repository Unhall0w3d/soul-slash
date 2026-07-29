# frozen_string_literal: true

require "json"
require "fileutils"
require "ipaddr"
require "rbconfig"
require "socket"
require "time"

require_relative "bounded_command_runner"
require_relative "apple_mobile_inventory_adapter"

module SoulCore
  class MaintenanceFleetStatusService
    SCHEMA_VERSION = "soul.maintenance.fleet_status.v1"
    COMMAND_TIMEOUT_SECONDS = 20
    DNF5_STATUS_TIMEOUT_SECONDS = 120
    MAX_OUTPUT_BYTES = 256 * 1024
    SSH_PATH = "/usr/bin/ssh"
    PING_PATH = "/usr/bin/ping"
    NMAP_PATH = "/usr/bin/nmap"
    ARP_PATH = "/proc/net/arp"
    ROUTE_PATH = "/proc/net/route"
    SYSTEMD_RUN_PATH = "/usr/bin/systemd-run"
    MAX_DHCP_RECOVERY_SCANS = 4
    MAX_SNAPSHOT_BYTES = 512 * 1024
    MAX_ROUTE_BYTES = 64 * 1024
    REGISTRY_SCHEMA = "soul.maintenance.fleet_registry.v1"
    MAX_ENROLLED_DEVICES = 64
    WORKSTATION_ID = "workstation"
    LEGACY_WORKSTATION_ID = "maven"
    SUPPORTED_PACKAGE_MANAGERS = %w[pacman yay paru apt apt-get dnf zypper apk flatpak snap nix].freeze
    DEFAULT_ADDRESSES = {
      WORKSTATION_ID => "local",
      "proxmox" => "proxmox-maintenance",
      "pihole" => "pihole-maintenance"
    }.freeze

    def initialize(
      runner: BoundedCommandRunner.new,
      clock: -> { Time.now.utc },
      ssh_config: File.expand_path("~/.ssh/config"),
      os_release_path: "/etc/os-release",
      hostname_reader: -> { Socket.gethostname },
      process_env: ENV,
      root: nil,
      nmap_path: NMAP_PATH,
      arp_path: ARP_PATH,
      route_path: ROUTE_PATH,
      systemd_run_path: SYSTEMD_RUN_PATH,
      ruby_path: RbConfig.ruby,
      recovery_scheduler: nil,
      apple_mobile_inventory_adapter: nil
    )
      @runner = runner
      @clock = clock
      @ssh_config = File.expand_path(ssh_config)
      @os_release_path = File.expand_path(os_release_path)
      @hostname_reader = hostname_reader
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @root = root && File.expand_path(root)
      @nmap_path = File.expand_path(nmap_path)
      @arp_path = File.expand_path(arp_path)
      @route_path = File.expand_path(route_path)
      @systemd_run_path = File.expand_path(systemd_run_path)
      @ruby_path = File.expand_path(ruby_path)
      @recovery_scheduler = recovery_scheduler
      @apple_mobile_inventory_adapter = apple_mobile_inventory_adapter || AppleMobileInventoryAdapter.new(runner: @runner)
      @addresses = {
        WORKSTATION_ID => configured_display_value(
          "SOUL_FLEET_WORKSTATION_ADDRESS",
          legacy_key: "SOUL_FLEET_MAVEN_ADDRESS",
          fallback: DEFAULT_ADDRESSES.fetch(WORKSTATION_ID)
        ),
        "proxmox" => configured_display_address("SOUL_FLEET_FORGE_ADDRESS", DEFAULT_ADDRESSES.fetch("proxmox")),
        "pihole" => configured_display_address("SOUL_FLEET_PIHOLE_ADDRESS", DEFAULT_ADDRESSES.fetch("pihole"))
      }.freeze
      @labels = {
        WORKSTATION_ID => configured_display_value(
          "SOUL_FLEET_WORKSTATION_LABEL",
          legacy_key: "SOUL_FLEET_MAVEN_LABEL",
          fallback: "Workstation"
        ),
        "pihole" => configured_display_address("SOUL_FLEET_PIHOLE_LABEL", "Pi-hole")
      }.freeze
      @snapshot_path = @root && File.join(@root, "Soul", "private", "host_maintenance", "fleet_status.json")
      @registry_path = @root && File.join(@root, "Soul", "private", "host_maintenance", "discovered_devices.json")
      @pending_recovery_path = @root && File.join(@root, "Soul", "private", "host_maintenance", "dhcp_recovery.json")
      @evidence = []
      @dhcp_scan_cache = {}
      @apple_mobile_inventory_scan = nil
    end

    def collect
      @evidence = []
      @dhcp_scan_cache = {}
      @apple_mobile_inventory_scan = nil
      devices = [
        collect_workstation,
        collect_proxmox,
        collect_pihole
      ]
      devices << collect_cisco_phone if cisco_phone_enabled?
      existing_addresses = devices.map { |device| device.fetch("address") }
      registry_records.each do |record|
        devices << collect_enrolled_device(record) unless existing_addresses.include?(record.fetch("address"))
      end
      collected_at = @clock.call.iso8601
      devices.each { |device| device["observed_at"] = collected_at }
      topology = build_topology(devices)

      response = success(
        "schema_version" => SCHEMA_VERSION,
        "collected_at" => collected_at,
        "freshness" => "on_demand",
        "read_only" => true,
        "devices" => devices,
        "summary" => summarize(devices),
        "topology" => topology,
        "evidence" => @evidence,
        "verification" => {
          "bounded_commands" => true,
          "background_polling" => false,
          "host_mutation" => false,
          "password_collected" => false,
          "fixed_targets" => true
        }
      )
      persist_snapshot(response.fetch("data")) if @snapshot_path
      response["mutation"] = "status_cache" if @snapshot_path
      response
    rescue StandardError => error
      failed("fleet status failed safely: #{safe_text(error.message)}")
    end

    def refresh(device_id:, schedule_recovery: true)
      @evidence = []
      @dhcp_scan_cache = {}
      @apple_mobile_inventory_scan = nil
      normalized_id = canonical_device_id(device_id.to_s.strip)
      return failed("device id is invalid") unless normalized_id.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}\z/)

      current = read_snapshot_data
      devices = Array(current["devices"])
      existing = devices.find { |device| device["id"] == normalized_id }
      return failed("device is not present in the current fleet snapshot") unless existing

      refreshed = collect_snapshot_device(existing, schedule_recovery: schedule_recovery)
      observed_at = @clock.call.iso8601
      refreshed["observed_at"] = observed_at
      updated_devices = devices.map { |device| device["id"] == normalized_id ? refreshed : device }
      data = current.merge(
        "collected_at" => observed_at,
        "freshness" => "on_demand_device",
        "read_only" => true,
        "devices" => updated_devices,
        "summary" => summarize(updated_devices),
        "topology" => build_topology(updated_devices),
        "evidence" => @evidence,
        "refreshed_device_id" => refreshed.fetch("id")
      )
      data.delete("source")
      persist_snapshot(data)
      success(data).merge("mutation" => "status_cache")
    rescue StandardError => error
      failed("device status refresh failed safely: #{safe_text(error.message)}")
    end

    def retry_pending
      @evidence = []
      @dhcp_scan_cache = {}
      pending = pending_recovery_records
      return success("schema_version" => SCHEMA_VERSION, "retried_device_count" => 0, "reason" => "no DHCP recovery is pending") if pending.empty?

      current = read_snapshot_data
      devices = Array(current["devices"])
      retried = []
      pending.each do |entry|
        existing = devices.find { |device| device["id"] == entry["device_id"] }
        record = registry_records.find { |candidate| candidate["id"] == entry["device_id"] }
        next unless existing && record && record["address_policy"] == "dhcp_tracked"

        refreshed = collect_enrolled_device(record, schedule_recovery: false)
        refreshed["observed_at"] = @clock.call.iso8601
        devices = devices.map { |device| device["id"] == entry["device_id"] ? refreshed : device }
        retried << entry["device_id"]
      end
      collected_at = @clock.call.iso8601
      data = current.merge(
        "collected_at" => collected_at,
        "freshness" => "delayed_dhcp_recovery",
        "read_only" => true,
        "devices" => devices,
        "summary" => summarize(devices),
        "topology" => build_topology(devices),
        "evidence" => @evidence,
        "dhcp_recovery" => {"retried_device_ids" => retried, "automatic_retry" => "complete_no_repeat"}
      )
      data.delete("source")
      persist_snapshot(data)
      clear_pending_recovery
      success(data).merge("mutation" => "status_cache")
    rescue StandardError => error
      clear_pending_recovery
      failed("delayed DHCP recovery failed safely: #{safe_text(error.message)}")
    end

    def snapshot
      success(read_snapshot_data.merge("source" => "persisted_snapshot"))
    rescue ArgumentError => error
      unavailable_snapshot(error.message)
    rescue JSON::ParserError, SystemCallError => error
      failed("fleet status snapshot could not be read safely: #{error.class}")
    end

    private

    def read_snapshot_data
      raise ArgumentError, "fleet status persistence is not configured" unless @snapshot_path
      raise ArgumentError, "no fleet status has been collected yet" unless File.exist?(@snapshot_path)
      raise ArgumentError, "fleet status snapshot path is unsafe" if File.symlink?(@snapshot_path)

      stat = File.stat(@snapshot_path)
      raise ArgumentError, "fleet status snapshot is not a private regular file" unless stat.file? && (stat.mode & 0o077).zero?
      raise ArgumentError, "fleet status snapshot exceeds its size bound" if stat.size > MAX_SNAPSHOT_BYTES

      parsed = JSON.parse(File.binread(@snapshot_path, MAX_SNAPSHOT_BYTES + 1))
      raise ArgumentError, "fleet status snapshot schema is unsupported" unless parsed["schema_version"] == SCHEMA_VERSION

      canonicalize_snapshot_data(parsed)
    end

    def collect_snapshot_device(existing, schedule_recovery: true)
      case canonical_device_id(existing["id"])
      when WORKSTATION_ID then collect_workstation
      when "proxmox" then collect_proxmox
      when "pihole" then collect_pihole
      when "cisco-8851"
        raise "Cisco phone status is no longer configured" unless cisco_phone_enabled?

        collect_cisco_phone
      else
        record = registry_records.find { |candidate| candidate["id"] == existing["id"] }
        raise "enrolled device is no longer present in the private registry" unless record

        collect_enrolled_device(record, schedule_recovery: schedule_recovery)
      end
    end

    def summarize(devices)
      states = devices.each_with_object(Hash.new(0)) { |device, counts| counts[device.fetch("status")] += 1 }
      {
        "device_count" => devices.length,
        "reachable_count" => devices.count { |device| device["reachable"] },
        "updates_available" => devices.sum { |device| device.dig("updates", "total").to_i },
        "reboot_required_count" => devices.count { |device| device.dig("reboot", "required") },
        "kernel_attention_count" => devices.count { |device| device.dig("kernel", "update_required") },
        "states" => states
      }
    end

    def collect_workstation
      kernel = local_run("workstation.kernel", "/usr/bin/uname", "-r")
      native = local_run("workstation.native_updates", "/usr/bin/pacman", "-Qu", accepted_exit_statuses: [0, 1])
      aur = local_run("workstation.aur_updates", "/usr/bin/yay", "-Qua", timeout: 30, accepted_exit_statuses: [0, 1])
      flatpak_user = local_run(
        "workstation.flatpak_user_updates",
        "/usr/bin/flatpak", "remote-ls", "--updates", "--user", "--columns=application,version,branch",
        timeout: 30
      )
      flatpak_system = local_run(
        "workstation.flatpak_system_updates",
        "/usr/bin/flatpak", "remote-ls", "--updates", "--system", "--columns=application,version,branch",
        timeout: 30
      )
      installed_kernel = local_run("workstation.installed_kernel", "/usr/bin/pacman", "-Q", "linux-cachyos")

      native_count = line_count(native, empty_exit_statuses: [0, 2])
      aur_count = line_count(aur)
      flatpak_count = line_count(flatpak_user) + line_count(flatpak_system)
      running_kernel = output(kernel)
      available_kernel = output(installed_kernel).split(/\s+/, 2)[1].to_s
      kernel_update = !available_kernel.empty? && !running_kernel.start_with?(available_kernel)
      updates = update_summary(
        native: native_count,
        aur: aur_count,
        flatpak: flatpak_count,
        freshness: "cached_pacman_metadata"
      )

      device(
        id: WORKSTATION_ID,
        label: @labels.fetch(WORKSTATION_ID),
        role: "Hyprland workstation · maintenance controller",
        address: @addresses.fetch(WORKSTATION_ID),
        reachable: true,
        os: os_release_summary,
        version: output(local_run("workstation.hyprland_version", "/usr/bin/hyprland", "-v")).lines.first.to_s.strip,
        kernel: kernel_summary(running_kernel, available_kernel, kernel_update),
        updates: updates,
        reboot: {"required" => kernel_update, "reason" => kernel_update ? "newer kernel package is installed" : "running kernel matches installed package"},
        services: [],
        facts: {
          "hostname" => safe_text(@hostname_reader.call),
          "management_channel" => "local",
          "flatpak_applicable" => flatpak_user.status != "unavailable" || flatpak_system.status != "unavailable"
        }
      )
    end

    def collect_proxmox
      reachable = remote_run("proxmox.reachability", "proxmox-maintenance", "/usr/bin/hostname")
      return offline_device("proxmox", "Proxmox", "Proxmox VE hypervisor", @addresses.fetch("proxmox"), reachable) unless successful?(reachable)

      node_name = bounded_node_name(output(reachable))
      version = remote_run("proxmox.version", "proxmox-maintenance", "/usr/bin/pveversion")
      kernel = remote_run("proxmox.kernel", "proxmox-maintenance", "/usr/bin/uname", "-r")
      boot_kernels = remote_run("proxmox.boot_kernels", "proxmox-maintenance", "/usr/sbin/proxmox-boot-tool", "kernel", "list")
      updates_result = remote_run(
        "proxmox.native_updates",
        "proxmox-maintenance",
        "/usr/bin/apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade",
        timeout: 30
      )
      reboot_file = remote_run(
        "proxmox.reboot_required",
        "proxmox-maintenance",
        "/usr/bin/test", "-e", "/var/run/reboot-required",
        accepted_exit_statuses: [0, 1]
      )
      lxc = remote_run(
        "proxmox.lxc_inventory",
        "proxmox-maintenance",
        "/usr/bin/pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"
      )
      running_kernel = output(kernel)
      available_kernel = newest_proxmox_kernel(output(boot_kernels))
      kernel_update = !available_kernel.empty? && running_kernel != available_kernel
      containers = parse_json_array(output(lxc)).map do |record|
        next unless record["type"] == "lxc"

        {
          "id" => record["vmid"],
          "name" => safe_text(record["name"]),
          "status" => safe_text(record["status"]),
          "tags" => safe_text(record["tags"]),
          "memory_bytes" => integer(record["mem"]),
          "max_memory_bytes" => integer(record["maxmem"]),
          "uptime_seconds" => integer(record["uptime"])
        }
      end.compact

      device(
        id: node_name,
        label: node_name.split("-").map(&:capitalize).join(" "),
        role: "Proxmox VE hypervisor",
        address: @addresses.fetch("proxmox"),
        reachable: true,
        os: "Proxmox VE on Debian",
        version: output(version),
        kernel: kernel_summary(running_kernel, available_kernel, kernel_update),
        updates: update_summary(native: apt_update_count(updates_result), freshness: "cached_apt_metadata"),
        reboot: {
          "required" => reboot_file.exit_status == 0 || kernel_update,
          "reason" => reboot_file.exit_status == 0 ? "reboot-required marker exists" : (kernel_update ? "newer Proxmox kernel is installed" : "no reboot evidence")
        },
        services: [],
        facts: {
          "hostname" => node_name,
          "platform" => "proxmox",
          "management_channel" => "ssh",
          "containers" => containers,
          "pihole_container" => containers.find { |record| record["id"] == 100 }
        }
      )
    end

    def collect_pihole
      reachable = remote_run("pihole.reachability", "pihole-maintenance", "/usr/bin/hostname")
      role = "Pi-hole DNS filtering · Unbound resolver · LXC 100"
      return offline_device("pihole", @labels.fetch("pihole"), role, @addresses.fetch("pihole"), reachable) unless successful?(reachable)

      version = remote_run("pihole.version", "pihole-maintenance", "/usr/local/bin/pihole", "-v")
      status = remote_run("pihole.status", "pihole-maintenance", "/usr/local/bin/pihole", "status")
      ftl = remote_run("pihole.ftl", "pihole-maintenance", "/usr/bin/systemctl", "is-active", "pihole-FTL")
      unbound = remote_run("pihole.unbound", "pihole-maintenance", "/usr/bin/systemctl", "is-active", "unbound")
      ssh = remote_run("pihole.ssh", "pihole-maintenance", "/usr/bin/systemctl", "is-active", "ssh")
      dns = remote_run(
        "pihole.dns_check",
        "pihole-maintenance",
        "/usr/bin/dig", "+time=2", "+tries=1", "@127.0.0.1", "pi.hole", "A", "+short"
      )
      updates_result = remote_run(
        "pihole.native_updates",
        "pihole-maintenance",
        "/usr/bin/apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade",
        timeout: 30
      )
      reboot_file = remote_run(
        "pihole.reboot_required",
        "pihole-maintenance",
        "/usr/bin/test", "-e", "/var/run/reboot-required",
        accepted_exit_statuses: [0, 1]
      )
      services = [
        service_record("Pi-hole FTL", ftl),
        service_record("Unbound", unbound),
        {"id" => "dns", "label" => "DNS query", "state" => successful?(dns) && !output(dns).empty? ? "active" : "failed"}
      ]
      healthy = successful?(ssh) && output(ssh) == "active" &&
        services.all? { |service| service["state"] == "active" } &&
        output(status).include?("Pi-hole blocking is enabled")

      device(
        id: "pihole",
        label: @labels.fetch("pihole"),
        role: role,
        address: @addresses.fetch("pihole"),
        reachable: true,
        os: "Debian 13 (LXC)",
        version: pihole_version_summary(output(version)),
        kernel: {"running" => "inherited from hypervisor", "available" => "managed by hypervisor", "update_required" => false},
        updates: update_summary(native: apt_update_count(updates_result), freshness: "cached_apt_metadata"),
        reboot: {
          "required" => reboot_file.exit_status == 0,
          "reason" => reboot_file.exit_status == 0 ? "reboot-required marker exists" : "no container reboot marker"
        },
        services: services,
        facts: {
          "hostname" => output(reachable),
          "management_channel" => "ssh",
          "ssh_state" => output(ssh),
          "blocking_enabled" => output(status).include?("Pi-hole blocking is enabled"),
          "dns_answer" => output(dns),
          "health" => healthy ? "healthy" : "attention"
        }
      )
    end

    def collect_cisco_phone
      address = cisco_phone_address
      label = configured_display_address("SOUL_FLEET_CISCO_PHONE_LABEL", "Cisco 8851")
      reachable = local_run(
        "cisco_phone.reachability",
        PING_PATH, "-c", "1", "-W", "2", address,
        timeout: 5
      )
      role = "Webex Calling desk phone · status only"
      return offline_device(
        "cisco-8851",
        label,
        role,
        address,
        reachable,
        control: "status_only",
        facts: cisco_phone_facts("unreachable")
      ) unless successful?(reachable)

      device(
        id: "cisco-8851",
        label: label,
        role: role,
        address: address,
        reachable: true,
        os: "Cisco IP Phone",
        version: "provider-managed · not queried",
        kernel: {"running" => "appliance-managed", "available" => "Webex-managed", "update_required" => false},
        updates: update_summary(freshness: "provider_managed"),
        reboot: {"required" => false, "reason" => "not assessed · provider-managed"},
        services: [
          {"id" => "network_reachability", "label" => "Network reachability", "state" => "active"}
        ],
        facts: cisco_phone_facts("reachable"),
        control: "status_only",
        status: "reachable"
      )
    end

    def collect_enrolled_device(record, schedule_recovery: true)
      stored_facts = record["facts"].is_a?(Hash) ? record["facts"] : {}
      facts = stored_facts.merge(
        "management_channel" => record.fetch("connection_mode") == "ssh" ? "ssh_inventory" : "icmp_status",
        "control_capability" => "inventory_only",
        "mutation_supported" => false,
        "enrollment_id" => record.fetch("id"),
        "address_policy" => record.fetch("address_policy", "fixed")
      )
      recovery = nil
      if record["address_policy"] == "dhcp_tracked"
        record, result, recovery = resolve_dhcp_record(record, schedule_recovery: schedule_recovery)
        facts = facts.merge(recovery)
      else
        result = if record.fetch("connection_mode") == "ssh"
                   enrolled_ssh_reachability(record.fetch("ssh_alias"))
                 else
                   local_run("enrolled_device.reachability", PING_PATH, "-c", "1", "-W", "2", record.fetch("address"), timeout: 5)
                 end
      end
      return offline_device(
        record.fetch("id"),
        record.fetch("label"),
        record.fetch("role"),
        record.fetch("address"),
        result,
        control: "inventory_only",
        facts: facts.merge("reachability" => "unreachable")
      ) unless successful?(result)

      package_managers = Array(facts["package_managers"])
        .map { |value| safe_text(value) }
        .select { |value| SUPPORTED_PACKAGE_MANAGERS.include?(value) }
        .uniq
      if record.fetch("connection_mode") == "ssh" &&
          facts["os_id"] == "fedora" &&
          package_managers.include?("dnf")
        return collect_fedora_inventory_device(record, facts, package_managers)
      end
      if record.fetch("connection_mode") == "ssh" && enrolled_proxmox?(record, facts)
        return collect_enrolled_proxmox_device(record, facts, package_managers)
      end
      if (mobile_inventory = apple_mobile_inventory_for(record))
        facts = facts.merge("apple_mobile_inventory" => mobile_inventory)
      end
      services = [
        {
          "id" => record.fetch("connection_mode") == "ssh" ? "ssh_inventory" : "network_reachability",
          "label" => record.fetch("connection_mode") == "ssh" ? "SSH inventory" : "Network reachability",
          "state" => "active"
        }
      ]
      if mobile_inventory
        services << {
          "id" => "apple_mobile_inventory",
          "label" => "Apple wired inventory",
          "state" => mobile_inventory["state"] == "available" ? "active" : "unavailable"
        }
      end
      device(
        id: record.fetch("id"),
        label: record.fetch("label"),
        role: record.fetch("role"),
        address: record.fetch("address"),
        reachable: true,
        os: facts["os_pretty_name"].to_s.empty? ? "Local network appliance" : facts["os_pretty_name"],
        version: package_managers.empty? ? "capabilities not queried" : "Packages · #{package_managers.join(" · ")}",
        kernel: {
          "running" => facts["kernel"].to_s.empty? ? "not queried" : facts["kernel"],
          "available" => "not queried",
          "update_required" => false
        },
        updates: update_summary(freshness: "not_queried"),
        reboot: {"required" => false, "reason" => "not assessed · inventory only"},
        services: services,
        facts: facts.merge("reachability" => "reachable", "package_managers" => package_managers),
        control: "inventory_only",
        status: "reachable"
      )
    end

    def enrolled_proxmox?(record, facts)
      return false unless facts["kernel"].to_s.end_with?("-pve")

      probe = remote_run(
        "enrolled_device.proxmox_probe",
        record.fetch("ssh_alias"),
        "/usr/bin/test", "-x", "/usr/bin/pveversion",
        accepted_exit_statuses: [0, 1]
      )
      probe.exit_status == 0
    end

    def collect_enrolled_proxmox_device(record, facts, package_managers)
      target = record.fetch("ssh_alias")
      version = remote_run("enrolled_proxmox.version", target, "/usr/bin/pveversion")
      kernel = remote_run("enrolled_proxmox.kernel", target, "/usr/bin/uname", "-r")
      boot_kernels = remote_run("enrolled_proxmox.boot_kernels", target, "/usr/sbin/proxmox-boot-tool", "kernel", "list")
      updates_result = remote_run(
        "enrolled_proxmox.native_updates",
        target,
        "/usr/bin/apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade",
        timeout: 30
      )
      reboot_file = remote_run(
        "enrolled_proxmox.reboot_required",
        target,
        "/usr/bin/test", "-e", "/var/run/reboot-required",
        accepted_exit_statuses: [0, 1]
      )
      guests_result = remote_run(
        "enrolled_proxmox.guest_inventory",
        target,
        "/usr/bin/pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"
      )
      running_kernel = output(kernel)
      available_kernel = newest_proxmox_kernel(output(boot_kernels))
      kernel_update = !available_kernel.empty? && running_kernel != available_kernel
      guests = parse_json_array(output(guests_result)).filter_map do |guest|
        next unless %w[lxc qemu].include?(guest["type"])

        {
          "id" => guest["vmid"],
          "type" => guest["type"],
          "name" => safe_text(guest["name"]),
          "status" => safe_text(guest["status"]),
          "tags" => safe_text(guest["tags"]),
          "memory_bytes" => integer(guest["mem"]),
          "max_memory_bytes" => integer(guest["maxmem"]),
          "uptime_seconds" => integer(guest["uptime"])
        }
      end
      enriched_facts = facts.merge(
        "platform" => "proxmox",
        "management_channel" => "ssh_inventory",
        "control_capability" => "inventory_only",
        "mutation_supported" => false,
        "status_adapter" => "proxmox_read_only",
        "package_managers" => package_managers,
        "guests" => guests
      )
      device(
        id: record.fetch("id"),
        label: record.fetch("label"),
        role: "Proxmox VE hypervisor · inventory only",
        address: record.fetch("address"),
        reachable: true,
        os: "Proxmox VE on Debian",
        version: output(version),
        kernel: kernel_summary(running_kernel, available_kernel, kernel_update),
        updates: update_summary(native: apt_update_count(updates_result), freshness: "cached_apt_metadata"),
        reboot: {
          "required" => reboot_file.exit_status == 0 || kernel_update,
          "reason" => reboot_file.exit_status == 0 ? "reboot-required marker exists" : (kernel_update ? "newer Proxmox kernel is installed" : "no reboot evidence")
        },
        services: [{"id" => "ssh_inventory", "label" => "SSH inventory", "state" => "active"}],
        facts: enriched_facts,
        control: "inventory_only"
      )
    end

    def collect_fedora_inventory_device(record, facts, package_managers)
      target = record.fetch("ssh_alias")
      updates_result = remote_run(
        "enrolled_device.dnf5_updates",
        target,
        "/usr/bin/dnf5", "--quiet", "check-upgrade",
        timeout: DNF5_STATUS_TIMEOUT_SECONDS,
        accepted_exit_statuses: [0, 100]
      )
      reboot_result = remote_run(
        "enrolled_device.dnf5_reboot",
        target,
        "/usr/bin/dnf5", "needs-restarting", "--json",
        timeout: 45
      )
      installed_kernels = remote_run(
        "enrolled_device.installed_kernels",
        target,
        "/usr/bin/rpm", "-q", "kernel-core"
      )
      running_kernel_result = remote_run(
        "enrolled_device.running_kernel",
        target,
        "/usr/bin/uname", "-r"
      )
      ssh = remote_run(
        "enrolled_device.ssh_service",
        target,
        "/usr/bin/systemctl", "is-active", "sshd"
      )
      guest_agent = remote_run(
        "enrolled_device.guest_agent",
        target,
        "/usr/bin/systemctl", "is-active", "qemu-guest-agent"
      )
      authority = remote_run(
        "enrolled_device.crucible_authority",
        target,
        "/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "self-check",
        timeout: 10
      )

      update_rows = dnf5_update_rows(updates_result)
      available_kernel = update_rows
        .find { |row| row.fetch("name").start_with?("kernel-core.") }
        &.fetch("version", nil)
      running_kernel = successful?(running_kernel_result) ? output(running_kernel_result) : facts["kernel"].to_s
      installed = output(installed_kernels).lines
        .map(&:strip)
        .filter_map { |line| line.delete_prefix("kernel-core-") unless line.empty? }
      newest_installed_kernel = installed.max_by { |version| version.scan(/\d+/).map(&:to_i) }
      kernel_reboot_required = !newest_installed_kernel.to_s.empty? &&
        !running_kernel.empty? &&
        running_kernel != newest_installed_kernel
      dnf_reboot_required = dnf5_reboot_required?(reboot_result)
      reboot_required = dnf_reboot_required || kernel_reboot_required
      authority_ready = crucible_authority_ready?(authority)
      services = [
        {
          "id" => "dnf5_evidence",
          "label" => "DNF5 evidence",
          "state" => successful?(updates_result) ? "active" : "failed"
        },
        service_record("SSH", ssh),
        service_record("QEMU guest agent", guest_agent),
        {
          "id" => "crucible_authority",
          "label" => "Crucible authority",
          "state" => authority_ready ? "active" : "unavailable"
        }
      ]

      device(
        id: record.fetch("id"),
        label: record.fetch("label"),
        role: record.fetch("role"),
        address: record.fetch("address"),
        reachable: true,
        os: facts["os_pretty_name"].to_s.empty? ? "Fedora Linux" : facts["os_pretty_name"],
        version: authority_ready ? "DNF5 · managed evidence" : "DNF5 · read-only evidence",
        kernel: {
          "running" => running_kernel,
          "available" => available_kernel || newest_installed_kernel || running_kernel,
          "update_required" => !available_kernel.to_s.empty? || kernel_reboot_required
        },
        updates: update_summary(native: update_rows.length, freshness: "live_dnf5_metadata"),
        reboot: {
          "required" => reboot_required,
          "reason" => if dnf_reboot_required
                        "DNF5 reports a reboot is required"
                      elsif kernel_reboot_required
                        "newer installed kernel requires reboot"
                      else
                        "DNF5 reports no reboot requirement"
                      end
        },
        services: services,
        facts: facts.merge(
          "reachability" => "reachable",
          "kernel" => running_kernel,
          "package_managers" => package_managers,
          "status_adapter" => authority_ready ? "dnf5_fixed_maintenance" : "dnf5_read_only",
          "control_target_id" => "crucible",
          "control_capability" => authority_ready ? "fixed_maintenance" : "inventory_only",
          "maintenance_authority" => authority_ready ? "root_owned_fixed_operations" : "unavailable",
          "dnf5_update_evidence" => successful?(updates_result) ? "available" : "unavailable",
          "installed_kernel_count" => installed.length,
          "mutation_supported" => authority_ready
        ),
        control: authority_ready ? "maintenance" : "inventory_only"
      )
    end

    def crucible_authority_ready?(result)
      return false unless successful?(result)

      parsed = JSON.parse(result.stdout.to_s)
      parsed.is_a?(Hash) &&
        parsed["version"] == "soul-crucible-maintenance-d1-v1" &&
        parsed["arbitrary_command_forwarding"] == false &&
        parsed["password_storage"] == false
    rescue JSON::ParserError
      false
    end

    def dnf5_update_rows(result)
      return [] unless successful?(result)

      result.stdout.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").lines.filter_map do |line|
        match = line.strip.match(/\A(\S+\.\S+)\s+(\S+)\s+(\S+)\z/)
        next unless match
        next if match[1] == "Name.Arch"

        {"name" => match[1], "version" => match[2], "repository" => match[3]}
      end
    end

    def dnf5_reboot_required?(result)
      return false unless successful?(result)

      parsed = JSON.parse(result.stdout.to_s)
      Array(parsed).any? { |entry| entry.is_a?(Hash) && entry["type"] == "reboot" && entry["reboot_required"] == true }
    rescue JSON::ParserError
      false
    end

    def resolve_dhcp_record(record, schedule_recovery:)
      expected_mac = record.fetch("mac_address")
      probe = local_run(
        "enrolled_device.dhcp_current_reachability",
        PING_PATH, "-c", "1", "-W", "2", record.fetch("address"),
        timeout: 5
      )
      observed_mac = arp_mac_for(record.fetch("address"))
      if successful?(probe) && observed_mac == expected_mac
        return [
          record,
          probe,
          {
            "identity_state" => "verified_current",
            "reviewed_mac" => expected_mac,
            "observed_mac" => observed_mac,
            "dhcp_recovery" => "not_needed"
          }
        ]
      end

      matches = locate_dhcp_mac(record.fetch("subnet"), expected_mac)
      if matches.length == 1
        resolved_address = matches.first
        if resolved_address != record.fetch("address")
          updated = retarget_dhcp_record(record, resolved_address)
          if updated
            refreshed_probe = local_run(
              "enrolled_device.dhcp_retarget_reachability",
              PING_PATH, "-c", "1", "-W", "2", resolved_address,
              timeout: 5
            )
            return [
              updated,
              refreshed_probe,
              {
                "identity_state" => "retargeted",
                "reviewed_mac" => expected_mac,
                "observed_mac" => expected_mac,
                "previous_address" => record.fetch("address"),
                "dhcp_recovery" => "address_updated"
              }
            ]
          end
          return [
            record,
            failed_result(probe),
            {
              "identity_state" => "address_conflict",
              "reviewed_mac" => expected_mac,
              "observed_mac" => observed_mac,
              "possible_address" => resolved_address,
              "dhcp_recovery" => "blocked_for_human_review"
            }
          ]
        end

        return [
          record,
          probe,
          {
            "identity_state" => "verified_after_scan",
            "reviewed_mac" => expected_mac,
            "observed_mac" => expected_mac,
            "dhcp_recovery" => "current_address_reconfirmed"
          }
        ] if successful?(probe)
      end

      scheduled = schedule_recovery && queue_pending_recovery(record, matches.length > 1 ? "ambiguous_mac" : "not_found")
      [
        record,
        failed_result(probe),
        {
          "identity_state" => matches.length > 1 ? "ambiguous_mac" : (observed_mac.empty? ? "offline" : "mac_mismatch"),
          "reviewed_mac" => expected_mac,
          "observed_mac" => observed_mac,
          "dhcp_recovery" => scheduled ? "retry_scheduled_for_ten_minutes" : "offline_until_next_check",
          "automatic_retry" => schedule_recovery ? "one" : "complete_no_repeat"
        }
      ]
    end

    def apple_mobile_inventory_for(record)
      return nil unless record["connection_mode"] == "status_only"
      return nil unless record["address_policy"] == "dhcp_tracked"

      reviewed_mac = record["mac_address"].to_s.downcase
      bound = record["inventory_adapter"] == "apple_mobile"
      scan = apple_mobile_inventory_scan
      projection = scan.fetch("devices", {})[reviewed_mac]
      if projection
        bind_apple_mobile_adapter(record) unless bound
        return projection.merge(
          "adapter" => "apple_mobile",
          "identity_match" => "reviewed_private_wifi_mac"
        )
      end
      return nil unless bound

      {
        "state" => scan.fetch("state", "unavailable"),
        "connection" => "unavailable",
        "adapter" => "apple_mobile",
        "identity_match" => "previously_reviewed",
        "battery_percent" => nil,
        "battery_is_charging" => nil,
        "external_power_connected" => nil,
        "fully_charged" => nil
      }
    end

    def apple_mobile_inventory_scan
      return @apple_mobile_inventory_scan if @apple_mobile_inventory_scan

      reviewed_macs = registry_records.filter_map do |record|
        record["mac_address"] if record["connection_mode"] == "status_only" &&
                                  record["address_policy"] == "dhcp_tracked"
      end
      @apple_mobile_inventory_scan = @apple_mobile_inventory_adapter.discover(reviewed_macs: reviewed_macs)
    end

    def bind_apple_mobile_adapter(record)
      records = registry_records
      updated = records.map do |candidate|
        candidate["id"] == record["id"] ? candidate.merge("inventory_adapter" => "apple_mobile") : candidate
      end
      persist_registry(updated)
    end

    def locate_dhcp_mac(subnet, expected_mac)
      return [] unless File.file?(@nmap_path) && File.executable?(@nmap_path)
      entries = @dhcp_scan_cache[subnet]
      unless entries
        if @dhcp_scan_cache.length >= MAX_DHCP_RECOVERY_SCANS
          @evidence << {
            "adapter" => "enrolled_device.dhcp_recovery_scan_budget",
            "status" => "failed",
            "exit_status" => nil,
            "truncated" => false
          }
          return []
        end

        result = @runner.run(
          @nmap_path,
          "-sn", "-n", "--max-retries", "1", "--host-timeout", "2s", subnet,
          timeout_seconds: 30,
          max_output_bytes: MAX_OUTPUT_BYTES,
          env: {"LC_ALL" => "C"}
        )
        @evidence << {
          "adapter" => "enrolled_device.dhcp_recovery_scan",
          "status" => result.status,
          "exit_status" => result.exit_status,
          "truncated" => result.truncated == true
        }
        entries = result.status == "ok" ? arp_entries : {}
        @dhcp_scan_cache[subnet] = entries
      end

      network = IPAddr.new(subnet)
      entries.filter_map do |address, mac|
        address if mac == expected_mac && network.include?(IPAddr.new(address))
      rescue IPAddr::InvalidAddressError
        nil
      end.uniq
    end

    def arp_mac_for(address)
      arp_entries[address].to_s
    end

    def arp_entries
      return {} unless File.file?(@arp_path) && !File.symlink?(@arp_path)

      File.foreach(@arp_path, encoding: "UTF-8").first(MAX_ENROLLED_DEVICES * 8 + 1).drop(1).each_with_object({}) do |line, entries|
        address, _hardware_type, flags, raw_mac, _mask, _device = line.split(/\s+/, 6)
        mac = raw_mac.to_s.downcase
        next unless flags == "0x2" && address.to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)
        next unless mac.match?(/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/)

        entries[address] = mac
      end
    rescue SystemCallError
      {}
    end

    def retarget_dhcp_record(record, new_address)
      records = registry_records
      return nil if records.any? { |candidate| candidate["id"] != record["id"] && candidate["address"] == new_address }

      changed_at = @clock.call.iso8601
      updated = record.merge(
        "address" => new_address,
        "address_history" => (
          Array(record["address_history"]) + [{
            "from" => record.fetch("address"),
            "to" => new_address,
            "changed_at" => changed_at,
            "reason" => "exact_reviewed_mac_match"
          }]
        ).last(8)
      )
      persist_registry(records.map { |candidate| candidate["id"] == record["id"] ? updated : candidate })
      updated
    end

    def failed_result(result)
      normalized = result.dup
      normalized.status = "failed"
      normalized.exit_status = 1 if normalized.exit_status.to_i.zero?
      normalized
    end

    def build_topology(devices)
      proxmox = devices.find { |device| device.dig("facts", "platform") == "proxmox" }
      proxmox_id = proxmox ? proxmox.fetch("id") : "proxmox"
      second_copy = devices.find { |device| device.dig("facts", "control_target_id") == "crucible" }
      second_copy_id = second_copy ? second_copy.fetch("id") : proxmox_id
      network = local_network_context
      gateway_device = devices.find { |device| device["address"] == network["gateway_address"] }
      gateway_node = gateway_device && {
        "id" => gateway_device.fetch("id"),
        "label" => gateway_device.fetch("label"),
        "role" => gateway_device.fetch("role"),
        "address" => gateway_device.fetch("address"),
        "status" => gateway_device.fetch("status")
      }
      gateway_node ||= {
        "id" => "default-gateway",
        "label" => "Default Gateway",
        "role" => "Local network edge · route evidence only",
        "address" => network["gateway_address"] || "unavailable",
        "status" => "unknown"
      }
      network["gateway_node_id"] = gateway_node.fetch("id")
      external_nodes = [
        {"id" => "internet", "label" => "WAN / Internet", "role" => "Package sources · recursive DNS roots", "address" => "cloud", "status" => "external"}
      ]
      if devices.any? { |device| device.fetch("id") == "cisco-8851" }
        external_nodes << {
          "id" => "webex-calling",
          "label" => "Webex Calling",
          "role" => "Provider-managed calling service",
          "address" => "cloud",
          "status" => "external"
        }
      end
      edges = [
        {"from" => gateway_node.fetch("id"), "to" => "internet", "label" => "default route · WAN uplink", "kind" => "wan"},
        {"from" => WORKSTATION_ID, "to" => proxmox_id, "label" => "SSH maintenance", "kind" => "management"},
        {"from" => proxmox_id, "to" => "pihole", "label" => "hosts LXC 100", "kind" => "containment"},
        {"from" => WORKSTATION_ID, "to" => "pihole", "label" => "primary DNS", "kind" => "dns"},
        {"from" => "pihole", "to" => "internet", "label" => "Unbound recursion · Quad9 fallback", "kind" => "upstream"},
        {
          "from" => WORKSTATION_ID,
          "to" => second_copy_id,
          "label" => second_copy ? "encrypted second copy · active" : "second-copy target · planned",
          "kind" => second_copy ? "backup" : "backup_planned"
        }
      ]
      if devices.any? { |device| device.fetch("id") == "cisco-8851" }
        edges << {"from" => "cisco-8851", "to" => "webex-calling", "label" => "Webex Calling · status not asserted", "kind" => "provider"}
      end
      devices.reject { |device| device["id"] == gateway_node["id"] }.each do |device|
        edges << {
          "from" => device.fetch("id"),
          "to" => gateway_node.fetch("id"),
          "label" => "default gateway",
          "kind" => "route"
        }
      end
      devices.select { |device| device.fetch("control") == "inventory_only" }.each do |device|
        channel = device.dig("facts", "management_channel") == "ssh_inventory" ? "fixed SSH inventory" : "bounded status probe"
        edges << {"from" => WORKSTATION_ID, "to" => device.fetch("id"), "label" => channel, "kind" => "inventory"}
      end
      device_nodes = devices.map do |device|
          {
            "id" => device.fetch("id"),
            "label" => device.fetch("label"),
            "role" => device.fetch("role"),
            "address" => device.fetch("address"),
            "status" => device.fetch("status")
          }
        end
      device_nodes << gateway_node unless device_nodes.any? { |node| node["id"] == gateway_node["id"] }
      network["lan_node_ids"] = device_nodes.reject { |node| node["id"] == gateway_node["id"] }.map { |node| node.fetch("id") }
      network["cloud_node_ids"] = external_nodes.map { |node| node.fetch("id") }
      {
        "layout" => "network_map",
        "network" => network,
        "nodes" => device_nodes + external_nodes,
        "edges" => edges
      }
    end

    def local_network_context
      return unavailable_network_context unless File.file?(@route_path) && !File.symlink?(@route_path)

      raw_routes = File.binread(@route_path, MAX_ROUTE_BYTES + 1)
      return unavailable_network_context if raw_routes.bytesize > MAX_ROUTE_BYTES

      rows = raw_routes.encode("UTF-8", invalid: :replace, undef: :replace).lines.first(257).drop(1).filter_map do |line|
        fields = line.split(/\s+/)
        next unless fields.length >= 8
        next unless fields[1].match?(/\A[0-9A-Fa-f]{8}\z/) &&
                    fields[2].match?(/\A[0-9A-Fa-f]{8}\z/) &&
                    fields[7].match?(/\A[0-9A-Fa-f]{8}\z/)

        {
          "interface" => safe_text(fields[0]).byteslice(0, 32).to_s,
          "destination" => route_hex_to_ipv4(fields[1]),
          "gateway" => route_hex_to_ipv4(fields[2]),
          "flags" => fields[3].to_i(16),
          "metric" => fields[6].to_i,
          "mask" => route_hex_to_ipv4(fields[7])
        }
      end
      default_route = rows
        .select { |row| row["destination"] == "0.0.0.0" && row["gateway"] != "0.0.0.0" && (row["flags"] & 0x2).positive? }
        .min_by { |row| row["metric"] }
      return unavailable_network_context unless default_route

      connected = rows.filter_map do |row|
        next unless row["interface"] == default_route["interface"] && row["gateway"] == "0.0.0.0"

        prefix = ipv4_mask_prefix(row["mask"])
        next unless prefix

        network = IPAddr.new("#{row["destination"]}/#{prefix}")
        [network, prefix]
      rescue IPAddr::InvalidAddressError
        nil
      end.select { |network, _prefix| network.include?(IPAddr.new(default_route["gateway"])) }
        .max_by { |_network, prefix| prefix }
      {
        "evidence" => "proc_net_route",
        "interface" => default_route.fetch("interface"),
        "gateway_address" => default_route.fetch("gateway"),
        "subnet" => connected ? "#{connected[0]}/#{connected[1]}" : "unavailable"
      }
    rescue SystemCallError, IPAddr::InvalidAddressError
      unavailable_network_context
    end

    def unavailable_network_context
      {
        "evidence" => "unavailable",
        "interface" => "unavailable",
        "gateway_address" => nil,
        "subnet" => "unavailable"
      }
    end

    def route_hex_to_ipv4(value)
      [value].pack("H*").bytes.reverse.join(".")
    end

    def ipv4_mask_prefix(mask)
      bits = IPAddr.new(mask).to_i.to_s(2).rjust(32, "0")
      return nil unless bits.match?(/\A1*0*\z/)

      bits.count("1")
    rescue IPAddr::InvalidAddressError
      nil
    end

    def device(id:, label:, role:, address:, reachable:, os:, version:, kernel:, updates:, reboot:, services:, facts:, control: "maintenance", status: nil)
      service_attention = services.any? { |service| service["state"] != "active" }
      status ||= if !reachable
                   "offline"
                 elsif service_attention || reboot["required"] || kernel["update_required"]
                   "attention"
                 elsif updates["total"].positive?
                   "updates_available"
                 else
                   "healthy"
                 end
      {
        "id" => id,
        "label" => label,
        "role" => role,
        "address" => address,
        "control" => control,
        "status" => status,
        "reachable" => reachable,
        "os" => safe_text(os),
        "version" => safe_text(version),
        "kernel" => kernel,
        "updates" => updates,
        "reboot" => reboot,
        "services" => services,
        "facts" => facts
      }
    end

    def offline_device(id, label, role, address, result, control: "maintenance", facts: {})
      {
        "id" => id,
        "label" => label,
        "role" => role,
        "address" => address,
        "control" => control,
        "status" => "offline",
        "reachable" => false,
        "os" => "unavailable",
        "version" => "unavailable",
        "kernel" => {"running" => "unavailable", "available" => "unavailable", "update_required" => false},
        "updates" => update_summary(freshness: "unavailable"),
        "reboot" => {"required" => false, "reason" => "unavailable while device is offline"},
        "services" => [],
        "facts" => facts.merge("connection_status" => result.status)
      }
    end

    def cisco_phone_enabled?
      %w[1 true yes on].include?(@process_env["SOUL_FLEET_CISCO_PHONE_ENABLED"].to_s.strip.downcase)
    end

    def registry_records
      return [] unless @registry_path && File.exist?(@registry_path)
      return [] if File.symlink?(@registry_path)

      stat = File.stat(@registry_path)
      return [] unless stat.file? && (stat.mode & 0o077).zero? && stat.size <= MAX_SNAPSHOT_BYTES

      parsed = JSON.parse(File.binread(@registry_path, MAX_SNAPSHOT_BYTES + 1))
      return [] unless parsed["schema_version"] == REGISTRY_SCHEMA && parsed["devices"].is_a?(Array)

      parsed["devices"].first(MAX_ENROLLED_DEVICES).filter_map do |record|
        next unless record.is_a?(Hash)
        next unless record["id"].to_s.match?(/\Amanaged_[a-f0-9]{16}\z/)
        next unless %w[status_only ssh].include?(record["connection_mode"])
        next unless record["address"].to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)
        next unless record["control"] == "inventory_only"
        next unless record["label"].to_s.length.between?(1, 80) && !record["label"].to_s.match?(/[[:cntrl:]]/)
        next unless record["role"].to_s.length.between?(1, 160)
        next unless record["facts"].is_a?(Hash)
        next if record["connection_mode"] == "ssh" && !record["ssh_alias"].to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/)

        policy = record["address_policy"].to_s.empty? ? "fixed" : record["address_policy"].to_s
        next unless %w[fixed dhcp_tracked].include?(policy)
        next if policy == "dhcp_tracked" && record["connection_mode"] != "status_only"
        mac = record["mac_address"].to_s.downcase
        next if policy == "dhcp_tracked" && !mac.match?(/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/)
        subnet = record["subnet"].to_s
        if policy == "dhcp_tracked"
          network = IPAddr.new(subnet)
          next unless network.ipv4? && network.prefix.between?(24, 32) && network.include?(IPAddr.new(record["address"]))
        end
        history = Array(record["address_history"]).first(8).filter_map do |event|
          event.slice("from", "to", "changed_at", "reason") if event.is_a?(Hash)
        end
        record.merge(
          "address_policy" => policy,
          "mac_address" => policy == "dhcp_tracked" ? mac : "",
          "subnet" => policy == "dhcp_tracked" ? subnet : "",
          "inventory_adapter" => record["inventory_adapter"] == "apple_mobile" ? "apple_mobile" : "",
          "address_history" => history
        )
      end
    rescue JSON::ParserError, SystemCallError, IPAddr::InvalidAddressError
      []
    end

    def persist_registry(records)
      raise "fleet registry persistence is not configured" unless @registry_path

      directory = File.dirname(@registry_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise "fleet registry directory is unsafe" if File.symlink?(directory)

      File.chmod(0o700, directory)
      payload = JSON.pretty_generate(
        "schema_version" => REGISTRY_SCHEMA,
        "updated_at" => @clock.call.iso8601,
        "devices" => records
      )
      raise "fleet registry exceeds its size bound" if payload.bytesize > MAX_SNAPSHOT_BYTES

      temporary = "#{@registry_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, @registry_path)
      File.chmod(0o600, @registry_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def queue_pending_recovery(record, reason)
      return false unless @pending_recovery_path

      existing = pending_recovery_records
      already_scheduled = File.file?(@pending_recovery_path) && !existing.empty?
      entry = {
        "device_id" => record.fetch("id"),
        "mac_address" => record.fetch("mac_address"),
        "subnet" => record.fetch("subnet"),
        "address" => record.fetch("address"),
        "reason" => reason,
        "queued_at" => @clock.call.iso8601,
        "attempts_remaining" => 1
      }
      pending = (existing.reject { |candidate| candidate["device_id"] == record["id"] } + [entry]).first(MAX_ENROLLED_DEVICES)
      persist_pending_recovery(pending)
      return true if already_scheduled

      scheduled = schedule_dhcp_recovery
      clear_pending_recovery unless scheduled
      scheduled
    end

    def pending_recovery_records
      return [] unless @pending_recovery_path && File.file?(@pending_recovery_path) && !File.symlink?(@pending_recovery_path)
      return [] if File.size(@pending_recovery_path) > MAX_SNAPSHOT_BYTES

      parsed = JSON.parse(File.binread(@pending_recovery_path, MAX_SNAPSHOT_BYTES + 1))
      return [] unless parsed["schema_version"] == "soul.maintenance.dhcp_recovery.v1" && parsed["devices"].is_a?(Array)

      parsed["devices"].first(MAX_ENROLLED_DEVICES).filter_map do |record|
        next unless record.is_a?(Hash) && record["device_id"].to_s.match?(/\Amanaged_[a-f0-9]{16}\z/)
        next unless record["mac_address"].to_s.match?(/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/)
        next unless record["attempts_remaining"] == 1

        record.slice("device_id", "mac_address", "subnet", "address", "reason", "queued_at", "attempts_remaining")
      end
    rescue JSON::ParserError, SystemCallError
      []
    end

    def persist_pending_recovery(records)
      directory = File.dirname(@pending_recovery_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise "DHCP recovery directory is unsafe" if File.symlink?(directory)

      payload = JSON.pretty_generate(
        "schema_version" => "soul.maintenance.dhcp_recovery.v1",
        "updated_at" => @clock.call.iso8601,
        "devices" => records
      )
      temporary = "#{@pending_recovery_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, @pending_recovery_path)
      File.chmod(0o600, @pending_recovery_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def clear_pending_recovery
      return unless @pending_recovery_path && File.file?(@pending_recovery_path) && !File.symlink?(@pending_recovery_path)

      File.delete(@pending_recovery_path)
    rescue SystemCallError
      nil
    end

    def schedule_dhcp_recovery
      return @recovery_scheduler.call if @recovery_scheduler
      return false unless @root && File.file?(@systemd_run_path) && File.executable?(@systemd_run_path)

      script = File.join(@root, "scripts", "soul-maintenance-fleet-dhcp-recheck")
      return false unless File.file?(script)

      result = @runner.run(
        @systemd_run_path,
        "--user",
        "--unit=soul-fleet-dhcp-recheck",
        "--on-active=10m",
        "--timer-property=AccuracySec=1s",
        "--collect",
        "--property=Type=oneshot",
        "--property=TimeoutStartSec=120",
        "--property=NoNewPrivileges=yes",
        "--property=ProtectSystem=strict",
        "--property=ReadWritePaths=#{File.dirname(@pending_recovery_path)}",
        "--property=RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6",
        @ruby_path,
        script,
        timeout_seconds: 10,
        max_output_bytes: 64 * 1024,
        env: {"LC_ALL" => "C"}
      )
      @evidence << {
        "adapter" => "enrolled_device.dhcp_recovery_schedule",
        "status" => result.status,
        "exit_status" => result.exit_status,
        "truncated" => result.truncated == true
      }
      result.status == "ok"
    end

    def enrolled_ssh_reachability(target)
      primary = remote_run("enrolled_device.reachability", target, "/usr/bin/hostname", timeout: 5)
      return primary if successful?(primary)

      remote_run("enrolled_device.reachability_fallback", target, "/bin/hostname", timeout: 5)
    end

    def cisco_phone_address
      value = @process_env["SOUL_FLEET_CISCO_PHONE_ADDRESS"].to_s.strip
      raise "Cisco phone address is required when fleet phone status is enabled" if value.empty?
      raise "Cisco phone address must be one IPv4 address or hostname" unless valid_network_address?(value)

      value
    end

    def cisco_phone_facts(reachability)
      {
        "platform" => "cisco_ip_phone",
        "configured_model" => "Cisco 8851",
        "calling_platform" => "Webex Calling",
        "management_channel" => "icmp_status",
        "control_capability" => "status_only",
        "mutation_supported" => false,
        "reachability" => reachability,
        "registration_status" => "not assessed",
        "firmware_status" => "provider-managed · not assessed",
        "web_status" => "not configured",
        "address_assignment" => "operator-configured · reserve DHCP address for stable tracking"
      }
    end

    def configured_display_address(key, fallback)
      value = @process_env[key].to_s.strip
      safe_text(value.empty? ? fallback : value)
    end

    def configured_display_value(key, legacy_key:, fallback:)
      value = @process_env[key].to_s.strip
      value = @process_env[legacy_key].to_s.strip if value.empty?
      safe_text(value.empty? ? fallback : value)
    end

    def canonical_device_id(value)
      return nil if value.nil?

      value.to_s == LEGACY_WORKSTATION_ID ? WORKSTATION_ID : value.to_s
    end

    def canonicalize_snapshot_data(parsed)
      devices = Array(parsed["devices"]).map do |device|
        next device unless device.is_a?(Hash)

        device.merge("id" => canonical_device_id(device["id"]))
      end
      topology = parsed["topology"].is_a?(Hash) ? parsed["topology"] : {}
      nodes = Array(topology["nodes"]).map do |node|
        node.is_a?(Hash) ? node.merge("id" => canonical_device_id(node["id"])) : node
      end
      edges = Array(topology["edges"]).map do |edge|
        next edge unless edge.is_a?(Hash)

        edge.merge(
          "from" => canonical_device_id(edge["from"]),
          "to" => canonical_device_id(edge["to"])
        )
      end
      network = topology["network"].is_a?(Hash) ? topology["network"].dup : nil
      if network
        network["gateway_node_id"] = canonical_device_id(network["gateway_node_id"]) if network.key?("gateway_node_id")
        network["lan_node_ids"] = Array(network["lan_node_ids"]).map { |id| canonical_device_id(id) } if network.key?("lan_node_ids")
        network["cloud_node_ids"] = Array(network["cloud_node_ids"]).map { |id| canonical_device_id(id) } if network.key?("cloud_node_ids")
      end
      canonical = parsed.merge(
        "devices" => devices,
        "topology" => topology.merge("nodes" => nodes, "edges" => edges)
      )
      canonical["topology"]["network"] = network if network
      canonical["refreshed_device_id"] = canonical_device_id(parsed["refreshed_device_id"]) if parsed.key?("refreshed_device_id")
      if parsed.dig("dhcp_recovery", "retried_device_ids").is_a?(Array)
        canonical["dhcp_recovery"] = parsed["dhcp_recovery"].merge(
          "retried_device_ids" => parsed.dig("dhcp_recovery", "retried_device_ids").map { |id| canonical_device_id(id) }
        )
      end
      canonical
    end

    def valid_network_address?(value)
      return true if value.match?(/\A(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\z/)

      value.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?\z/) &&
        value.split(".").all? { |label| label.length.between?(1, 63) && !label.start_with?("-") && !label.end_with?("-") }
    end

    def local_run(adapter, *argv, timeout: COMMAND_TIMEOUT_SECONDS, accepted_exit_statuses: [0])
      run(adapter, argv, timeout: timeout, accepted_exit_statuses: accepted_exit_statuses)
    end

    def remote_run(adapter, target, *argv, timeout: COMMAND_TIMEOUT_SECONDS, accepted_exit_statuses: [0])
      run(
        adapter,
        [
          SSH_PATH,
          "-F", @ssh_config,
          "-o", "BatchMode=yes",
          "-o", "ConnectTimeout=5",
          "-o", "ConnectionAttempts=1",
          "-o", "LogLevel=ERROR",
          target,
          *argv
        ],
        timeout: timeout,
        accepted_exit_statuses: accepted_exit_statuses
      )
    end

    def run(adapter, argv, timeout:, accepted_exit_statuses:)
      result = @runner.run(
        *argv,
        timeout_seconds: timeout,
        max_output_bytes: MAX_OUTPUT_BYTES,
        env: {"LC_ALL" => "C"}
      )
      normalized_result = result.dup
      normalized_result.status = "ok" if accepted_exit_statuses.include?(result.exit_status)
      @evidence << {
        "adapter" => adapter,
        "status" => normalized_result.status,
        "exit_status" => result.exit_status,
        "truncated" => result.truncated == true
      }
      normalized_result
    end

    def successful?(result, empty_exit_statuses: [0])
      result.status == "ok" || empty_exit_statuses.include?(result.exit_status)
    end

    def output(result)
      safe_text(result.stdout).strip
    end

    def line_count(result, empty_exit_statuses: [0])
      return 0 unless successful?(result, empty_exit_statuses: empty_exit_statuses)

      output(result).lines.count { |line| !line.strip.empty? }
    end

    def apt_update_count(result)
      return 0 unless successful?(result)

      output(result).lines.count { |line| line.start_with?("Inst ") }
    end

    def update_summary(native: 0, aur: 0, flatpak: 0, freshness:)
      native_count = integer(native)
      aur_count = integer(aur)
      flatpak_count = integer(flatpak)
      {
        "native" => native_count,
        "aur" => aur_count,
        "flatpak" => flatpak_count,
        "total" => native_count + aur_count + flatpak_count,
        "freshness" => freshness
      }
    end

    def kernel_summary(running, available, update_required)
      {
        "running" => safe_text(running),
        "available" => safe_text(available.empty? ? running : available),
        "update_required" => update_required == true
      }
    end

    def newest_proxmox_kernel(value)
      kernels = value.lines.filter_map do |line|
        match = line.strip.match(/\A(\d+\.\d+\.\d+-\d+-pve)\z/)
        match && match[1]
      end
      kernels.max_by { |version| version.split(/[.-]/).map { |part| Integer(part) rescue 0 } }.to_s
    end

    def pihole_version_summary(value)
      versions = value.lines.filter_map do |line|
        match = line.match(/\A(Core|Web|FTL) version is ([^ ]+)/)
        "#{match[1]} #{match[2]}" if match
      end
      versions.join(" · ")
    end

    def service_record(label, result)
      {"id" => label.downcase.gsub(/[^a-z0-9]+/, "_"), "label" => label, "state" => output(result) == "active" ? "active" : "failed"}
    end

    def parse_json_array(value)
      parsed = JSON.parse(value)
      parsed.is_a?(Array) ? parsed.first(128) : []
    rescue JSON::ParserError
      []
    end

    def bounded_node_name(value)
      name = value.to_s.strip.downcase
      raise "Proxmox returned an invalid node identity" unless name.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)

      name
    end

    def os_release_summary
      values = {}
      File.foreach(@os_release_path, encoding: "UTF-8") do |line|
        key, value = line.strip.split("=", 2)
        next if key.to_s.empty? || value.nil?

        values[key] = value.sub(/\A["']/, "").sub(/["']\z/, "")
      end
      values["PRETTY_NAME"].to_s.empty? ? values["NAME"].to_s : values["PRETTY_NAME"].to_s
    rescue SystemCallError
      "Linux workstation"
    end

    def integer(value)
      Integer(value)
    rescue ArgumentError, TypeError
      0
    end

    def safe_text(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").byteslice(0, 4096).to_s
    end

    def persist_snapshot(data)
      directory = File.dirname(@snapshot_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise "fleet status directory is unsafe" if File.symlink?(directory)

      File.chmod(0o700, directory)
      payload = JSON.pretty_generate(data)
      raise "fleet status snapshot exceeds its size bound" if payload.bytesize > MAX_SNAPSHOT_BYTES

      temporary = "#{@snapshot_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, @snapshot_path)
      File.chmod(0o600, @snapshot_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def unavailable_snapshot(reason)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "data" => {
          "schema_version" => SCHEMA_VERSION,
          "available" => false,
          "reason" => reason,
          "source" => "persisted_snapshot"
        },
        "mutation" => "none"
      }
    end

    def success(data)
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "none"}
    end

    def failed(reason)
      {"ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => {}, "mutation" => "none"}
    end
  end
end
