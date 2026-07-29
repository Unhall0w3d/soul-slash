#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/crucible_maintenance_authority"
require_relative "../lib/soul_core/maintenance_device_control_service"
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

class D1AuthorityRunner
  attr_reader :calls

  def initialize(ready: true, broad: false)
    @ready = ready
    @broad = broad
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    if argv.include?("/usr/bin/scp")
      return result
    end
    remote = argv.drop_while { |part| part != "crucible-maintenance" }.drop(1)
    return result unless remote.first == "/usr/bin/sudo" || remote.first == "/usr/bin/rm"
    return result("{\"version\":\"soul-crucible-maintenance-d1-v1\",\"arbitrary_command_forwarding\":false,\"password_storage\":false}\n") if remote.last(2) == ["/usr/local/libexec/soul-crucible-maintenance", "self-check"] && @ready
    return result("", "", 1, "failed") if remote.last(2) == ["/usr/local/libexec/soul-crucible-maintenance", "self-check"]
    return @broad ? result : result("", "", 1, "failed") if remote.last(3) == ["/usr/bin/test", "-e", "/etc/sudoers.d/90-cloud-init-users"]

    result
  end
end

class D1FleetStub
  attr_reader :collect_count

  def initialize
    @collect_count = 0
  end

  def collect
    @collect_count += 1
    {"ok" => true, "data" => {"devices" => []}}
  end

  def snapshot
    {"ok" => true, "data" => {"devices" => []}}
  end
end

class D1ControlRunner
  attr_reader :calls

  def initialize
    @calls = []
    @boot_reads = 0
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    remote = argv.drop_while { |part| part != "crucible-maintenance" }.drop(1)
    case remote
    when ["/usr/bin/cat", "/proc/sys/kernel/random/boot_id"]
      @boot_reads += 1
      result(@boot_reads == 1 ? "old\n" : "new\n")
    when ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "reboot"]
      result("", "", 255, "failed")
    when ["/usr/bin/systemctl", "is-active", "sshd", "qemu-guest-agent"]
      result("active\nactive\n")
    when ["/usr/bin/dnf5", "--version"]
      result("dnf5 version 5.4.1.0\n")
    when ["/usr/bin/findmnt", "--noheadings", "--output", "TARGET", "/srv/soul-backup"]
      result("/srv/soul-backup\n")
    when ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "self-check"]
      result("{\"version\":\"soul-crucible-maintenance-d1-v1\"}\n")
    else
      result
    end
  end
end

puts "Crucible maintenance control D1 verification:"

