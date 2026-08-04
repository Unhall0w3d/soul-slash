#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/witness_maintenance_authority"
require_relative "../lib/soul_core/maintenance_device_control_service"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def result(stdout = "", stderr = "", exit_status = 0, status = "ok")
  SoulCore::BoundedCommandRunner::Result.new(
    stdout: stdout,
    stderr: stderr,
    exit_status: exit_status,
    status: status,
    truncated: false
  )
end

class WitnessAuthorityRunner
  attr_reader :calls

  def initialize(ready: true, broad: false)
    @ready = ready
    @broad = broad
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return result if argv.include?("/usr/bin/scp")

    remote = argv.drop_while { |part| part != "witness" }.drop(1)
    return result unless remote.first == "/usr/bin/sudo" || remote.first == "/usr/bin/rm" || remote.first == "/usr/bin/install" || remote.first == "/usr/sbin/visudo"

    if remote.last(2) == [SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "self-check"]
      return @ready ? result(
        "{\"version\":\"#{SoulCore::WitnessMaintenanceAuthority::VERSION}\"," \
          "\"arbitrary_command_forwarding\":false,\"password_storage\":false,\"broad_cloud_init_authority_present\":#{@broad}\n" \
          "}\n"
      ) : result("", "", 1, "failed")
    end

    return result("", "", 1, "failed") if remote == ["/usr/bin/sudo", "-n", "/usr/bin/id"]

    result
  end
end

class WitnessControlRunner
  attr_reader :calls

  def initialize
    @calls = []
    @boot_reads = 0
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    remote = argv.drop_while { |part| part != "witness" }.drop(1)
    case remote
    when ["/usr/bin/cat", "/proc/sys/kernel/random/boot_id"]
      @boot_reads += 1
      result(@boot_reads == 1 ? "old\n" : "new\n")
    when ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "apt-upgrade"]
      result("", "", 0, "ok")
    when ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "reboot"]
      result("", "", 255, "ok")
    when ["/usr/bin/systemctl", "is-active", "ssh", "wazuh-agent"]
      result("active\nactive\n")
    when ["/usr/bin/apt-get", "--version"]
      result("apt 2.8.4\n")
    when ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "self-check"]
      result("{\"version\":\"#{SoulCore::WitnessMaintenanceAuthority::VERSION}\",\"arbitrary_command_forwarding\":false,\"password_storage\":false,\"broad_cloud_init_authority_present\":false}\n")
    else
      result("unexpected witness command", "", 127, "failed")
    end
  end
end

class WitnessFleetStub
  attr_reader :collect_count

  def initialize(control)
    @control = control
    @collect_count = 0
  end

  def collect
    @collect_count += 1
    snapshot
  end

  def snapshot
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "devices" => @control ? [
          {
            "address" => "192.0.2.20",
            "control" => "maintenance",
            "facts" => {
              "control_target_id" => "witness",
              "mutation_supported" => true,
              "status_adapter" => "debian_apt_fixed_maintenance"
            }
          }
        ] : []
      }
    }
  end
end

class WitnessStatusRunner
  attr_reader :calls

  def initialize(authority_ready: true)
    @authority_ready = authority_ready
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    target_index = argv.index("witness")
    return result("", "fixture unavailable", 127, "failed") unless target_index

    remote = argv[(target_index + 1)..]
    case remote
    when ["/usr/bin/hostname"], ["/bin/hostname"]
      result("witness\n")
    when ["/usr/bin/uname", "-r"]
      result("6.18.34+rpt-rpi-v8\n")
    when ["/usr/bin/test", "-e", "/var/run/reboot-required"]
      result("", "", 1, "failed")
    when ["/usr/bin/systemctl", "is-active", "ssh"], ["/usr/bin/systemctl", "is-active", "wazuh-agent"]
      result("active\n")
    when ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "self-check"]
      return result("", "", 1, "failed") unless @authority_ready

      result("{\"version\":\"#{SoulCore::WitnessMaintenanceAuthority::VERSION}\",\"arbitrary_command_forwarding\":false,\"password_storage\":false,\"broad_cloud_init_authority_present\":false}\n")
    else
      if remote == ["/usr/bin/apt-get", "-s", "-o", "Debug::NoLocking=1", "dist-upgrade"]
        result("Inst openssh-server [1] (2 fixture)\nInst linux-image-rpi-v8 [1:6.18.34-1] (1:6.18.39-1 fixture)\n2 upgraded, 0 newly installed\n")
      else
        result("", "fixture unavailable", 127, "failed")
      end
    end
  end
end

puts "Witness maintenance control A1 verification:"

