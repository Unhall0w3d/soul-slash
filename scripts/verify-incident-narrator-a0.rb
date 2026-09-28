#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

require_relative "../lib/soul_core/incident_narrator_service"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/host_stewardship_capability_registry"

errors = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end

clock = -> { Time.utc(2026, 8, 14, 18, 0, 0) }
alerts = {
  "data" => {
    "alerts" => [
      {"event_id" => "old", "occurred_at" => "2026-08-14T17:00:00Z", "severity" => "high", "rule_id" => "5710", "agent_name" => "atelier", "description" => "password=leak /home/operator/secret"},
      {"event_id" => "new", "occurred_at" => "2026-08-14T17:30:00Z", "severity" => "critical", "rule_id" => "9001", "agent_name" => "warden", "description" => "sudo restic /srv/private"}
    ]
  }
}
security = {
  "data" => {
    "collected_at" => "2026-08-14T17:45:00Z",
    "manager" => {"state" => "active"},
    "summary" => {"active" => 3, "total" => 4}
  }
}
device_receipts = {
  "data" => {
    "receipts" => [
      {"receipt_id" => "device-old", "completed_at" => "2026-08-14T16:00:00Z", "action" => "maintain", "mode" => "foreground", "lifecycle_state" => "complete"},
      {"receipt_id" => "device-new", "completed_at" => "2026-08-14T17:50:00Z", "action" => "maintain", "mode" => "foreground", "lifecycle_state" => "failed", "reason" => "password=secret /etc/soul/config sudo pacman -Syu"}
    ]
  }
}
host_receipts = {
  "data" => {
    "receipts" => [
      {"receipt_id" => "host-one", "completed_at" => "2026-08-14T17:40:00Z", "operation" => "reboot", "mode" => "foreground", "state" => "complete"}
    ]
  }
}
backup = {
  "data" => {
    "drs" => {
      "receipt_id" => "drs-one",
      "completed_at" => "2026-08-14T17:20:00Z",
      "state" => "complete",
      "repository" => "/mnt/private/restic",
      "password" => "not-for-output"
    }
  }
}

build = lambda do |alert_source: alerts, security_source: security, device_source: device_receipts, host_source: host_receipts, backup_source: backup, current_clock: clock|
  SoulCore::IncidentNarratorService.new(
    alert_source: alert_source.respond_to?(:call) ? alert_source : -> { alert_source },
    security_source: security_source.respond_to?(:call) ? security_source : -> { security_source },
    maintenance_device_receipt_source: device_source.respond_to?(:call) ? device_source : -> { device_source },
    maintenance_host_receipt_source: host_source.respond_to?(:call) ? host_source : -> { host_source },
    backup_source: backup_source.respond_to?(:call) ? backup_source : -> { backup_source },
    clock: current_clock
  )
end

puts "Incident Narrator A0 verification:"
outcome = build.call.compose
data = outcome.fetch("data")
serialized = JSON.generate(outcome)

check.call(
  "complete envelope is foreground and read-only",
  outcome["ok"] == true && outcome["lifecycle_state"] == "complete" && outcome["mutation"] == "none" &&
    data["schema_version"] == SoulCore::IncidentNarratorService::SCHEMA_VERSION &&
    data["automatic_refresh"] == false && data["background_polling"] == false &&
    data["mutation_authority"] == "none" && data["model_used"] == false
)
check.call(
  "newest evidence is first and critical state dominates",
  data["events"].map { |event| event["evidence_id"] }.first == "maintenance_device_receipts:device-new" &&
    data["events"].first["observed_at"] == "2026-08-14T17:50:00Z" && data["state"] == "critical"
)
check.call(
  "retained input descriptions, paths, credentials, and commands do not leak",
  !serialized.include?("leak") && !serialized.include?("/home/operator") && !serialized.include?("/etc/soul") &&
    !serialized.include?("/mnt/private") && !serialized.include?("not-for-output") && !serialized.include?("pacman -Syu") &&
    !serialized.include?("password=secret") && serialized.include?("ended failed.")
)
check.call(
  "maintenance failure is retained and every inference is bounded low confidence",
  data["findings"].any? { |finding| finding["kind"] == "observation" && finding["finding_id"] == "maintenance_device_receipts-failure-summary" } &&
    data["findings"].select { |finding| finding["kind"] == "inference" }.all? { |finding| finding["confidence"] == "low" && !finding["supporting_evidence_ids"].empty? }
)

