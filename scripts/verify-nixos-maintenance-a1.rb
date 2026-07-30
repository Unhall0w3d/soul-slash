#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_device_control_service"
require_relative "../lib/soul_core/maintenance_fleet_discovery_service"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def result(stdout = "", stderr = "", exit_status = 0, status = "ok")
  SoulCore::BoundedCommandRunner::Result.new(
    stdout: stdout, stderr: stderr, exit_status: exit_status,
    status: status, truncated: false
  )
end

class NixosFleetStub
  attr_reader :collect_count

  def initialize
    @collect_count = 0
  end

  def collect
    @collect_count += 1
    {"ok" => true, "data" => {"devices" => []}}
  end

  def snapshot
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "devices" => [{
          "control" => "maintenance",
          "facts" => {
            "control_target_id" => "temper",
            "mutation_supported" => true,
            "status_adapter" => "nixos_flake_fixed_maintenance"
          }
        }]
      }
    }
  end
end

class NixosRunner
  attr_reader :calls

  LOCKED = "1" * 40
  UPSTREAM = "2" * 40

  def initialize
    @calls = []
    @boot_reads = 0
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return result("host 192.168.50.80\nhostname 192.168.50.80\nuser soul-maintenance\n") if argv.include?("-G")

    target_index = argv.index("temper")
    return result("", "unexpected target", 127, "failed") unless target_index

    remote = argv[(target_index + 1)..]
    case remote
    when ["/run/current-system/sw/bin/hostname"] then result("temper\n")
    when ["/run/current-system/sw/bin/uname", "-r"] then result("6.18.40\n")
    when ["/run/current-system/sw/bin/cat", "/etc/os-release"] then result("PRETTY_NAME=\"NixOS 26.05 (Yarara)\"\nID=nixos\n")
    when ["/run/current-system/sw/bin/test", "-x", "/run/current-system/sw/bin/test"] then result
    when ["/run/current-system/sw/bin/nixos-version"] then result("26.05.fixture (Yarara)\n")
    when ["/run/current-system/sw/bin/readlink", "-f", "/run/current-system"] then result("/nix/store/current-system\n")
    when ["/run/current-system/sw/bin/readlink", "-f", "/run/booted-system"] then result("/nix/store/booted-system\n")
    when ["/run/current-system/sw/bin/cat", "/proc/sys/kernel/random/boot_id"]
      @boot_reads += 1
      result(@boot_reads == 1 ? "old-boot\n" : "new-boot\n")
    when ["/run/current-system/sw/bin/cat", "/etc/nixos/flake.lock"]
      result(JSON.generate("nodes" => {"nixpkgs" => {"locked" => {"rev" => LOCKED}}}))
    when ["/run/current-system/sw/bin/git", "ls-remote", "https://github.com/NixOS/nixpkgs.git", "refs/heads/nixos-26.05"]
      result("#{UPSTREAM}\trefs/heads/nixos-26.05\n")
    when ["/run/current-system/sw/bin/systemctl", "is-active", "sshd"],
         ["/run/current-system/sw/bin/systemctl", "is-active", "qemu-guest-agent"]
      result("active\n")
    when ["/run/current-system/sw/bin/systemctl", "is-active", "sshd", "qemu-guest-agent"]
      result("active\nactive\n")
    when ["/run/current-system/sw/bin/sudo", "-n", "/run/current-system/sw/bin/soul-nixos-maintenance", "self-check"]
      result("{\"version\":\"soul-nixos-maintenance-a1-v1\",\"flake\":\"/etc/nixos#temper\",\"arbitrary_command_forwarding\":false,\"password_storage\":false}\n")
    when ["/run/current-system/sw/bin/sudo", "-n", "/run/current-system/sw/bin/soul-nixos-maintenance", "generation-match"]
      result("matched\n")
    when ["/run/current-system/sw/bin/sudo", "-n", "/run/current-system/sw/bin/soul-nixos-maintenance", "upgrade"]
      result("upgrade complete\n")
    when ["/run/current-system/sw/bin/sudo", "-n", "/run/current-system/sw/bin/soul-nixos-maintenance", "reboot"]
      result("", "", 255, "failed")
    else
      if remote.length == 3 && remote[0, 2] == ["/run/current-system/sw/bin/test", "-x"]
        return result if [
          "/run/current-system/sw/bin/nix",
          "/run/current-system/sw/bin/git"
        ].include?(remote.last)
        return result("", "", 1, "failed")
      end
      result("", "unexpected command", 127, "failed")
    end
  end
