#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class CrucibleStatusRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    target = argv.index("crucible-maintenance")
    return result("", "unexpected target", 127, "failed") unless target

    remote = argv[(target + 1)..]
    case remote
    when ["/usr/bin/dnf5", "--quiet", "check-upgrade"]
      result(<<~UPDATES, "", 100, "failed")
        Upgrades
        cloud-init.noarch       26.1-1.fc44       updates
        kernel-core.x86_64      7.1.5-200.fc44    updates
      UPDATES
    when ["/usr/bin/dnf5", "needs-restarting", "--json"]
      result("[{\"type\":\"reboot\",\"reboot_required\":false,\"packages\":[]}]\n")
    when ["/usr/bin/rpm", "-q", "kernel-core"]
      result("kernel-core-6.19.10-300.fc44.x86_64\n")
    when ["/usr/bin/uname", "-r"]
      result("6.19.10-300.fc44.x86_64\n")
    when ["/usr/bin/systemctl", "is-active", "sshd"],
         ["/usr/bin/systemctl", "is-active", "qemu-guest-agent"]
      result("active\n")
    when ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-crucible-maintenance", "self-check"]
      result("", "authority unavailable", 1, "failed")
    else
      result("", "unexpected command", 127, "failed")
    end
  end

  private

  def result(stdout, stderr = "", exit_status = 0, status = "ok")
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout,
      stderr: stderr,
      exit_status: exit_status,
      status: status,
      truncated: false
    )
  end
end

puts "Crucible Fedora status A0 verification:"

runner = CrucibleStatusRunner.new
service = SoulCore::MaintenanceFleetStatusService.new(runner: runner)
record = {
  "id" => "managed_0123456789abcdef",
  "label" => "Crucible",
  "role" => "Discovered Linux device · inventory only",
  "address" => "192.0.2.44",
  "ssh_alias" => "crucible-maintenance"
}
facts = {
  "os_id" => "fedora",
  "os_pretty_name" => "Fedora Linux 44 (Cloud Edition)",
  "kernel" => "6.19.10-300.fc44.x86_64",
  "mutation_supported" => false
}
device = service.send(:collect_fedora_inventory_device, record, facts, ["dnf"])

check.call("DNF5 exit 100 is accepted and update rows are counted",
           device.dig("updates", "native") == 2 &&
             device.dig("updates", "freshness") == "live_dnf5_metadata")
check.call("available kernel evidence is distinguished from reboot evidence",
           device.dig("kernel", "running") == "6.19.10-300.fc44.x86_64" &&
             device.dig("kernel", "available") == "7.1.5-200.fc44" &&
             device.dig("kernel", "update_required") == true &&
             device.dig("reboot", "required") == false)
check.call("Crucible remains read-only despite richer status evidence",
           device["control"] == "inventory_only" &&
             device.dig("facts", "status_adapter") == "dnf5_read_only" &&
             device.dig("facts", "mutation_supported") == false)
check.call("SSH and guest-agent readiness are normalized",
           device.fetch("services").map { |row| [row["label"], row["state"]] } == [
             ["DNF5 evidence", "active"],
             ["SSH", "active"],
             ["QEMU guest agent", "active"],
             ["Crucible authority", "unavailable"]
           ])
check.call("all commands are fixed, shell-free, bounded SSH calls",
           runner.calls.length == 7 &&
             runner.calls.all? do |call|
               argv = call.fetch("argv")
               argv.include?("BatchMode=yes") &&
                 argv.include?("ConnectTimeout=5") &&
                 argv.include?("crucible-maintenance") &&
                 !argv.any? { |part| %w[sh bash zsh -c].include?(part) } &&
                 call.dig("options", :timeout_seconds).to_i.between?(1, 120)
             end)

dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
check.call("Dashboard presents live DNF5 evidence without mutation controls",
           dashboard.include?('device.facts?.status_adapter === "dnf5_read_only"') &&
             dashboard.include?("DNF5 evidence only · maintenance and reboot authority remain disabled"))

if errors.empty?
  puts "Crucible Fedora status A0 verification passed."
  exit 0
end

warn "Crucible Fedora status A0 verification failed: #{errors.join(', ')}"
exit 1