unavailable = build.call(
  security_source: {"ok" => false, "lifecycle_state" => "failed", "reason" => "token=should-not-leak /var/private", "data" => {}}
).compose
unavailable_data = unavailable.fetch("data")
check.call(
  "unavailable source becomes an explicit gap and never healthy",
  unavailable["lifecycle_state"] == "complete" && unavailable_data["state"] == "critical" &&
    unavailable_data["findings"].any? { |finding| finding["kind"] == "gap" && finding["finding_id"] == "security_snapshot-unavailable" } &&
    !JSON.generate(unavailable).include?("should-not-leak")
)

stale = build.call(
  alert_source: {"collected_at" => "2026-08-14T17:50:00Z", "alerts" => []},
  security_source: {"collected_at" => "2026-08-10T17:45:00Z", "manager" => {"state" => "healthy"}, "summary" => {"active" => 3, "total" => 3}}
).compose.fetch("data")
check.call(
  "stale retained health evidence is disclosed as a gap",
  stale["state"] == "attention" && stale["sources"].any? { |source| source["source_id"] == "security_snapshot" && source["stale"] == true } &&
    stale["findings"].any? { |finding| finding["kind"] == "gap" && finding["finding_id"] == "security_snapshot-stale" }
)

many_alerts = 80.times.map do |index|
  {
    "event_id" => "a#{index}",
    "occurred_at" => "2026-08-14T#{format("%02d", index / 60)}:#{format("%02d", index % 60)}:00Z",
    "severity" => "informational",
    "rule_id" => "rule-#{index}",
    "agent_name" => "agent"
  }
end
many_receipts = 40.times.map do |index|
  {
    "receipt_id" => "r#{index}",
    "completed_at" => "2026-08-14T17:00:00Z",
    "action" => "maintain",
    "mode" => "foreground",
    "state" => "complete"
  }
end
bounded = build.call(
  alert_source: {"alerts" => many_alerts},
  device_source: {"receipts" => many_receipts},
  host_source: {"receipts" => many_receipts}
).compose.fetch("data")
check.call(
  "events and findings stay bounded",
  bounded["events"].length == SoulCore::IncidentNarratorService::MAX_EVENTS &&
    bounded["findings"].length <= SoulCore::IncidentNarratorService::MAX_FINDINGS
)

again = build.call.compose
check.call("fixed inputs and clock produce deterministic output", JSON.generate(outcome) == JSON.generate(again))

failed = build.call(current_clock: -> { nil }).compose
check.call(
  "unexpected composition failure remains a failed no-mutation envelope",
  failed["ok"] == false && failed["lifecycle_state"] == "failed" && failed["mutation"] == "none" &&
    failed.dig("data", "schema_version") == SoulCore::IncidentNarratorService::SCHEMA_VERSION
)

check.call(
  "application contract and capability registry declare the read-only operation",
  SoulCore::ApplicationContract::OPERATIONS["incident_narrator.compose"] == [] &&
    SoulCore::HostStewardshipCapabilityRegistry.new(process_env: {"PATH" => ""}, clock:).snapshot
      .dig("data", "records").any? { |record| record["id"] == "incident_narrator.compose" && record["mutation"] == "none" }
)

fixture = Object.new
fixture.define_singleton_method(:compose) { {"ok" => true, "lifecycle_state" => "complete", "data" => {"schema_version" => SoulCore::IncidentNarratorService::SCHEMA_VERSION}, "mutation" => "none"} }
facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, incident_narrator_service: fixture)
facade_response = facade.call({"schema_version" => "soul.application.v1", "request_id" => "verify-incident-100", "operation" => "incident_narrator.compose", "parameters" => {}, "context" => {"interface" => "dashboard_test"}})
check.call(
  "application facade routes the retained-evidence operation",
  facade_response["lifecycle_state"] == "complete" && facade_response.dig("data", "schema_version") == SoulCore::IncidentNarratorService::SCHEMA_VERSION
)