end

puts "NixOS maintenance A1 verification:"

Dir.mktmpdir("soul-nixos-a1-") do |root|
  ssh_config = File.join(root, "ssh_config")
  File.write(ssh_config, "Host temper\n  HostName 192.168.50.80\n  User soul-maintenance\n")
  File.chmod(0o600, ssh_config)
  runner = NixosRunner.new

  discovery = SoulCore::MaintenanceFleetDiscoveryService.new(
    root: root,
    runner: runner,
    ssh_config: ssh_config,
    ssh_path: "/usr/bin/ssh"
  )
  resolved = discovery.send(:resolved_ssh_hostname, "temper")
  check.call("fixture SSH alias resolves to the selected address", resolved == "192.168.50.80")
  facts = discovery.send(:fingerprint_ssh, "192.168.50.80", "temper")
  check.call("NixOS immutable command paths enroll through the ordinary SSH inventory flow",
             facts["hostname"] == "temper" &&
               facts["os_id"] == "nixos" &&
               facts["package_managers"].include?("nix"))

  fleet = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    ssh_config: ssh_config,
    process_env: {
      "SOUL_FLEET_TEMPER_CONTROL_ENABLED" => "true",
      "SOUL_FLEET_TEMPER_SSH_ALIAS" => "temper"
    }
  )
  device = fleet.send(
    :collect_nixos_inventory_device,
    {
      "id" => "managed_temper",
      "label" => "Temper",
      "role" => "NixOS maintenance laboratory",
      "address" => "192.168.50.80",
      "ssh_alias" => "temper"
    },
    {
      "os_pretty_name" => "NixOS 26.05 (Yarara)",
      "kernel" => "6.18.40",
      "enrollment_id" => "managed_temper"
    },
    ["nix"]
  )
  check.call("live Nix branch evidence produces one native Nix update channel",
             device.dig("updates", "native") == 1 &&
               device.dig("updates", "channels", 0, "label") == "Nix" &&
               device.dig("updates", "channels", 0, "manager") == "nix" &&
               device.dig("updates", "freshness") == "live_nixpkgs_branch")
  check.call("generation mismatch is the bounded NixOS reboot signal",
             device.dig("reboot", "required") == true &&
               device.dig("reboot", "reason").include?("differs"))
  check.call("exact authority self-check plus the local switch enables Temper maintenance",
             device["control"] == "maintenance" &&
               device.dig("facts", "control_target_id") == "temper" &&
               device.dig("facts", "status_adapter") == "nixos_flake_fixed_maintenance" &&
               device.dig("facts", "maintenance_adapter") == "nixos_flake")
  disabled_fleet = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    ssh_config: ssh_config,
    process_env: {}
  )
  disabled_device = disabled_fleet.send(
    :collect_nixos_inventory_device,
    {
      "id" => "managed_temper",
      "label" => "Temper",
      "role" => "NixOS maintenance laboratory",
      "address" => "192.168.50.80",
      "ssh_alias" => "temper"
    },
    {
      "os_pretty_name" => "NixOS 26.05 (Yarara)",
      "kernel" => "6.18.40",
      "enrollment_id" => "managed_temper"
    },
    ["nix"]
  )
  check.call("a valid helper remains inventory-only while the local Temper authority switch is disabled",
             disabled_device["control"] == "inventory_only" &&
               disabled_device.dig("facts", "mutation_supported") == false &&
               disabled_device.dig("facts", "status_adapter") == "nixos_flake_read_only")

  fleet_stub = NixosFleetStub.new
  control = SoulCore::MaintenanceDeviceControlService.new(
    root: root,
    fleet_status_service: fleet_stub,
    runner: runner,
    clock: -> { Time.utc(2026, 7, 30, 12, 0, 0) },
    sleeper: ->(_seconds) {},
    live_execution_enabled: true,
    ssh_config: ssh_config,
    process_env: {
      "SOUL_FLEET_TEMPER_CONTROL_ENABLED" => "true",
      "SOUL_FLEET_TEMPER_SSH_ALIAS" => "temper",
      "SOUL_FLEET_TEMPER_ADDRESS" => "192.168.50.80",
      "SOUL_FLEET_TEMPER_LABEL" => "Temper"
    }
  )
  preview = control.preview(device_id: "temper", action: "maintenance")
  reboot_preview = control.preview(device_id: "temper", action: "reboot")
  check.call("Temper preview binds one fixed flake upgrade and exact confirmation",
             preview.dig("data", "confirmation") == "MAINTAIN_TEMPER" &&
               preview.dig("data", "plan", "maintenance_adapter") == "nixos_flake" &&
               preview.dig("data", "plan", "commands") == [{
               "argv" => ["/run/current-system/sw/bin/sudo", "-n", "/run/current-system/sw/bin/soul-nixos-maintenance", "upgrade"]
               }])
  check.call("Temper reboot preview binds its immutable boot identity and three readiness checks",
             reboot_preview.dig("data", "plan", "boot_identity", "argv") == [
               "/run/current-system/sw/bin/cat", "/proc/sys/kernel/random/boot_id"
             ] &&
               reboot_preview.dig("data", "plan", "readiness").length == 3)
  stale = control.execute(
    device_id: "temper",
    action: "maintenance",
    confirmation: "MAINTAIN_TEMPER",
    expected_digest: "0" * 64
  )
  calls_before = runner.calls.length
  check.call("stale Temper evidence executes no maintenance command",
             stale["lifecycle_state"] == "blocked_for_human_review")
  completed = control.execute(
    device_id: "temper",
    action: "maintenance",
    confirmation: preview.dig("data", "confirmation"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  maintenance_calls = runner.calls.drop(calls_before).count do |call|
    call.fetch("argv").last(4) == [
      "/run/current-system/sw/bin/sudo", "-n",
      "/run/current-system/sw/bin/soul-nixos-maintenance", "upgrade"
    ]
  end
  check.call("authorized Temper maintenance terminates after one fixed helper call",
             completed["lifecycle_state"] == "complete" &&
               maintenance_calls == 1 &&
               fleet_stub.collect_count == 1)
  rebooted = control.execute(
    device_id: "temper",
    action: "reboot",
    confirmation: reboot_preview.dig("data", "confirmation"),
    expected_digest: reboot_preview.dig("data", "expected_digest")
  )
  check.call("Temper reboot sends one request and verifies new identity plus all readiness checks",
             rebooted["lifecycle_state"] == "complete" &&
               rebooted.dig("data", "receipt", "reboot_request_count") == 1 &&
               fleet_stub.collect_count == 2)
end

module_text = File.read(File.expand_path("../deploy/nixos/temper/soul-maintenance.nix", __dir__))
helper_text = File.read(File.expand_path("../deploy/nixos/temper/soul-nixos-maintenance", __dir__))
check.call("declarative authority exposes four literal operations without command forwarding",
           %w[self-check generation-match upgrade reboot].all? { |operation| module_text.include?(operation) } &&
             !helper_text.include?('"$@"') &&
             !helper_text.match?(/\beval\b/) &&
             helper_text.include?('nixos-rebuild switch --flake "$FLAKE"'))
check.call("failed upgrade restores the reviewed flake lock",
           helper_text.include?("trap restore ERR INT TERM") &&
             helper_text.include?('cp -- "$backup" "$LOCK"'))

if errors.empty?
  puts "NixOS maintenance A1 verification passed."
  exit 0
end

warn "NixOS maintenance A1 verification failed: #{errors.join(', ')}"
exit 1
