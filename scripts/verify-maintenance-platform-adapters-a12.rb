#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_fleet_status_service"
require_relative "../lib/soul_core/maintenance_platform_adapter_registry"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class OmarchyAdapterFakeRunner
  attr_reader :calls

  def initialize(omarchy_path)
    @omarchy_path = omarchy_path
    @calls = []
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return ok("7.1.9-arch1-2\n") if argv == ["/usr/bin/uname", "-r"]
    return ok("") if argv[0, 3] == ["/usr/bin/fakeroot", "/usr/bin/pacman", "-Sy"]
    return ok("") if argv[0, 2] == ["/usr/bin/pacman", "-Qu"]
    return ok("") if argv == ["/usr/bin/yay", "-Qua"]
    return ok("") if argv.include?("remote-ls")
    return ok("linux 7.1.9-arch1-2\n") if argv == ["/usr/bin/pacman", "-Q", "linux"]
    return ok("Omarchy 4.0.2\n") if argv == [@omarchy_path, "version"]
    return ok("202609010001\n202609020001\n") if argv == [@omarchy_path, "migrate", "--pending"]

    failed("unexpected command: #{argv.join(' ')}")
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false
    )
  end

  def failed(stderr)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: stderr, exit_status: 127, status: "failed", truncated: false
    )
  end
end

puts "Maintenance platform adapter registry A12 verification:"

registry = SoulCore::MaintenancePlatformAdapterRegistry.new
check.call("Omarchy resolves to its Arch-based adapter",
           registry.resolve(os_id: "omarchy").values_at("id", "base_family", "maintenance_adapter") ==
             ["omarchy", "arch", "omarchy_update"])
check.call("CachyOS and Arch retain the generic Arch adapter",
           %w[cachyos arch].all? do |os_id|
             registry.resolve(os_id: os_id).values_at("id", "maintenance_adapter") == ["arch", "arch_pacman"]
           end)
check.call("Proxmox, Debian, Fedora, and NixOS resolve to shared platform adapters",
           registry.resolve(os_id: "debian", platform: "proxmox")["id"] == "proxmox_apt" &&
             registry.resolve(os_id: "debian")["id"] == "debian_apt" &&
             registry.resolve(os_id: "fedora")["id"] == "fedora_dnf5" &&
             registry.resolve(os_id: "nixos")["id"] == "nixos_flake")
check.call("unknown platforms fail closed to inventory-only",
           registry.resolve(os_id: "unrecognized").values_at("id", "maintenance_adapter", "mutation_authorized") ==
             ["inventory_only", nil, false])
check.call("installed Omarchy command uses the fixed package binary rather than a source-tree symlink",
           File.read(File.expand_path("../lib/soul_core/maintenance_fleet_status_service.rb", __dir__))
             .include?('omarchy_path: "/usr/bin/omarchy"'))

Dir.mktmpdir("soul-omarchy-adapter-") do |root|
  os_release = File.join(root, "os-release")
  File.write(os_release, <<~OS_RELEASE)
    NAME="Omarchy"
    PRETTY_NAME="Omarchy 4.0.2"
    ID=omarchy
    ID_LIKE=arch
  OS_RELEASE
  omarchy = File.join(root, "omarchy")
  File.write(omarchy, "#!/bin/sh\nexit 0\n")
  File.chmod(0o755, omarchy)
  state_root = File.join(root, "state")
  FileUtils.mkdir_p(state_root)
  File.write(File.join(state_root, "reboot-required"), "")
  File.write(File.join(state_root, "restart-waybar-required"), "")
  File.write(File.join(state_root, "ignored-marker"), "must not be exposed")

  runner = OmarchyAdapterFakeRunner.new(omarchy)
  service = SoulCore::MaintenanceFleetStatusService.new(
    runner: runner,
    os_release_path: os_release,
    hostname_reader: -> { "atelier" },
    process_env: {},
    omarchy_path: omarchy,
    omarchy_state_root: state_root
  )
  workstation = service.send(:collect_workstation)

  check.call("workstation status exposes Omarchy adapter identity without mutation authority",
             workstation.dig("facts", "platform_adapter") == "omarchy" &&
               workstation.dig("facts", "platform_base_family") == "arch" &&
               workstation.dig("facts", "status_adapter") == "omarchy_arch_read_only" &&
               workstation.dig("facts", "mutation_supported") == false)
  check.call("Omarchy version and pending migrations are bounded read-only evidence",
             workstation["version"] == "Omarchy 4.0.2" &&
               workstation.dig("facts", "omarchy", "pending_migrations") == 2 &&
               workstation.dig("facts", "omarchy", "pending_migrations_status") == "ok")
  check.call("only approved Omarchy state marker names are exposed",
             workstation.dig("facts", "omarchy", "state_markers") ==
               %w[reboot-required restart-waybar-required] &&
               workstation.dig("reboot", "required") == true &&
               workstation.dig("reboot", "reason") == "Omarchy recorded a reboot requirement")
  check.call("status collection never invokes an Omarchy update or reboot",
             runner.calls.none? do |call|
               argv = call.fetch("argv")
               argv.first == omarchy && %w[update system].include?(argv[1])
             end)
end

if errors.empty?
  puts "Maintenance platform adapter registry A12 verification passed."
  exit 0
end

warn "Maintenance platform adapter registry A12 verification failed: #{errors.join(', ')}"
exit 1