dashboard_html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
dashboard_js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
dashboard_css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
check.call(
  "Dashboard exposes one explicit foreground compose action",
  dashboard_html.include?('id="compose-incident-narrative"') && dashboard_js.include?('callSoul("incident_narrator.compose")') &&
    dashboard_js.include?("function renderIncidentNarrative") && dashboard_css.include?(".incident-narrator-card")
)
check.call(
  "Dashboard renders narrative text without HTML injection or remediation actions",
  !dashboard_js.match?(/incident-narrator[^\n]*innerHTML/) && !dashboard_html.match?(/incident-narrator[^\n]*(remediate|acknowledge|suppress)/i)
)

device_source = File.read(File.expand_path("../lib/soul_core/maintenance_device_control_service.rb", __dir__))
host_source = File.read(File.expand_path("../lib/soul_core/maintenance_foreground_execution_service.rb", __dir__))
backup_source = File.read(File.expand_path("../lib/soul_core/backup_administration_service.rb", __dir__))
device_retained = device_source[/def retained_receipts.*?rescue ArgumentError/m].to_s
host_retained = host_source[/def retained_receipts.*?rescue ArgumentError/m].to_s
backup_retained = backup_source[/def retained_drs_status.*?rescue StandardError/m].to_s
check.call(
  "integration uses retained readers rather than source refresh or preparation",
  device_source.match?(/def retained_receipts.*?Dir\.glob/m) && host_source.match?(/def retained_receipts.*?receipt_paths/m) &&
    backup_source.match?(/def retained_drs_status.*?latest_drs_status/m) &&
    !device_retained.include?("prepare_directories") && !host_retained.include?("desktop_handoff") &&
    !host_retained.include?("native_evidence") && !backup_retained.include?("@runner")
)

quiet_sources = {
  alert_source: {"data" => {"collected_at" => "2026-08-14T17:55:00Z", "alerts" => []}},
  security_source: {"data" => {"state" => "healthy", "collected_at" => "2026-08-14T17:55:00Z", "manager" => {"state" => "healthy"}, "summary" => {"active" => 1, "total" => 1}}},
  device_source: {"data" => {"receipts" => []}},
  host_source: {"data" => {"receipts" => []}},
  backup_source: {"data" => {"drs" => {"state" => "complete", "completed_at" => "2026-08-14T17:55:00Z"}}}
}
quiet = build.call(**quiet_sources).compose.fetch("data")
check.call(
  "five retained sources can compose a quiet report without a remote query",
  quiet["state"] == "quiet" && quiet["sources"].map { |source| source["source_id"] } == SoulCore::IncidentNarratorService::SOURCE_IDS &&
    quiet["sources"].length == 5
)

overflow_alerts = 64.times.map do |index|
  {"event_id" => "info-#{index}", "occurred_at" => (Time.utc(2026, 8, 14, 16, 30) + index * 60).iso8601,
   "severity" => "informational", "rule_id" => "routine", "agent_name" => "atelier"}
end
overflow_alerts << {"event_id" => "older-critical", "occurred_at" => "2026-08-14T16:00:00Z",
                    "severity" => "critical", "rule_id" => "urgent", "agent_name" => "atelier"}
overflow = build.call(**quiet_sources.merge(alert_source: {"data" => {"collected_at" => "2026-08-14T17:55:00Z", "alerts" => overflow_alerts}})).compose.fetch("data")
check.call(
  "grouping occurs before the event bound so an older critical alert survives",
  overflow["state"] == "critical" && overflow["events"].any? { |event| event["evidence_id"] == "wazuh:older-critical" } &&
    overflow["sources"].first["event_count"] == 65 && overflow["events"].count { |event| event["category"] == "security_alert" } == 2
)

