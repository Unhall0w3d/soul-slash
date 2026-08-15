#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

require_relative "../lib/soul_core/fleet_operations_evidence_service"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/host_stewardship_capability_registry"

errors = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end

clock = -> { Time.utc(2026, 8, 15, 12, 0, 0) }
device = lambda do |id:, observed_at:, reachable: true, updates: 0, freshness: "cached_apt_metadata", reboot: false, control_target_id: nil|
  {
    "id" => id,
    "label" => id.capitalize,
    "role" => "test system",
    "address" => "192.0.2.10",
    "observed_at" => observed_at,
    "reachable" => reachable,
    "status" => reachable ? "healthy" : "offline",
    "control" => "maintenance",
    "facts" => {
      "management_channel" => "ssh",
      "maintenance_adapter" => "test_apt",
      "control_target_id" => control_target_id,
      "credential" => "must-not-leak",
      "command" => "sudo apt update"
    },
    "updates" => {"total" => updates, "freshness" => freshness},
    "reboot" => {"required" => reboot},
    "raw_output" => "/home/operator/private"
  }
end
receipt = lambda do |id:, device_id:, action: "maintenance", state: "complete", finished_at: "2026-08-15T10:00:00Z"|
  {
    "receipt_id" => id,
    "device_id" => device_id,
    "action" => action,
    "lifecycle_state" => state,
    "maintenance_adapter" => "test_apt",
    "started_at" => "2026-08-15T09:55:00Z",
    "finished_at" => finished_at,
    "summary" => "password=secret /etc/private",
    "evidence" => [{"argv" => ["sudo", "apt", "upgrade"], "stdout" => "secret"}]
  }
end

fleet = {
  "ok" => true,
  "data" => {
    "schema_version" => "soul.maintenance.fleet_status.v1",
    "collected_at" => "2026-08-15T11:00:00Z",
    "devices" => [
      device.call(id: "alpha", observed_at: "2026-08-15T11:00:00Z"),
      device.call(id: "inventory-beta", control_target_id: "beta", observed_at: "2026-08-15T11:00:00Z", updates: 2),
      device.call(id: "gamma", observed_at: "2026-08-15T09:00:00Z"),
      device.call(id: "delta", observed_at: "2026-08-15T11:00:00Z", reachable: false),
      device.call(id: "epsilon", observed_at: "2026-08-15T11:00:00Z", freshness: "not_queried"),
      device.call(id: "zeta", observed_at: "2026-08-15T11:00:00Z", reboot: false),
      device.call(id: "eta", observed_at: "2026-08-15T11:00:00Z", reboot: true)
    ]
  }
}
receipts = {
  "ok" => true,
  "data" => {
    "receipts" => [
      receipt.call(id: "r-alpha", device_id: "alpha"),
      receipt.call(id: "r-beta", device_id: "beta"),
      receipt.call(id: "r-gamma", device_id: "gamma"),
      receipt.call(id: "r-delta", device_id: "delta"),
      receipt.call(id: "r-epsilon", device_id: "epsilon"),
      receipt.call(id: "r-zeta", device_id: "zeta", action: "reboot"),
      receipt.call(id: "r-eta", device_id: "eta", action: "reboot"),
      receipt.call(id: "r-failed", device_id: "theta", state: "failed", finished_at: "2026-08-15T10:30:00Z")
    ]
  }
}

build = lambda do |fleet_source: fleet, receipt_source: receipts|
  SoulCore::FleetOperationsEvidenceService.new(
    fleet_snapshot_source: -> { fleet_source },
    device_receipt_source: -> { receipt_source },
    clock: clock
  )
end

puts "PatchMon concept adaptation A0 verification:"
outcome = build.call.compose
data = outcome.fetch("data")
transactions = data.fetch("transactions").to_h { |row| [row.fetch("receipt_id"), row] }
serialized = JSON.generate(outcome)