Dir.mktmpdir("soul-witness-a1-") do |root|
  ssh_config = File.join(root, "ssh_config")
  File.write(ssh_config, "Host witness\n  HostName 192.0.2.20\n")

  authority_runner = WitnessAuthorityRunner.new
  authority = SoulCore::WitnessMaintenanceAuthority.new(
    root: File.expand_path("..", __dir__),
    runner: authority_runner,
    ssh_config: ssh_config,
    id_generator: -> { "0123456789abcdef" }
  )
  plan = authority.plan.fetch("data")
  commands = plan.fetch("allowed_operations")
  expected_sudoers = commands.map do |operation|
    "sha256:#{plan.fetch("helper_sha256")} #{SoulCore::WitnessMaintenanceAuthority::HELPER_PATH} #{operation}"
  end
  check.call("authority plan pins the exact helper digest for fixed maintenance operations",
    plan.fetch("operation") == "witness_maintenance_authority_install" &&
      commands == %w[self-check apt-upgrade reboot] &&
      expected_sudoers.all? { |entry| plan.fetch("sudoers_content").include?(entry) } &&
      plan.fetch("sudoers_content").scan("sha256:#{plan.fetch("helper_sha256")} #{SoulCore::WitnessMaintenanceAuthority::HELPER_PATH}").length == 3
  )

  authority_status = authority.status
  check.call("authority self-check proves no broad cloud-init sudoers entry",
    authority_status.fetch("ok") == true &&
      authority_status.dig("data", "ready") == true &&
      authority_status.dig("data", "broad_cloud_init_authority_present") == false
  )

  before_digest = authority_runner.calls.length
  wrong_digest = authority.install(
    expected_digest: "0" * 64,
    confirmation: SoulCore::WitnessMaintenanceAuthority::CONFIRM_INSTALL
  )
  check.call("wrong digest blocks install without remote execution",
    wrong_digest.fetch("lifecycle_state") == "blocked_for_human_review" && authority_runner.calls.length == before_digest
  )

  before_confirmation = authority_runner.calls.length
  wrong_confirmation = authority.install(
    expected_digest: plan.fetch("expected_digest"),
    confirmation: "NOPE"
  )
  check.call("wrong confirmation blocks install without remote execution",
    wrong_confirmation.fetch("lifecycle_state") == "awaiting_input" && authority_runner.calls.length == before_confirmation
  )

  complete = authority.install(
    expected_digest: plan.fetch("expected_digest"),
    confirmation: SoulCore::WitnessMaintenanceAuthority::CONFIRM_INSTALL
  )
  check.call("install succeeds and keeps cloud-init sudoers removal after helper activation and self-check",
    complete.fetch("lifecycle_state") == "complete" &&
      complete.fetch("data", {}).fetch("ready") == true &&
      (helper_install = authority_runner.calls.index do |call|
        call.fetch("argv").include?("/usr/bin/install") &&
          call.fetch("argv").include?(SoulCore::WitnessMaintenanceAuthority::HELPER_PATH)
      end) &&
      (sudoers_stage = authority_runner.calls.index do |call|
        call.fetch("argv").include?("/usr/bin/install") && call.fetch("argv").any? { |argv| argv.end_with?(".new") }
      end) &&
      (visudo_check = authority_runner.calls.index { |call| call.fetch("argv").include?("/usr/sbin/visudo") }) &&
      (self_check = authority_runner.calls.index do |call|
        argv = call.fetch("argv").drop_while { |part| part != "witness" }.drop(1)
        argv == ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "self-check"]
      end) &&
      (remove_cloud = authority_runner.calls.index do |call|
        call.fetch("argv").include?(SoulCore::WitnessMaintenanceAuthority::CLOUD_INIT_SUDOERS_PATH)
      end) &&
      remove_cloud > helper_install &&
      remove_cloud > sudoers_stage &&
      remove_cloud > visudo_check &&
      remove_cloud > self_check
  )

  fleet_root = File.join(root, "fleet-root")
  registry_directory = File.join(fleet_root, "Soul", "private", "host_maintenance")
  FileUtils.mkdir_p(registry_directory, mode: 0o700)
  registry_path = File.join(registry_directory, "discovered_devices.json")
  File.write(registry_path, JSON.pretty_generate({
    "schema_version" => "soul.maintenance.fleet_registry.v1",
    "devices" => [{
      "id" => "managed_acd26dbd223d819d",
      "label" => "Witness",
      "role" => "Passive security telemetry · Raspberry Pi",
      "address" => "192.0.2.20",
      "connection_mode" => "ssh",
      "ssh_alias" => "witness",
      "control" => "inventory_only",
      "facts" => {
        "platform" => "linux",
        "os_id" => "debian",
        "os_pretty_name" => "Debian GNU/Linux 13 (trixie)",
        "kernel" => "6.18.34+rpt-rpi-v8",
        "package_managers" => ["apt", "apt-get"]
      }
    }]
  }))
  File.chmod(0o600, registry_path)
  status_runner = WitnessStatusRunner.new
  managed_witness = SoulCore::MaintenanceFleetStatusService.new(
    root: fleet_root,
    runner: status_runner,
    ssh_config: ssh_config,
    process_env: {
      "SOUL_FLEET_WITNESS_CONTROL_ENABLED" => "true",
      "SOUL_FLEET_WITNESS_SSH_ALIAS" => "witness",
      "SOUL_FLEET_WITNESS_ADDRESS" => "192.0.2.20"
    }
  ).collect.dig("data", "devices").find { |device| device["id"] == "managed_acd26dbd223d819d" }
  check.call("exact Witness enrollment and authority produce managed APT evidence",
    managed_witness["control"] == "maintenance" &&
      managed_witness["role"] == "Passive security telemetry · Raspberry Pi" &&
      managed_witness.dig("updates", "channels") == [{
        "id" => "native", "label" => "APT", "manager" => "apt", "status" => "complete", "count" => 2
      }] &&
      managed_witness.dig("kernel", "available") == "linux-image-rpi-v8 1:6.18.39-1" &&
      managed_witness.dig("kernel", "update_required") == true &&
      managed_witness.dig("facts", "control_target_id") == "witness" &&
      managed_witness.dig("facts", "status_adapter") == "debian_apt_fixed_maintenance" &&
      managed_witness.dig("facts", "mutation_supported") == true &&
      managed_witness.fetch("services").any? { |service| service["label"] == "Wazuh agent" && service["state"] == "active" }
  )

  mismatched_witness = SoulCore::MaintenanceFleetStatusService.new(
    root: fleet_root,
    runner: WitnessStatusRunner.new,
    ssh_config: ssh_config,
    process_env: {
      "SOUL_FLEET_WITNESS_CONTROL_ENABLED" => "true",
      "SOUL_FLEET_WITNESS_SSH_ALIAS" => "witness",
      "SOUL_FLEET_WITNESS_ADDRESS" => "192.0.2.21"
    }
  ).collect.dig("data", "devices").find { |device| device["id"] == "managed_acd26dbd223d819d" }
  check.call("a mismatched Witness address remains inventory only",
    mismatched_witness["control"] == "inventory_only" &&
      mismatched_witness.dig("facts", "mutation_supported") == false
  )

  no_authority_control = SoulCore::MaintenanceDeviceControlService.new(
    root: root,
    fleet_status_service: WitnessFleetStub.new(false),
    runner: WitnessControlRunner.new,
    clock: -> { Time.utc(2026, 8, 1, 12, 0, 0) },
    sleeper: ->(_seconds) {},
    live_execution_enabled: true,
    ssh_config: ssh_config,
    process_env: {}
  )
  disabled = no_authority_control.preview(device_id: "witness", action: "maintenance")
  check.call("disabled witness env blocks maintenance control", disabled.fetch("lifecycle_state") == "awaiting_input")

  absent_fleet = SoulCore::MaintenanceDeviceControlService.new(
    root: root,
    fleet_status_service: WitnessFleetStub.new(false),
    runner: WitnessControlRunner.new,
    clock: -> { Time.utc(2026, 8, 1, 12, 0, 0) },
    sleeper: ->(_seconds) {},
    live_execution_enabled: true,
    ssh_config: ssh_config,
    process_env: {"SOUL_FLEET_WITNESS_CONTROL_ENABLED" => "true", "SOUL_FLEET_WITNESS_SSH_ALIAS" => "witness", "SOUL_FLEET_WITNESS_ADDRESS" => "192.0.2.20"}
  )
  absent = absent_fleet.preview(device_id: "witness", action: "maintenance")
  check.call("missing witness fleet evidence blocks maintenance control", absent.fetch("lifecycle_state") == "awaiting_input")

  stale_address_control = SoulCore::MaintenanceDeviceControlService.new(
    root: root,
    fleet_status_service: WitnessFleetStub.new(true),
    runner: WitnessControlRunner.new,
    clock: -> { Time.utc(2026, 8, 1, 12, 0, 0) },
    sleeper: ->(_seconds) {},
    live_execution_enabled: true,
    ssh_config: ssh_config,
    process_env: {
      "SOUL_FLEET_WITNESS_CONTROL_ENABLED" => "true",
      "SOUL_FLEET_WITNESS_SSH_ALIAS" => "witness",
      "SOUL_FLEET_WITNESS_ADDRESS" => "192.0.2.21"
    }
  )
  stale_address = stale_address_control.preview(device_id: "witness", action: "maintenance")
  check.call("changed Witness address invalidates stale fleet control evidence", stale_address.fetch("lifecycle_state") == "awaiting_input")

  witness_fleet = WitnessFleetStub.new(true)
  witness_runner = WitnessControlRunner.new
  control = SoulCore::MaintenanceDeviceControlService.new(
    root: root,
    fleet_status_service: witness_fleet,
    runner: witness_runner,
    clock: -> { Time.utc(2026, 8, 1, 12, 0, 0) },
    sleeper: ->(_seconds) {},
    live_execution_enabled: true,
    ssh_config: ssh_config,
    process_env: {
      "SOUL_FLEET_WITNESS_CONTROL_ENABLED" => "true",
      "SOUL_FLEET_WITNESS_SSH_ALIAS" => "witness",
      "SOUL_FLEET_WITNESS_ADDRESS" => "192.0.2.20"
    }
  )
  maintenance_preview = control.preview(device_id: "witness", action: "maintenance")
  reboot_preview = control.preview(device_id: "witness", action: "reboot")
  check.call("witness previews lock to helper-only maintenance and reboot vectors",
    maintenance_preview.fetch("ok") == true &&
      maintenance_preview.dig("data", "plan", "commands") == [
        {"argv" => ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "apt-upgrade"]}
      ] &&
      reboot_preview.fetch("ok") == true &&
      reboot_preview.dig("data", "plan", "commands") == [
        {"argv" => ["/usr/bin/sudo", "-n", SoulCore::WitnessMaintenanceAuthority::HELPER_PATH, "reboot"]}
      ]
  )

  stale = control.execute(
    device_id: "witness",
    action: "maintenance",
    confirmation: maintenance_preview.dig("data", "confirmation"),
    expected_digest: "f" * 64
  )
  calls_before = witness_runner.calls.length
  check.call("stale witness preview digest blocks execution", stale.fetch("lifecycle_state") == "blocked_for_human_review")

  maintenance = control.execute(
    device_id: "witness",
    action: "maintenance",
    confirmation: maintenance_preview.dig("data", "confirmation"),
    expected_digest: maintenance_preview.dig("data", "expected_digest")
  )
  maintenance_evidence = maintenance.dig("data", "receipt", "evidence") || []
  check.call("witness maintenance executes one helper command with valid evidence",
    maintenance.fetch("lifecycle_state") == "complete" &&
      maintenance_evidence.any? { |item| item.fetch("adapter") == "maintenance.1" && item.fetch("status") == "ok" } &&
      maintenance_evidence.any? { |item| item.fetch("adapter") == "maintenance.1" && item.fetch("status") == "ok" && item["diagnostic"].nil? } &&
      witness_runner.calls.count { |call| call.fetch("argv").include?(SoulCore::WitnessMaintenanceAuthority::HELPER_PATH) && call.fetch("argv").include?("apt-upgrade") } == 1 &&
      witness_fleet.collect_count >= 1
  )

  witness_runner.calls.slice!(0, calls_before)
  reboot = control.execute(
    device_id: "witness",
    action: "reboot",
    confirmation: reboot_preview.dig("data", "confirmation"),
    expected_digest: reboot_preview.dig("data", "expected_digest")
  )
  reboot_evidence = reboot.dig("data", "receipt", "evidence") || []
  check.call("witness reboot uses fixed helper-only request and readiness evidence",
    reboot.fetch("lifecycle_state") == "complete" &&
      reboot_evidence.any? { |item| item.fetch("adapter") == "reboot.request" && item.fetch("status") == "ok" } &&
      reboot_evidence.any? { |item| item.fetch("adapter").start_with?("reboot.readiness.") && item.fetch("status") == "ok" } &&
      reboot_evidence.any? { |item| item.fetch("adapter") == "reboot.reconnect.1" && item.fetch("status") == "ok" } &&
      reboot.dig("data", "receipt", "reboot_request_count") == 1 &&
      witness_runner.calls.count { |call| call.fetch("argv").include?(SoulCore::WitnessMaintenanceAuthority::HELPER_PATH) && call.fetch("argv").include?("reboot") } == 1 &&
      reboot.dig("data", "receipt", "evidence").length >= 4
  )
end

if errors.empty?
  puts "Witness maintenance control A1 verification passed."
  exit 0
end

warn "Witness maintenance control A1 verification failed: #{errors.join(', ')}"
exit 1