distinct_overflow = build.call(**quiet_sources.merge(
  alert_source: {"data" => {"collected_at" => "2026-08-14T17:55:00Z", "alerts" => many_alerts + [overflow_alerts.last]}}
)).compose.fetch("data")
check.call(
  "urgent evidence survives the output bound and selected events remain newest first",
  distinct_overflow["state"] == "critical" && distinct_overflow["events"].length == SoulCore::IncidentNarratorService::MAX_EVENTS &&
    distinct_overflow["events"].any? { |event| event["evidence_id"] == "wazuh:older-critical" } &&
    distinct_overflow["events"].map { |event| event["observed_at"] || "" } ==
      distinct_overflow["events"].map { |event| event["observed_at"] || "" }.sort.reverse
)

malformed_sources = {
  "wazuh_alerts" => {alert_source: {"data" => {"collected_at" => "2026-08-14T17:55:00Z", "alerts" => "not-an-array"}}},
  "security_snapshot" => {security_source: {"data" => {"manager" => "healthy", "summary" => {}}}},
  "maintenance_device_receipts" => {device_source: {"data" => {"receipts" => "not-an-array"}}},
  "maintenance_host_receipts" => {host_source: {"data" => {"receipts" => [false]}}},
  "backup_drs" => {backup_source: {"data" => {"drs" => "not-an-object"}}}
}
check.call(
  "malformed retained source shapes become explicit attention gaps",
  malformed_sources.all? do |source_id, override|
    report = build.call(**quiet_sources.merge(override)).compose.fetch("data")
    report["state"] == "attention" &&
      report["sources"].any? { |source| source["source_id"] == source_id && source["available"] == false } &&
      report["findings"].any? { |finding| finding["kind"] == "gap" && finding["finding_id"] == "#{source_id}-unavailable" }
  end
)

partial = build.call(**quiet_sources.merge(
  security_source: {"data" => quiet_sources.fetch(:security_source).fetch("data").merge("state" => "partial")}
)).compose.fetch("data")
truncated = build.call(**quiet_sources.merge(
  alert_source: {"data" => quiet_sources.fetch(:alert_source).fetch("data").merge("query" => {"truncated" => true})}
)).compose.fetch("data")
check.call(
  "partial and truncated retained evidence cannot present as quiet",
  [partial, truncated].all? { |report| report["state"] == "attention" && report["headline"].include?("incomplete") } &&
    partial["findings"].any? { |finding| finding["finding_id"] == "security_snapshot-partial" } &&
    truncated["findings"].any? { |finding| finding["finding_id"] == "wazuh_alerts-partial" }
)

private_text = "Authorization: Bearer fixtureopaque AWS_ACCESS_KEY_ID=FIXTUREKEY"
private_receipt = {"receipt_id" => "private-one", "finished_at" => "2026-08-14T17:50:00Z", "action" => "maintenance",
                   "lifecycle_state" => "failed", "summary" => private_text, "reason" => private_text}
private_report = build.call(**quiet_sources.merge(
  device_source: {"data" => {"receipts" => [private_receipt]}}
)).compose
unavailable_report = build.call(**quiet_sources.merge(
  security_source: {"ok" => false, "reason" => private_text}
)).compose
raised_report = build.call(**quiet_sources.merge(
  security_source: -> { raise private_text }
)).compose
check.call(
  "free-form receipt diagnostics, unavailable reasons, and source exceptions stay private",
  [private_report, unavailable_report, raised_report].none? { |report| JSON.generate(report).include?("fixtureopaque") || JSON.generate(report).include?("FIXTUREKEY") }
)
failed_private = build.call(**quiet_sources.merge(current_clock: -> { raise private_text })).compose
check.call(
  "top-level failure does not echo exception text",
  failed_private["lifecycle_state"] == "failed" && !JSON.generate(failed_private).include?("fixtureopaque")
)

invalid_semantics = [
  {alert_source: {"data" => {"alerts" => [{"event_id" => "bad", "occurred_at" => "2026-08-14T17:00:00Z",
                                            "severity" => "nonsense", "level" => 15, "rule_id" => "123",
                                            "agent_name" => "atelier"}], "collected_at" => "2026-08-14T17:55:00Z"}}},
  {alert_source: {"data" => {"alerts" => [], "query" => {"truncated" => "false"}, "collected_at" => "2026-08-14T17:55:00Z"}}},
  {security_source: {"data" => {"state" => "healthy", "collected_at" => "2026-08-14T17:55:00Z",
                                 "manager" => {"state" => "healthy"}, "summary" => {"active" => "unknown", "total" => 1}}}}
]
check.call(
  "contradictory alert severity and malformed source counts cannot read as healthy",
  invalid_semantics.all? do |override|
    report = build.call(**quiet_sources.merge(override)).compose.fetch("data")
    report["state"] == "attention" && report["findings"].any? { |finding| finding["kind"] == "gap" }
  end
)