Dir.mktmpdir("soul-crucible-d1-") do |root|
  ssh_config = File.join(root, "ssh_config")
  File.write(ssh_config, "Host crucible-maintenance\n  HostName 192.0.2.44\n")
  authority_runner = D1AuthorityRunner.new
  authority = SoulCore::CrucibleMaintenanceAuthority.new(
    root: File.expand_path("..", __dir__),
    runner: authority_runner,
    ssh_config: ssh_config,
    id_generator: -> { "0123456789abcdef" }
  )
  plan = authority.plan.fetch("data")
  helper = plan.fetch("helper_content")
  sudoers = plan.fetch("sudoers_content")
  check.call("helper exposes only three fixed operations without command forwarding",
             plan.fetch("allowed_operations") == %w[self-check dnf5-upgrade reboot] &&
               helper.include?("exec /usr/bin/dnf5 -y upgrade --refresh") &&
               helper.include?("exec /usr/bin/systemctl reboot") &&
               !helper.include?('"$@"') && !helper.match?(/\beval\b/))
  check.call("sudoers pins the exact helper digest and contains no broad authority",
             sudoers.scan("sha256:#{plan.fetch('helper_sha256')}").length == 3 &&
               !sudoers.include?("ALL=(ALL) NOPASSWD:ALL") &&
               !sudoers.include?("/usr/bin/dnf5"))
  rejected = authority.install(expected_digest: "0" * 64, confirmation: SoulCore::CrucibleMaintenanceAuthority::CONFIRM_INSTALL)
  check.call("wrong install digest causes no remote call",
             rejected["lifecycle_state"] == "blocked_for_human_review" && authority_runner.calls.empty?)
  status = authority.status
  check.call("authority status requires exact self-check and absence of broad cloud-init sudo",
             status.dig("data", "ready") == true &&
               status.dig("data", "broad_cloud_init_authority_present") == false)

  fleet = D1FleetStub.new
  control_runner = D1ControlRunner.new
  control = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: fleet, runner: control_runner,
    clock: -> { Time.utc(2026, 7, 28, 22, 0, 0) },
    sleeper: ->(_seconds) {}, live_execution_enabled: true,
    ssh_config: ssh_config, id_generator: -> { "fixture" }
  )
  maintenance_preview = control.preview(device_id: "crucible", action: "maintenance")
  reboot_preview = control.preview(device_id: "crucible", action: "reboot")
  check.call("Crucible previews bind exact helper operations and never direct package or reboot commands",
             maintenance_preview.dig("data", "plan", "commands") == [
               {"argv" => ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "dnf5-upgrade"]}
             ] &&
               reboot_preview.dig("data", "plan", "commands") == [
                 {"argv" => ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "reboot"]}
               ] &&
               reboot_preview.dig("data", "plan", "readiness").length == 4)
  stale = control.execute(
    device_id: "crucible", action: "maintenance",
    confirmation: maintenance_preview.dig("data", "confirmation"),
    expected_digest: "f" * 64
  )
  check.call("stale Crucible preview runs no command",
             stale["lifecycle_state"] == "blocked_for_human_review" && control_runner.calls.empty?)
  completed = control.execute(
    device_id: "crucible", action: "maintenance",
    confirmation: maintenance_preview.dig("data", "confirmation"),
    expected_digest: maintenance_preview.dig("data", "expected_digest")
  )
  check.call("Crucible maintenance is one bounded helper call with no reboot",
             completed["lifecycle_state"] == "complete" &&
               control_runner.calls.length == 1 &&
               control_runner.calls.first.fetch("argv").last(4) == [
                 "/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "dnf5-upgrade"
               ] &&
               fleet.collect_count == 1)

  fedora_runner = Object.new
  fedora_calls = []
  fedora_runner.define_singleton_method(:run) do |*command, **options|
    argv = command.flatten.map(&:to_s)
    fedora_calls << {"argv" => argv, "options" => options}
    remote = argv.drop_while { |part| part != "crucible-maintenance" }.drop(1)
    case remote
    when ["/usr/bin/dnf5", "--quiet", "check-upgrade"] then result("pkg.x86_64 2.0 updates\n", "", 100, "failed")
    when ["/usr/bin/dnf5", "needs-restarting", "--json"] then result("[]\n")
    when ["/usr/bin/rpm", "-q", "kernel-core"] then result("kernel-core-1.0\n")
    when ["/usr/bin/systemctl", "is-active", "sshd"], ["/usr/bin/systemctl", "is-active", "qemu-guest-agent"] then result("active\n")
    when ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "self-check"]
      result("{\"version\":\"soul-crucible-maintenance-d1-v1\",\"arbitrary_command_forwarding\":false,\"password_storage\":false}\n")
    else result("", "unexpected", 127, "failed")
    end
  end
  fleet_service = SoulCore::MaintenanceFleetStatusService.new(runner: fedora_runner, ssh_config: ssh_config)
  device = fleet_service.send(
    :collect_fedora_inventory_device,
    {"id" => "managed_fixture", "label" => "Crucible", "role" => "Backup target", "address" => "192.0.2.44", "ssh_alias" => "crucible-maintenance"},
    {"os_pretty_name" => "Fedora Linux", "kernel" => "1.0", "enrollment_id" => "managed_fixture"},
    ["dnf"]
  )
  check.call("fleet evidence exposes Crucible controls only after exact authority self-check",
             device["control"] == "maintenance" &&
               device.dig("facts", "control_target_id") == "crucible" &&
               device.dig("facts", "mutation_supported") == true &&
               device.dig("facts", "status_adapter") == "dnf5_fixed_maintenance" &&
               device.dig("facts", "control_capability") == "fixed_maintenance" &&
               device.dig("facts", "maintenance_authority") == "root_owned_fixed_operations")
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
stylesheet = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
check.call("dashboard uses separate integrated and network-presence surfaces",
           html.include?('id="maintenance-managed-device-grid"') &&
             html.include?('id="maintenance-status-device-grid"') &&
             javascript.include?("const managedDevices = (data.devices || []).filter") &&
             javascript.include?("const statusDevices = (data.devices || []).filter(maintenanceDeviceIsStatusOnly)") &&
             stylesheet.include?(".maintenance-device-surfaces"))
check.call("Crucible card routes lifecycle controls through its reviewed target while refresh keeps enrollment identity",
           javascript.include?("const controlDeviceId = device.facts?.control_target_id || device.id") &&
             javascript.include?("openMaintenanceDeviceAction(controlDeviceId, action)") &&
             javascript.include?("refreshMaintenanceDevice(device.id, refresh)"))

if errors.empty?
  puts "Crucible maintenance control D1 verification passed."
  exit 0
end

warn "Crucible maintenance control D1 verification failed: #{errors.join(', ')}"
exit 1
