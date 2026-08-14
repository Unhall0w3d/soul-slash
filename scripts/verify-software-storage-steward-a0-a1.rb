#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/software_steward_service"
require_relative "../lib/soul_core/storage_steward_service"
require_relative "../lib/soul_core/host_stewardship_capability_registry"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"

errors = []
def check(errors, label, valid)
  valid ? puts("PASS: #{label}") : (errors << label; warn("FAIL: #{label}"))
end
class Runner
  attr_reader :calls
  def initialize(results) = (@results = results; @calls = [])
  def call(argv, timeout_seconds:, output_limit_bytes:)
    @calls << argv
    (@results[argv] || { "status" => "unavailable", "stdout" => "", "stderr" => "missing", "exit_status" => nil }).merge("elapsed_ms" => 1.0)
  end
end
def ok(stdout) = { "status" => "ok", "stdout" => stdout, "stderr" => "", "exit_status" => 0 }
clock = -> { Time.utc(2026, 8, 14, 12, 0, 0) }

software_commands = {
  %w[pacman -Qq] => ok("base\nforeign\norphan\n"), %w[pacman -Qeq] => ok("base\n"),
  %w[pacman -Qmq] => ok("foreign\n"), %w[pacman -Qdtq] => ok("orphan\n"),
  %w[flatpak list --app --columns=application] => ok("org.example.App\n"),
  %w[arch-audit --json] => ok(JSON.generate([{ "name" => "AVG-1", "packages" => ["orphan"], "severity" => "High", "fixed" => "2", "issues" => ["CVE-2026-1"] }]))
}
software_runner = Runner.new(software_commands)
software = SoulCore::SoftwareStewardService.new(runner: software_runner, clock:).refresh.fetch("data")
check(errors, "A0 fixed allowlist and bounded inventory", software_runner.calls.sort == SoulCore::SoftwareStewardService::COMMANDS.values.sort && software.dig("package_inventory", "foreign", "items") == ["foreign"] && software.dig("flatpak", "count") == 1)
check(errors, "A0 attributes arch-audit and groups severity", software.dig("arch_audit", "may_contact_arch_security_tracker") && software.dig("arch_audit", "findings_by_severity", "high") == 1 && software.dig("arch_audit", "findings", 0, "affected_package") == "orphan" && software.dig("arch_audit", "findings", 0, "advisories", 0, "advisory") == "AVG-1")
closed = software_commands.merge(%w[arch-audit --json] => { "status" => "truncated", "stdout" => "", "stderr" => "", "exit_status" => nil })
check(errors, "A0 truncated audit is unavailable not clean", !SoulCore::SoftwareStewardService.new(runner: Runner.new(closed), clock:).refresh.dig("data", "arch_audit", "available"))

root = "/owner/private/root"
storage_commands = {
  %w[lsblk --json --bytes -o NAME,KNAME,TYPE,SIZE,MODEL,TRAN,ROTA] => ok(JSON.generate("blockdevices" => [{ "name" => "nvme0n1", "kname" => "nvme0n1", "type" => "disk", "size" => 100, "model" => "Disk", "serial" => "NO-LEAK" }])),
  ["findmnt", "--json", "--bytes", "-o", "TARGET,FSTYPE,SIZE,USED,AVAIL,USE%"] => ok(JSON.generate("filesystems" => [{ "target" => "/", "fstype" => "btrfs", "size" => 100, "used" => 50, "avail" => 50, "use%" => "50%" }])),
  %w[nvme list --output-format=json] => ok(JSON.generate("Devices" => [{ "DevicePath" => "/dev/nvme0n1", "ModelNumber" => "Disk", "Firmware" => "1", "PhysicalSize" => 100, "SerialNumber" => "NO-LEAK" }])),
  ["nvme", "smart-log", "--output-format=json", "/dev/nvme0n1"] => { "status" => "failed", "stdout" => "", "stderr" => "Permission denied", "exit_status" => 1 },
  ["compsize", "-b", root] => ok("Processed #{root}\nDisk Usage: 10M\n"),
  %w[iotop --batch --only --processes --no-color --hide-command --iter=2 --delay=2] => { "status" => "failed", "stdout" => "", "stderr" => "CAP_NET_ADMIN required", "exit_status" => 1 }
}
storage = SoulCore::StorageStewardService.new(runner: Runner.new(storage_commands), process_env: { "SOUL_STORAGE_STEWARD_PATHS" => "media=#{root}" }, clock:)
storage_result = storage.refresh
storage_data = storage_result.fetch("data")
wire = JSON.generate(storage_result)
check(errors, "A1 hides serials paths and command argv", !wire.include?("NO-LEAK") && !wire.include?(root) && !wire.include?("argv"))
check(errors, "A1 exposes bounded non-path identities", storage_data.dig("filesystems", "entries", 0, "mount_id") == "root" && storage_data.dig("nvme", "devices", 0, "device_id") == "nvme0n1" && storage_data.dig("compression_roots", 0, "root_id") == "media")
check(errors, "A1 smart failure remains unavailable without elevation", !storage_data.dig("nvme", "smart", 0, "available") && storage_data.dig("nvme", "smart", 0, "reason").include?("no elevation"))
io = storage.io_diagnostic.fetch("data")
check(errors, "A1 iotop failure remains unavailable without elevation", !io["available"] && io["reason"].include?("no elevation"))
row_commands = storage_commands.merge(%w[iotop --batch --only --processes --no-color --hide-command --iter=2 --delay=2] => ok("  91 be/4 owner 1.00 K/s 2.00 K/s 0.00 % 3.00 % secret-command\n"))
rows = SoulCore::StorageStewardService.new(runner: Runner.new(row_commands), process_env: {}, clock:).io_diagnostic.fetch("data")
check(errors, "A1 removes process command lines", rows["available"] && rows.dig("rows", 0, "process_id") == 91 && !JSON.generate(rows).include?("secret-command"))
truncated = storage_commands.merge(%w[lsblk --json --bytes -o NAME,KNAME,TYPE,SIZE,MODEL,TRAN,ROTA] => { "status" => "truncated", "stdout" => "", "stderr" => "", "exit_status" => nil })
check(errors, "A1 truncated source fails closed", !SoulCore::StorageStewardService.new(runner: Runner.new(truncated), process_env: {}, clock:).refresh.dig("data", "block_devices", "available"))