too_many_receipts = build.call(**quiet_sources.merge(
  host_source: {"data" => {"receipts" => many_receipts}}
)).compose.fetch("data")
check.call(
  "out-of-contract receipt counts are explicit gaps",
  too_many_receipts["state"] == "attention" &&
    too_many_receipts["findings"].any? { |finding| finding["finding_id"] == "maintenance_host_receipts-unavailable" }
)

malformed_nested = build.call(**quiet_sources.merge(
  alert_source: {"data" => {"collected_at" => "2026-08-14T17:55:00Z", "alerts" => [{"event_id" => "bad", "severity" => "high"}]}}
)).compose.fetch("data")
oversized_alert_input = build.call(**quiet_sources.merge(
  alert_source: {"data" => {"collected_at" => "2026-08-14T17:55:00Z", "alerts" => many_alerts * 4}}
)).compose.fetch("data")
check.call(
  "invalid nested alerts and out-of-contract alert counts become gaps",
  [malformed_nested, oversized_alert_input].all? do |report|
    report["state"] == "attention" &&
      report["findings"].any? { |finding| finding["finding_id"] == "wazuh_alerts-unavailable" }
  end
)

unknown_state = build.call(**quiet_sources.merge(
  security_source: {"data" => quiet_sources.fetch(:security_source).fetch("data").merge("state" => "FIXTUREKEY")}
)).compose.fetch("data")
unknown_fields = build.call(**quiet_sources.merge(
  device_source: {"data" => {"receipts" => [private_receipt.merge("action" => "FIXTUREKEY", "mode" => "fixtureopaque", "lifecycle_state" => "FIXTUREKEY")]}},
  backup_source: {"data" => {"drs" => {"state" => "FIXTUREKEY"}}}
)).compose
check.call(
  "unknown state, operation, and mode values never echo private source text",
  unknown_state["state"] == "attention" &&
    unknown_state["findings"].any? { |finding| finding["finding_id"] == "security_snapshot-unknown" } &&
    !JSON.generate(unknown_state).include?("FIXTUREKEY") &&
    !JSON.generate(unknown_fields).include?("FIXTUREKEY") &&
    !JSON.generate(unknown_fields).include?("fixtureopaque")
)

stub_source = ->(method_name, value) do
  Object.new.tap { |object| object.define_singleton_method(method_name) { |**_kwargs| value } }
end
active_facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, clock: clock)
active_facade.define_singleton_method(:wazuh_alert_evidence) { stub_source.call(:snapshot, quiet_sources.fetch(:alert_source)) }
active_facade.define_singleton_method(:wazuh_security_status) { stub_source.call(:snapshot, quiet_sources.fetch(:security_source)) }
active_facade.define_singleton_method(:maintenance_device_control) { stub_source.call(:retained_receipts, quiet_sources.fetch(:device_source)) }
active_facade.define_singleton_method(:maintenance_foreground_execution) { stub_source.call(:retained_receipts, quiet_sources.fetch(:host_source)) }
active_facade.define_singleton_method(:backup_administration) { stub_source.call(:retained_drs_status, quiet_sources.fetch(:backup_source)) }
fleet_calls = 0
active_facade.define_singleton_method(:fleet_observability_summary) { fleet_calls += 1; raise "A0 must not query fleet observability" }
active_result = active_facade.call({"schema_version" => "soul.application.v1", "request_id" => "verify-incident-101",
                                   "operation" => "incident_narrator.compose", "parameters" => {}, "context" => {"interface" => "dashboard_test"}})
check.call(
  "real facade composition reads only five retained sources",
  active_result["lifecycle_state"] == "complete" && active_result.dig("data", "sources")&.length == 5 && fleet_calls.zero?
)

exit(errors.empty? ? 0 : 1)