check.call(
  "complete envelope is foreground and read-only",
  outcome["ok"] == true && outcome["lifecycle_state"] == "complete" && outcome["mutation"] == "none" &&
    data["schema_version"] == SoulCore::FleetOperationsEvidenceService::SCHEMA_VERSION &&
    data.dig("contract", "background_polling") == false && data.dig("contract", "mutation_authority") == "none" &&
    data.dig("contract", "fleet_wide_action") == false
)
check.call(
  "execution and reconciliation remain separate",
  transactions.fetch("r-alpha")["execution_state"] == "complete" && transactions.fetch("r-alpha").dig("reconciliation", "state") == "verified" &&
    data.dig("contract", "execution_and_reconciliation_are_separate") == true
)
check.call(
  "remaining updates and unreachable evidence require attention",
  transactions.fetch("r-beta").dig("reconciliation", "state") == "attention" &&
    transactions.fetch("r-delta").dig("reconciliation", "state") == "attention" &&
    data.fetch("devices").any? { |record| record["device_id"] == "beta" && record["inventory_id"] == "inventory-beta" }
)
check.call(
  "older evidence remains pending and unassessed evidence stays unknown",
  transactions.fetch("r-gamma").dig("reconciliation", "state") == "awaiting_fresh_evidence" &&
    transactions.fetch("r-epsilon").dig("reconciliation", "state") == "unknown"
)
check.call(
  "reboot reconciliation respects current reboot evidence",
  transactions.fetch("r-zeta").dig("reconciliation", "state") == "verified" &&
    transactions.fetch("r-eta").dig("reconciliation", "state") == "attention"
)
check.call(
  "failed execution is not falsely reconciled",
  transactions.fetch("r-failed").dig("reconciliation", "state") == "not_applicable"
)
check.call(
  "addresses, credentials, paths, commands, summaries, and raw evidence do not leak",
  !serialized.include?("192.0.2.10") && !serialized.include?("must-not-leak") && !serialized.include?("/home/operator") &&
    !serialized.include?("/etc/private") && !serialized.include?("sudo apt") && !serialized.include?("password=secret")
)

unavailable = build.call(fleet_source: {"ok" => false, "reason" => "password=secret /private"}).compose.fetch("data")
check.call(
  "unavailable source is an explicit gap and not a healthy default",
  unavailable.fetch("devices").empty? && unavailable.fetch("sources").find { |source| source["source_id"] == "fleet_snapshot" }["available"] == false &&
    !JSON.generate(unavailable).include?("password=secret")
)

many_devices = 80.times.map { |index| device.call(id: "device#{index}", observed_at: "2026-08-15T11:00:00Z") }
many_receipts = 80.times.map { |index| receipt.call(id: "receipt#{index}", device_id: "device#{index}") }
bounded = build.call(
  fleet_source: {"data" => {"devices" => many_devices}},
  receipt_source: {"data" => {"receipts" => many_receipts}}
).compose.fetch("data")
check.call(
  "devices and transactions remain bounded",
  bounded.fetch("devices").length == SoulCore::FleetOperationsEvidenceService::MAX_DEVICES &&
    bounded.fetch("transactions").length == SoulCore::FleetOperationsEvidenceService::MAX_TRANSACTIONS
)
check.call("fixed inputs and clock produce deterministic output", JSON.generate(outcome) == JSON.generate(build.call.compose))

fixture = Object.new
fixture.define_singleton_method(:compose) { outcome }
facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, fleet_operations_evidence_service: fixture)
facade_response = facade.call({
  "schema_version" => "soul.application.v1",
  "request_id" => "verify-fleet-evidence-100",
  "operation" => "maintenance.fleet.evidence",
  "parameters" => {},
  "context" => {"interface" => "dashboard_test"}
})
check.call(
  "application contract, facade, and capability registry expose only the read operation",
  SoulCore::ApplicationContract::OPERATIONS["maintenance.fleet.evidence"] == [] &&
    facade_response["lifecycle_state"] == "complete" && facade_response.dig("meta", "mutation") == "none" &&
    SoulCore::HostStewardshipCapabilityRegistry.new(process_env: {"PATH" => ""}, clock: clock).snapshot
      .dig("data", "records").any? { |record| record["id"] == "maintenance.fleet.evidence" && record["mutation"] == "none" }
)

dashboard_html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
dashboard_js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
evidence_markup = dashboard_html[/<details class="maintenance-operations-evidence".*?<\/details>/m].to_s
check.call(
  "Guided Maintenance renders retained reconciliation without a new action button",
  dashboard_html.include?('id="maintenance-evidence-transactions"') &&
    dashboard_js.include?('callSoul("maintenance.fleet.evidence")') &&
    dashboard_js.include?("function renderFleetOperationsEvidence") &&
    !evidence_markup.match?(/<(button|input|select|textarea)\b/i)
)

control_source = File.read(File.expand_path("../lib/soul_core/maintenance_device_control_service.rb", __dir__))
check.call(
  "existing device control preview and exact confirmation gates remain present",
  control_source.include?("def preview(device_id:, action:)") && control_source.include?("exact device confirmation is required") &&
    control_source.include?("device preview changed; review the fresh plan")
)

exit(errors.empty? ? 0 : 1)