ids = SoulCore::HostStewardshipCapabilityRegistry.new(process_env: { "PATH" => "" }, clock:).snapshot.dig("data", "records").map { |record| record["id"] }
check(errors, "capability registry declares new authority", %w[software_steward.inventory storage_steward.inventory storage_steward.io_diagnostic].all? { |id| ids.include?(id) })
check(errors, "contract declares three read-only operations", %w[software_steward.refresh storage_steward.refresh storage_steward.io_diagnostic].all? { |operation| SoulCore::ApplicationContract::OPERATIONS[operation] == [] })
class FacadeFixture
  def initialize(name) = @name = name
  def refresh = { "ok" => true, "lifecycle_state" => "complete", "data" => { "fixture" => @name }, "mutation" => "none" }
  def io_diagnostic = refresh
end
facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, software_steward_service: FacadeFixture.new("software"), storage_steward_service: FacadeFixture.new("storage"))
facade_ok = %w[software_steward.refresh storage_steward.refresh storage_steward.io_diagnostic].each_with_index.all? do |operation, index|
  response = facade.call({ "schema_version" => "soul.application.v1", "request_id" => "verify-#{index + 100}", "operation" => operation, "parameters" => {}, "context" => { "interface" => "dashboard_test" } })
  response["lifecycle_state"] == "complete" && response.dig("data", "fixture") == (operation.start_with?("software") ? "software" : "storage")
end
check(errors, "facade routes all three foreground operations", facade_ok)
source = File.read(File.expand_path("../lib/soul_core/software_steward_service.rb", __dir__))
check(errors, "timeout terminates a complete process group", source.include?("pgroup: true") && source.include?("Process.kill(\"TERM\", -pid)") && source.include?("Process.kill(\"KILL\", -pid)"))
dashboard_html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
dashboard_js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
dashboard_css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
environment = File.read(File.expand_path("../.env.example", __dir__))
check(errors, "Dashboard exposes separate manual Software and Storage controls", %w[refresh-software-steward refresh-storage-steward sample-storage-io].all? { |id| dashboard_html.include?(%(id="#{id}")) } && dashboard_js.include?('callSoul("software_steward.refresh")') && dashboard_js.include?('callSoul("storage_steward.refresh")') && dashboard_js.include?('callSoul("storage_steward.io_diagnostic")'))
check(errors, "Dashboard renders bounded evidence without HTML injection", dashboard_js.include?("function renderSoftwareSteward") && dashboard_js.include?("function renderStorageSteward") && dashboard_js.include?("function renderStorageIoDiagnostic") && !dashboard_js.match?(/software-steward[^\n]*innerHTML|storage-steward[^\n]*innerHTML/) && dashboard_css.include?(".steward-evidence"))
check(errors, "portable compression roots remain empty by default", environment.match?(/^SOUL_STORAGE_STEWARD_PATHS=$/))

if errors.empty?
  puts "Software and Storage Steward A0-A1 verification passed."
  exit 0
end
warn "Software and Storage Steward A0-A1 verification failed: #{errors.join(', ')}"
exit 1
