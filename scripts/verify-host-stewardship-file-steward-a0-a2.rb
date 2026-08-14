#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/file_steward_service"
require_relative "../lib/soul_core/host_stewardship_capability_registry"
require_relative "../lib/soul_core/host_stewardship_service"
require_relative "../lib/soul_core/application_contract"

errors = []
check = lambda do |label, condition|
  if condition
    puts "PASS: #{label}"
  else
    errors << label
    warn "FAIL: #{label}"
  end
end

def data(result)
  result.fetch("data", {})
end

Dir.mktmpdir("soul-host-stewardship-") do |root|
  first = File.join(root, "first")
  second = File.join(root, "second")
  FileUtils.mkdir_p([first, second])
  env = { "SOUL_FILE_STEWARD_ROOTS" => "first=#{first};second=#{second}", "PATH" => ENV.fetch("PATH", "") }
  clock_time = Time.utc(2026, 8, 14, 12, 0, 0)
  service = SoulCore::FileStewardService.new(root: root, process_env: env, clock: -> { clock_time })

  File.write(File.join(first, "visible.txt"), "visible\n")
  File.write(File.join(first, ".hidden.txt"), "hidden\n")
  File.symlink(File.join(first, "visible.txt"), File.join(first, "linked.txt"))
  roots = service.roots
  inventory = service.inventory(root_id: "first", relative_path: ".")
  check.call("A0 exposes only configured public root IDs", roots["ok"] && data(roots).fetch("roots").map { |record| record["root_id"] } == %w[first second] && !JSON.generate(roots).include?(root))
  check.call("A0 omits hidden and symbolic-link entries", inventory["ok"] && data(inventory).fetch("entries").map { |entry| entry["name"] } == ["visible.txt"] && data(inventory)["omitted_count"] == 2)
  check.call("A0 inventory is read-only and bounded", inventory["mutation"] == "none" && data(inventory).dig("limits", "returned_entries") == 200 && data(inventory).dig("limits", "scanned_entries") == 2_000)

  rename_preview = service.operation_preview(action: "rename", source_root_id: "first", source_relative_path: "visible.txt", destination_root_id: "first", destination_relative_path: "renamed.txt")
  rename_data = data(rename_preview)
  wrong_confirmation = service.operation_execute(action: "rename", source_root_id: "first", source_relative_path: "visible.txt", destination_root_id: "first", destination_relative_path: "renamed.txt", confirmation: "YES", expected_digest: rename_data["expected_digest"])
  check.call("A1 refuses non-exact confirmation", wrong_confirmation["lifecycle_state"] == "blocked_for_human_review" && File.exist?(File.join(first, "visible.txt")))
  rename = service.operation_execute(action: "rename", source_root_id: "first", source_relative_path: "visible.txt", destination_root_id: "first", destination_relative_path: "renamed.txt", confirmation: SoulCore::FileStewardService::OPERATION_CONFIRMATION, expected_digest: rename_data["expected_digest"])
  check.call("A1 renames one exact file and verifies it", rename["ok"] && !File.exist?(File.join(first, "visible.txt")) && File.read(File.join(first, "renamed.txt")) == "visible\n" && data(rename).dig("verification", "source_absent"))

  copy_preview = service.operation_preview(action: "copy", source_root_id: "first", source_relative_path: "renamed.txt", destination_root_id: "second", destination_relative_path: "copy.txt")
  copy = service.operation_execute(action: "copy", source_root_id: "first", source_relative_path: "renamed.txt", destination_root_id: "second", destination_relative_path: "copy.txt", confirmation: SoulCore::FileStewardService::OPERATION_CONFIRMATION, expected_digest: data(copy_preview)["expected_digest"])
  check.call("A1 copies with byte and checksum verification", copy["ok"] && File.read(File.join(second, "copy.txt")) == "visible\n" && data(copy).dig("verification", "sha256") == Digest::SHA256.hexdigest("visible\n"))
  collision = service.operation_preview(action: "copy", source_root_id: "first", source_relative_path: "renamed.txt", destination_root_id: "second", destination_relative_path: "copy.txt")
  check.call("A1 never overwrites a destination", collision["lifecycle_state"] == "blocked_for_human_review")

  File.write(File.join(first, "stale.txt"), "before")
  stale_preview = service.operation_preview(action: "move", source_root_id: "first", source_relative_path: "stale.txt", destination_root_id: "second", destination_relative_path: "stale.txt")
  File.write(File.join(first, "stale.txt"), "after")
  stale = service.operation_execute(action: "move", source_root_id: "first", source_relative_path: "stale.txt", destination_root_id: "second", destination_relative_path: "stale.txt", confirmation: SoulCore::FileStewardService::OPERATION_CONFIRMATION, expected_digest: data(stale_preview)["expected_digest"])
  check.call("A1 rejects a source changed after preview", stale["lifecycle_state"] == "blocked_for_human_review" && File.exist?(File.join(first, "stale.txt")))

  File.link(File.join(first, "renamed.txt"), File.join(first, "hardlink.txt"))
  hardlink = service.operation_preview(action: "move", source_root_id: "first", source_relative_path: "hardlink.txt", destination_root_id: "second", destination_relative_path: "hardlink.txt")
  check.call("A1 refuses hard-linked sources", hardlink["lifecycle_state"] == "blocked_for_human_review")
  FileUtils.rm_f(File.join(first, "hardlink.txt"))

  sparse = File.join(first, "oversized.bin")
  File.open(sparse, "wb") { |file| file.truncate(SoulCore::FileStewardService::MAX_COPY_BYTES + 1) }
  oversized = service.operation_preview(action: "copy", source_root_id: "first", source_relative_path: "oversized.bin", destination_root_id: "second", destination_relative_path: "oversized.bin")
  check.call("A1 blocks oversized copies before execution", oversized["lifecycle_state"] == "blocked_for_human_review")

  oversized_quarantine_path = File.join(first, "oversized-quarantine.bin")
  File.open(oversized_quarantine_path, "wb") { |file| file.truncate(SoulCore::FileStewardService::MAX_QUARANTINE_BYTES + 1) }
  oversized_quarantine = service.quarantine_preview(root_id: "first", relative_path: "oversized-quarantine.bin")
  check.call("A2 blocks oversized quarantine before execution", oversized_quarantine["lifecycle_state"] == "blocked_for_human_review")
  FileUtils.rm_f(oversized_quarantine_path)

  File.write(File.join(first, "quarantine.txt"), "quarantine exact bytes\n")
  preview_private_state = Dir.glob(File.join(root, "Soul", "private", "file_steward", "**", "*"), File::FNM_DOTMATCH).sort
  quarantine_preview = service.quarantine_preview(root_id: "first", relative_path: "quarantine.txt")
  check.call("A2 quarantine preview performs no state-directory mutation", quarantine_preview["ok"] && Dir.glob(File.join(root, "Soul", "private", "file_steward", "**", "*"), File::FNM_DOTMATCH).sort == preview_private_state)
  quarantine = service.quarantine_execute(root_id: "first", relative_path: "quarantine.txt", confirmation: SoulCore::FileStewardService::QUARANTINE_CONFIRMATION, expected_digest: data(quarantine_preview)["expected_digest"])
  quarantine_id = data(quarantine)["quarantine_id"]
  check.call("A2 quarantine moves one exact file without deletion", quarantine["ok"] && !File.exist?(File.join(first, "quarantine.txt")) && quarantine_id.match?(SoulCore::FileStewardService::QUARANTINE_ID) && data(quarantine)["permanent_delete"] == false)
  listed = service.quarantine_list
  check.call("A2 lists owner-private quarantine evidence", listed["ok"] && data(listed)["count"] == 1 && data(listed).dig("entries", 0, "quarantine_id") == quarantine_id)

  restore_preview = service.restore_preview(quarantine_id: quarantine_id)
  File.write(File.join(first, "quarantine.txt"), "collision")
  collision_restore = service.restore_execute(quarantine_id: quarantine_id, confirmation: SoulCore::FileStewardService::RESTORE_CONFIRMATION, expected_digest: data(restore_preview)["expected_digest"])
  check.call("A2 restore refuses an occupied original destination", collision_restore["lifecycle_state"] == "blocked_for_human_review" && File.read(File.join(first, "quarantine.txt")) == "collision")
  FileUtils.rm_f(File.join(first, "quarantine.txt"))
  restore_preview = service.restore_preview(quarantine_id: quarantine_id)
  restore = service.restore_execute(quarantine_id: quarantine_id, confirmation: SoulCore::FileStewardService::RESTORE_CONFIRMATION, expected_digest: data(restore_preview)["expected_digest"])
  check.call("A2 restores exact bytes and closes the quarantine entry", restore["ok"] && File.read(File.join(first, "quarantine.txt")) == "quarantine exact bytes\n" && data(service.quarantine_list)["count"] == 0)

  unconfigured = SoulCore::FileStewardService.new(root: root, process_env: {})
  check.call("read roots never implicitly become File Steward mutation roots", !unconfigured.configured? && unconfigured.roots["ok"] && data(unconfigured.roots)["count"] == 0)

  registry = SoulCore::HostStewardshipCapabilityRegistry.new(process_env: env, clock: -> { clock_time })
  capabilities = registry.snapshot(file_steward_configured: true)
  permanent = data(capabilities).fetch("records").find { |record| record["id"] == "file_steward.permanent_delete" }
  check.call("A0 registry declares authority and permanent deletion boundary", capabilities["ok"] && data(capabilities)["background_behavior"] == false && permanent["available"] == false)

  host_source = lambda do
    {
      "collected_at" => clock_time.iso8601,
      "collected" => {
        "memory" => { "used_percent" => 82.5 },
        "load" => { "one_minute" => 0.2 },
        "filesystems" => [{ "used_percent" => 41 }],
        "systemd" => { "failed_unit_count" => 0 }
      },
      "core" => { "runtime_status" => "complete", "label" => "Soul Core" }
    }
  end
  security_source = -> { { "ok" => true, "data" => { "available" => true, "state" => "healthy", "collected_at" => clock_time.iso8601 } } }
  backup_source = -> { { "ok" => true, "data" => { "ready" => true, "mode" => "installed", "credential_ready" => true, "checked_at" => clock_time.iso8601 } } }
  presence = SoulCore::HostStewardshipService.new(host_source: host_source, security_source: security_source, backup_source: backup_source, capability_registry: registry, file_steward: service, clock: -> { clock_time }).snapshot
  check.call("A1 composes source-attributed host posture without mutation", presence["ok"] && data(presence)["state"] == "attention" && data(presence).fetch("signals").find { |signal| signal["id"] == "memory" }["state"] == "attention" && presence["mutation"] == "none")
  check.call("A1 declares foreground-only refresh behavior", data(presence)["automatic_refresh"] == false && data(presence)["background_polling"] == false)

  operations = SoulCore::ApplicationContract::OPERATIONS
  required_operations = %w[host_stewardship.capabilities host_stewardship.snapshot file_steward.roots file_steward.inventory file_steward.operation.preview file_steward.operation.execute file_steward.quarantine.list file_steward.quarantine.preview file_steward.quarantine.execute file_steward.restore.preview file_steward.restore.execute]
  check.call("application contract exposes the exact A0-A2 operation set", required_operations.all? { |operation| operations.key?(operation) } && operations.keys.none? { |operation| operation.start_with?("file_steward") && operation.include?("delete") })
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
check.call("Dashboard exposes Host Stewardship and File Steward controls", %w[host-stewardship-tab host-stewardship-panel refresh-host-presence file-steward-root file-steward-inventory preview-file-operation preview-file-quarantine restore-file-quarantine].all? { |id| html.include?("id=\"#{id}\"") })
check.call("Dashboard preserves Host Stewardship location across refresh", javascript.include?('host: "#host-stewardship-panel"') && javascript.include?("loadHostStewardship") && css.include?(".host-stewardship-panel"))
check.call(
  "Dashboard keeps all seven Host Stewardship sections compact and keyboard-accessible",
  html.scan(/<details class="[^"]*host-stewardship-disclosure[^"]*"/).length == 7 &&
    html.scan(/<summary class="card-heading host-stewardship-disclosure-summary">/).length == 7 &&
    css.include?(".host-stewardship-disclosure[open]") &&
    css.include?(".host-stewardship-disclosure-summary:focus-visible")
)

if errors.empty?
  puts "Host Stewardship and File Steward A0-A2 verification passed."
  exit 0
end

warn "Host Stewardship and File Steward A0-A2 verification failed: #{errors.join(', ')}"
exit 1
