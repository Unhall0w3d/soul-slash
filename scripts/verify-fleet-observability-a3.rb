#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require_relative "../lib/soul_core/fleet_observability_summary_service"
require_relative "../lib/soul_core/conversation_fleet_observability_service"
require_relative "../lib/soul_core/conversation_tool_catalog"
require_relative "../lib/soul_core/application_facade"

errors = []
check = lambda do |label, result|
  puts "- #{label}: #{result ? 'ok' : 'FAIL'}"
  errors << label unless result
end

class QueryFixture
  attr_reader :queries
  def initialize(rows = {})
    @rows = rows
    @queries = []
  end

  def query(promql)
    @queries << promql
    query_id = SoulCore::FleetObservabilitySummaryService::QUERIES.key(promql)
    value = @rows.fetch(query_id, [])
    raise value if value.is_a?(Exception)

    {"status" => "success", "data" => {"resultType" => "vector", "result" => value}}
  end
end

row = ->(labels, value) { {"metric" => labels, "value" => [1_776_000_000, value.to_s]} }
fixture = QueryFixture.new(
  "endpoint_age" => [row.call({"device_id" => "workstation", "role" => "operator_workstation"}, 12), row.call({"device_id" => "hypervisor", "role" => "primary_hypervisor"}, 240)],
  "cpu_pressure" => [row.call({"device_id" => "workstation", "role" => "operator_workstation"}, 31.25)],
  "memory_pressure" => [row.call({"device_id" => "workstation", "role" => "operator_workstation"}, 48.5)],
  "root_pressure" => [row.call({"device_id" => "workstation", "role" => "operator_workstation"}, 59.1)],
  "host_network_errors" => [row.call({"device_id" => "hypervisor", "role" => "primary_hypervisor"}, 0.4)],
  "switch_up" => [row.call({"device_id" => "access-switch"}, 1)],
  "switch_errors" => [row.call({"device_id" => "access-switch", "ifName" => "gi1"}, 0.2)],
  "alerts" => [row.call({"device_id" => "hypervisor", "alertname" => "SoulEndpointStale", "severity" => "attention"}, 1)],
  "boot_age" => [row.call({"device_id" => "workstation", "role" => "operator_workstation"}, 8_000)]
)
service = SoulCore::FleetObservabilitySummaryService.new(
  query_client: fixture,
  process_env: {"SOUL_OBSERVABILITY_GRAFANA_URL" => "https://observatory.example.invalid/d/soul-fleet-operations-a2"},
  clock: -> { Time.utc(2026, 8, 16, 12, 0, 0) }
)
outcome = service.summary
report = outcome.fetch("data")

puts "Fleet observability A3 verification:"
check.call("fixed registry is executed exactly once with no arbitrary query input",
  fixture.queries == SoulCore::FleetObservabilitySummaryService::QUERIES.values &&
    report["query_ids"] == SoulCore::FleetObservabilitySummaryService::QUERIES.keys &&
    report["raw_promql_exposed"] == false)
check.call("summary normalizes endpoint, pressure, network, switch, alert, boot, and drill-down evidence",
  outcome["lifecycle_state"] == "complete" && report["state"] == "attention" &&
    report.dig("endpoints", "reporting") == 1 && report.dig("endpoints", "stale") == 1 &&
    report.dig("network", "switches_reporting") == 1 && report.dig("network", "switch_records").length == 1 && report.dig("network", "host_errors").length == 1 &&
    report["alerts"].length == 1 && report["boot_age"].length == 1 &&
    report["grafana_url"].start_with?("https://"))
check.call("summary is foreground, read-only, and privacy bounded",
  report["automatic_refresh"] == false && report["background_polling"] == false &&
    report["mutation_authority"] == "none" && report["raw_journal_returned"] == false &&
    !JSON.generate(report).include?("192.168."))

gap_fixture = QueryFixture.new("switch_up" => RuntimeError.new("connection /etc/private failed"))
gap = SoulCore::FleetObservabilitySummaryService.new(query_client: gap_fixture, process_env: {}, clock: -> { Time.utc(2026, 8, 16) }).summary.fetch("data")
check.call("unavailable sources become explicit redacted gaps rather than healthy zeros",
  gap["state"] == "partial" && gap["gaps"].any? { |entry| entry["source_id"] == "switch_up" && entry["reason"].include?("[private path]") })

empty_switches = SoulCore::FleetObservabilitySummaryService.new(query_client: QueryFixture.new, process_env: {}, clock: -> { Time.utc(2026, 8, 16) }).summary.fetch("data")
check.call("a successful empty SNMP query remains an explicit not-configured gap",
  empty_switches["state"] == "partial" && empty_switches["gaps"].any? { |entry| entry["source_id"] == "switch_up" && entry["reason"].include?("No reviewed SNMP switch target") })

conversation = SoulCore::ConversationFleetObservabilityService.new(summary_service: service).report
check.call("conversation response is useful and explicitly denies action authority",
  conversation["content"].include?("1 reporting and 1 stale") &&
    conversation["content"].include?("Grafana drill-down") &&
    conversation["content"].include?("No maintenance, reboot, switch change, alert mutation, or remediation"))

tool = SoulCore::ConversationToolCatalog.new
check.call("explicit chat and voice phrasing routes to the read-only observability tool",
  tool.match("How does the fleet look?").map(&:id) == ["fleet.observability"] &&
    tool.match("Summarize fleet observability").map(&:id) == ["fleet.observability"])

facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, fleet_observability_summary_service: service)
facade_result = facade.call({
  "schema_version" => "soul.application.v1", "request_id" => "fleet-observability-a3-0001",
  "operation" => "fleet_observability.summary", "parameters" => {}, "context" => {"interface" => "dashboard_test"}
})
facade_source = File.read(File.join(Dir.pwd, "lib", "soul_core", "application_facade.rb"))
check.call("application contract exposes the bounded Dashboard operation",
  facade_result["lifecycle_state"] == "complete" && facade_result.dig("data", "mutation_authority") == "none" &&
    facade_source.match?(/def fleet_observability_summary.*resolved_configuration.*resolver\.effective_environment/m))

html = File.read(File.join(Dir.pwd, "assets", "dashboard", "index.html"))
javascript = File.read(File.join(Dir.pwd, "assets", "dashboard", "dashboard.js"))
check.call("Host Stewardship renders one manual summary and HTTPS drill-down surface",
  html.include?("Read fleet observability") && html.include?("fleet-observability-drilldown") &&
    javascript.include?('callSoul("fleet_observability.summary")') &&
    html.include?('rel="noopener noreferrer"'))

exit(errors.empty? ? 0 : 1)
