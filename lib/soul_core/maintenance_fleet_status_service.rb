# frozen_string_literal: true

require "json"
require "fileutils"
require "socket"
require "time"

require_relative "bounded_command_runner"

module SoulCore
  class MaintenanceFleetStatusService
    SCHEMA_VERSION = "soul.maintenance.fleet_status.v1"
    COMMAND_TIMEOUT_SECONDS = 20
    MAX_OUTPUT_BYTES = 256 * 1024
    SSH_PATH = "/usr/bin/ssh"
    LOCAL_ADDRESS = "192.168.124.238"
    PROXMOX_ADDRESS = "192.168.124.225"
    PIHOLE_ADDRESS = "192.168.124.206"
    MAX_SNAPSHOT_BYTES = 512 * 1024

    def initialize(
      runner: BoundedCommandRunner.new,
      clock: -> { Time.now.utc },
      ssh_config: File.expand_path("~/.ssh/config"),
      os_release_path: "/etc/os-release",
      hostname_reader: -> { Socket.gethostname },
      root: nil
    )
      @runner = runner
      @clock = clock
      @ssh_config = File.expand_path(ssh_config)
      @os_release_path = File.expand_path(os_release_path)
      @hostname_reader = hostname_reader
      @snapshot_path = root && File.join(File.expand_path(root), "Soul", "private", "host_maintenance", "fleet_status.json")
      @evidence = []
    end

    def collect
      @evidence = []
      devices = [
        collect_workstation,
        collect_proxmox,
        collect_pihole
      ]
      topology = build_topology(devices)
      states = devices.each_with_object(Hash.new(0)) { |device, counts| counts[device.fetch("status")] += 1 }

      response = success(
        "schema_version" => SCHEMA_VERSION,
        "collected_at" => @clock.call.iso8601,
        "freshness" => "on_demand",
        "read_only" => true,
        "devices" => devices,
        "summary" => {
          "device_count" => devices.length,
          "reachable_count" => devices.count { |device| device["reachable"] },
          "updates_available" => devices.sum { |device| device.dig("updates", "total").to_i },
          "reboot_required_count" => devices.count { |device| device.dig("reboot", "required") },
          "kernel_attention_count" => devices.count { |device| device.dig("kernel", "update_required") },
          "states" => states
        },
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

    def snapshot
      return unavailable_snapshot("fleet status persistence is not configured") unless @snapshot_path
      return unavailable_snapshot("no fleet status has been collected yet") unless File.exist?(@snapshot_path)
      return unavailable_snapshot("fleet status snapshot path is unsafe") if File.symlink?(@snapshot_path)

      stat = File.stat(@snapshot_path)
      return unavailable_snapshot("fleet status snapshot is not a private regular file") unless stat.file? && (stat.mode & 0o077).zero?
      return unavailable_snapshot("fleet status snapshot exceeds its size bound") if stat.size > MAX_SNAPSHOT_BYTES

      parsed = JSON.parse(File.binread(@snapshot_path, MAX_SNAPSHOT_BYTES + 1))
      return unavailable_snapshot("fleet status snapshot schema is unsupported") unless parsed["schema_version"] == SCHEMA_VERSION

      success(parsed.merge("source" => "persisted_snapshot"))
    rescue JSON::ParserError, SystemCallError => error
      failed("fleet status snapshot could not be read safely: #{error.class}")
    end

    private

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
        id: "maven",
        label: "Maven",
        role: "Hyprland workstation · maintenance controller",
        address: LOCAL_ADDRESS,
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
      return offline_device("proxmox", "Proxmox", "Proxmox VE hypervisor", PROXMOX_ADDRESS, reachable) unless successful?(reachable)

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
        address: PROXMOX_ADDRESS,
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
      return offline_device("pihole", "Pi-hole", "DNS filtering · Unbound resolver · LXC 100", PIHOLE_ADDRESS, reachable) unless successful?(reachable)

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
        label: "Pi-hole",
        role: "DNS filtering · Unbound resolver · LXC 100",
        address: PIHOLE_ADDRESS,
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

    def build_topology(devices)
      proxmox = devices.find { |device| device.dig("facts", "platform") == "proxmox" }
      proxmox_id = proxmox ? proxmox.fetch("id") : "proxmox"
      {
        "nodes" => devices.map do |device|
          {
            "id" => device.fetch("id"),
            "label" => device.fetch("label"),
            "role" => device.fetch("role"),
            "address" => device.fetch("address"),
            "status" => device.fetch("status")
          }
        end + [
          {"id" => "internet", "label" => "Internet", "role" => "Package sources · recursive DNS roots", "address" => "WAN", "status" => "external"}
        ],
        "edges" => [
          {"from" => "maven", "to" => proxmox_id, "label" => "SSH maintenance", "kind" => "management"},
          {"from" => proxmox_id, "to" => "pihole", "label" => "hosts LXC 100", "kind" => "containment"},
          {"from" => "maven", "to" => "pihole", "label" => "primary DNS", "kind" => "dns"},
          {"from" => "pihole", "to" => "internet", "label" => "Unbound recursion · Quad9 fallback", "kind" => "upstream"},
          {"from" => "maven", "to" => proxmox_id, "label" => "second-copy target · planned", "kind" => "backup_planned"}
        ]
      }
    end

    def device(id:, label:, role:, address:, reachable:, os:, version:, kernel:, updates:, reboot:, services:, facts:)
      service_attention = services.any? { |service| service["state"] != "active" }
      status = if !reachable
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

    def offline_device(id, label, role, address, result)
      {
        "id" => id,
        "label" => label,
        "role" => role,
        "address" => address,
        "status" => "offline",
        "reachable" => false,
        "os" => "unavailable",
        "version" => "unavailable",
        "kernel" => {"running" => "unavailable", "available" => "unavailable", "update_required" => false},
        "updates" => update_summary(freshness: "unavailable"),
        "reboot" => {"required" => false, "reason" => "unavailable while device is offline"},
        "services" => [],
        "facts" => {"connection_status" => result.status}
      }
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
