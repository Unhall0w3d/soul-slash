#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_device_control_service"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def result(stdout = "", exit_status = 0, status = "ok")
  SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: exit_status, status: status, truncated: false)
end

class DebianAptRunner
  attr_reader :calls

  def initialize(authority_ready: true)
    @authority_ready = authority_ready
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    target = argv.index("debian-fixture")
    return result("", 127, "failed") unless target

    remote = argv[(target + 1)..]
    case remote
    when ["/usr/bin/apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade"]
      result("0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.\n")
    when ["/usr/bin/uname", "-r"]
      result("6.12.0-amd64\n")
    when ["/usr/bin/test", "-e", "/var/run/reboot-required"]
      result("", 1, "failed")
    when ["/usr/bin/systemctl", "is-active", "ssh"]
      result("active\n")
    when ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-debian-apt-maintenance", "self-check"]
      @authority_ready ? result("{\"version\":\"soul-debian-apt-maintenance-a1-v1\",\"arbitrary_command_forwarding\":false,\"password_storage\":false}\n") : result("", 1, "failed")
    else
      result("", 127, "failed")
    end
  end
end

class DebianFleetStub
  def initialize(device)
    @device = device
  end

  def snapshot
    {"ok" => true, "lifecycle_state" => "complete", "data" => {"devices" => [@device]}}
  end
end

record = {
  "id" => "managed_fixture", "label" => "Debian Fixture", "role" => "Service host",
  "address" => "192.0.2.15", "connection_mode" => "ssh", "ssh_alias" => "debian-fixture",
  "address_policy" => "fixed", "facts" => {}
}
facts = {"os_id" => "debian", "os_pretty_name" => "Debian GNU/Linux 13", "kernel" => "6.12.0-amd64", "package_managers" => ["apt"]}

Dir.mktmpdir("soul-debian-apt-a1") do |root|
  runner = DebianAptRunner.new
  status = SoulCore::MaintenanceFleetStatusService.new(
    root: root, runner: runner, ssh_config: File.join(root, "ssh_config"),
    process_env: {"SOUL_FLEET_DEBIAN_APT_CONTROL_ALIASES" => "debian-fixture"}
  )
  device = status.send(:collect_debian_apt_inventory_device, record, facts, ["apt"])
  check.call("qualified Debian evidence promotes the enrolled private ID to fixed maintenance",
             device["control"] == "maintenance" &&
               device.dig("facts", "control_target_id") == "managed_fixture" &&
               device.dig("facts", "ssh_alias") == "debian-fixture")

  control = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: DebianFleetStub.new(device), runner: runner,
    live_execution_enabled: false, ssh_config: File.join(root, "ssh_config"),
    process_env: {"SOUL_FLEET_DEBIAN_APT_CONTROL_ALIASES" => "debian-fixture"}
  )
  preview = control.preview(device_id: "managed_fixture", action: "maintenance")
  check.call("dynamic control preview retains the private card identity and exact helper vector",
             preview["ok"] &&
               preview.dig("data", "plan", "device_label") == "Debian Fixture" &&
               preview.dig("data", "plan", "commands", 0, "argv") == ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-debian-apt-maintenance", "apt-upgrade"])

  bad = Marshal.load(Marshal.dump(device))
  bad["facts"]["mutation_supported"] = false
  rejected = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: DebianFleetStub.new(bad), runner: runner,
    live_execution_enabled: false, ssh_config: File.join(root, "ssh_config"),
    process_env: {"SOUL_FLEET_DEBIAN_APT_CONTROL_ALIASES" => "debian-fixture"}
  ).preview(device_id: "managed_fixture", action: "maintenance")
  check.call("stale or downgraded evidence blocks dynamic control", rejected["lifecycle_state"] == "awaiting_input")

  disabled = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: DebianFleetStub.new(device), runner: runner,
    live_execution_enabled: false, ssh_config: File.join(root, "ssh_config"), process_env: {}
  ).preview(device_id: "managed_fixture", action: "maintenance")
  check.call("persisted evidence cannot bypass removal of the owner-local alias allowlist", disabled["lifecycle_state"] == "awaiting_input")
end

helper = File.read(File.expand_path("../deploy/maintenance/debian-apt/soul-debian-apt-maintenance", __dir__))
installer = File.read(File.expand_path("../deploy/maintenance/debian-apt/install-authority.sh", __dir__))
check.call("helper exposes only the three reviewed operation names", helper.scan(/^  (self-check|apt-upgrade|reboot)\)$/).flatten.sort == %w[apt-upgrade reboot self-check])
check.call("installer binds each exact helper operation by SHA-256", installer.include?("sha256:") && installer.include?("visudo -cf"))
check.call("public artifacts do not contain an owner-specific endpoint", ![helper, installer].join.include?("observatory"))

abort "Generic Debian APT Maintenance A1 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Generic Debian APT Maintenance A1 verification passed."
