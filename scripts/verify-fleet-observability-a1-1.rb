#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
errors = []

check = lambda do |label, result|
  puts "- #{label}: #{result ? 'ok' : 'FAIL'}"
  errors << label unless result
end

puts "Fleet observability A1.1 verification:"

manifest = JSON.parse(File.read(File.join(ROOT, "config", "fleet_observability_dashboard_a1_1.json")))
dashboard_path = File.join(ROOT, "deploy", "observability", "central", "fleet-overview.json")
dashboard = JSON.parse(File.read(dashboard_path))
renderer = File.read(File.join(ROOT, "deploy", "observability", "central", "render-dashboard.sh"))
review = File.read(File.join(ROOT, "docs", "assessments", "FLEET_OBSERVABILITY_A1_1_REVIEW.md"))

flatten = lambda do |panels|
  panels.flat_map { |panel| [panel, *flatten.call(panel.fetch("panels", []))] }
end
panels = flatten.call(dashboard.fetch("panels"))

check.call("manifest is a bounded dashboard-only A1 extension",
  manifest["schema_version"] == "soul.fleet-observability.dashboard.a1.1.v1" &&
    manifest["extends"] == "soul.fleet-observability.deployment.a1.v1" &&
    manifest["collection_change"] == "none" &&
    manifest["journal_ingest"] == false &&
    manifest["alerting"] == false &&
    manifest["mutation_authority"] == "none")

overview_titles = [
  "Reporting endpoints", "Endpoint sample age", "Failed systemd units",
  "CPU package temperature", "Global presence", "CPU busy by endpoint",
  "Memory used", "Root filesystem used"
]
top_level = dashboard.fetch("panels").reject { |panel| panel["type"] == "row" }
check.call("overview has the exact eight reviewed panels",
  top_level.map { |panel| panel["title"] } == overview_titles)

row_titles = [
  "Compute and memory pressure", "Storage behavior", "Network health",
  "Services and stability", "Thermal and power sensors"
]
rows = dashboard.fetch("panels").select { |panel| panel["type"] == "row" }
check.call("five detail rows are collapsed by default",
  rows.map { |row| row["title"] } == row_titles &&
    rows.all? { |row| row["collapsed"] == true && row.fetch("panels").any? })

expressions = panels.flat_map { |panel| panel.fetch("targets", []).map { |target| target["expr"] } }.compact.join("\n")
metric_families = %w[
  node_uname_info node_cpu_seconds_total node_load1 node_memory_MemAvailable_bytes
  node_memory_SwapTotal_bytes node_vmstat_pswpin node_disk_read_bytes_total
  node_disk_io_time_seconds_total node_disk_read_time_seconds_total
  node_network_receive_bytes_total node_network_receive_errs_total
  node_systemd_unit_state node_systemd_service_restart_total node_boot_time_seconds
  node_vmstat_oom_kill node_hwmon_temp_celsius node_hwmon_sensor_label
  node_hwmon_power_average_watt
]
check.call("queries cover the reviewed existing metric families",
  metric_families.all? { |metric| expressions.include?(metric) })

role_colors = {
  "/.* · operator_workstation/" => "#00E5FF",
  "/.* · primary_hypervisor/" => "#D4AF37",
  "/.* · secondary_hypervisor/" => "#A970FF",
  "/.* · backup_target/" => "#73BF69"
}
time_series = panels.select { |panel| panel["type"] == "timeseries" }
check.call("role colors remain stable across every time-series panel",
  time_series.length == 16 && time_series.all? do |panel|
    overrides = panel.dig("fieldConfig", "overrides") || []
    actual = overrides.to_h do |override|
      [override.dig("matcher", "options"), override.dig("properties", 0, "value", "fixedColor")]
    end
    panel.dig("targets", 0, "legendFormat") == "{{device_id}} · {{role}}" &&
      overrides.all? { |override| override.dig("matcher", "id") == "byRegexp" } &&
      actual == role_colors
  end)

thermal_panels = panels.select { |panel| ["CPU package temperature", "NVMe composite temperature", "Chipset temperature"].include?(panel["title"]) }
thermal_expressions = thermal_panels.flat_map { |panel| panel.fetch("targets").map { |target| target.fetch("expr") } }.join("\n")
check.call("thermal panels are sensor-specific and discard impossible readings",
  thermal_panels.length == 4 &&
    thermal_expressions.include?("node_hwmon_sensor_label") &&
    thermal_expressions.include?("Package id [0-9]+|CPU Package|Tctl|Tdie") &&
    thermal_expressions.include?('label="Composite"') &&
    thermal_expressions.include?("thermal_thermal_zone2") &&
    thermal_expressions.scan(">= 0").length == 4 &&
    thermal_expressions.scan("< 125").length == 4)

thermal_row = rows.find { |row| row["title"] == "Thermal and power sensors" }
check.call("CPU activity is adjacent to package temperature",
  thermal_row.fetch("panels").first(2).map { |panel| panel["title"] } ==
    ["CPU package temperature", "CPU busy beside temperature"])

map = panels.find { |panel| panel["type"] == "geomap" }
map_expression = map&.dig("targets", 0, "expr").to_s
check.call("global presence uses owner-private render placeholders",
  map_expression.include?("__SOUL_SITE_LABEL__") &&
    map_expression.include?("__SOUL_SITE_LATITUDE__") &&
    map_expression.include?("__SOUL_SITE_LONGITUDE__") &&
    map.dig("options", "layers", 0, "location", "mode") == "coords")

check.call("renderer validates a root-owned bounded region file",
  renderer.include?("EUID") && renderer.include?("mode 0600") &&
    renderer.include?("value >= -90 && value <= 90") &&
    renderer.include?("value >= -180 && value <= 180") &&
    renderer.include?("unresolved owner-local placeholders") &&
    !renderer.include?("systemctl"))

public_text = [
  File.join(ROOT, "config", "fleet_observability_dashboard_a1_1.json"),
  File.join(ROOT, "docs", "soul", "FLEET_OBSERVABILITY_A1_1_BRIEF.md"),
  File.join(ROOT, "docs", "assessments", "FLEET_OBSERVABILITY_A1_1_REVIEW.md"),
  dashboard_path,
  File.join(ROOT, "deploy", "observability", "central", "central.env.example")
].map { |path| File.read(path) }.join("\n")
check.call("public A1.1 assets contain no owner-private site identity",
  !public_text.match?(/192\.168\.|\b(?:atelier|forge|foundry|warden|crucible|witness|temper|syracuse)\b|bhones/i))

check.call("A1.1 human live review remains explicit",
  review.include?("[x] live Grafana deployment") &&
    review.include?("[x] Operator visual review") &&
    review.include?("Operator-approved"))

exit(errors.empty? ? 0 : 1)
