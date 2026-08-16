#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
errors = []
check = lambda do |label, result|
  puts "- #{label}: #{result ? 'ok' : 'FAIL'}"
  errors << label unless result
end

puts "Fleet observability A2 verification:"
manifest = JSON.parse(File.read(File.join(ROOT, "config", "fleet_observability_a2_a3.json")))
prometheus = YAML.safe_load(File.read(File.join(ROOT, "deploy", "observability", "central", "prometheus.yml")), aliases: true)
rules = YAML.safe_load(File.read(File.join(ROOT, "deploy", "observability", "central", "fleet-alerts.yml")), aliases: true)
dashboard = JSON.parse(File.read(File.join(ROOT, "deploy", "observability", "central", "fleet-operations.json")))
alloy = File.read(File.join(ROOT, "deploy", "observability", "collector", "config.alloy"))
central = File.read(File.join(ROOT, "deploy", "observability", "central", "install-central.sh"))
collector = File.read(File.join(ROOT, "deploy", "observability", "collector", "install-collector.sh"))
renderer = File.read(File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"))

check.call("manifest preserves the read-only A2 boundary",
  manifest.dig("a2", "notifications") == false && manifest.dig("a2", "remediation") == false &&
    manifest["mutation_authority"] == "none")

jobs = prometheus.fetch("scrape_configs").to_h { |job| [job.fetch("job_name"), job] }
switch_job = jobs.fetch("switch_interfaces", {})
check.call("SNMP exporter remains loopback-only with owner-private file discovery",
  switch_job["metrics_path"] == "/snmp" &&
    switch_job.dig("file_sd_configs", 0, "files") == ["/etc/prometheus/soul-switch-targets.json"] &&
    switch_job.fetch("relabel_configs", []).any? { |rule| rule["replacement"] == "127.0.0.1:9116" } &&
    central.include?("prometheus-snmp-exporter") &&
    central.include?("PrivateUsers=false") && central.include?("--web.listen-address=127.0.0.1:9116"))

check.call("owner-private renderer uses bounded generic switch slots",
  renderer.include?("(1..8).filter_map") &&
    renderer.include?('SOUL_OBSERVABILITY_SWITCH_#{slot}') &&
    renderer.include?("at least one complete owner-private switch slot is required") &&
    !renderer.match?(/SOUL_FLEET_|\b(?:loom|lattice)\b/i))

alert_names = rules.fetch("groups").flat_map { |group| group.fetch("rules") }.map { |rule| rule["alert"] }
check.call("bounded alerts cover endpoint, storage, memory, host network, switch, and interface evidence",
  alert_names == %w[SoulEndpointStale SoulRootFilesystemPressure SoulMemoryPressure SoulHostNetworkErrors SoulSwitchScrapeUnavailable SoulSwitchPortErrors] &&
    rules.fetch("groups").flat_map { |group| group.fetch("rules") }.all? { |rule| rule.dig("labels", "scope") && rule["for"] })

annotation_names = dashboard.dig("annotations", "list").map { |entry| entry["name"] }
panel_titles = dashboard.fetch("panels").map { |panel| panel["title"] }
check.call("operational dashboard has reboot and maintenance overlays plus reviewed evidence panels",
  dashboard["uid"] == "soul-fleet-operations-a2" &&
    annotation_names == ["Reboots", "Maintenance lifecycle"] &&
    ["Firing bounded alerts", "Reporting switches", "Fleet resource pressure", "Host network errors and drops", "Switch interface errors", "Redacted maintenance lifecycle"].all? { |title| panel_titles.include?(title) })

check.call("journal source keeps exact units and replaces every retained message before Loki",
  alloy.include?('regex         = "soul-maintenance-fleet-status.service|soul-maintenance-resume.service"') &&
    alloy.include?('replace    = "bounded maintenance lifecycle event"') &&
    alloy.index("loki.process \"maintenance\"") < alloy.index("loki.write \"central\"") &&
    collector.include?("systemd-journal"))

public = [
  "config/fleet_observability_a2_a3.json",
  "docs/soul/FLEET_OBSERVABILITY_A2_A3_BRIEF.md",
  "deploy/observability/central/fleet-alerts.yml",
  "deploy/observability/central/fleet-operations.json",
  "deploy/observability/central/switch-targets.example.json",
  "deploy/observability/central/prometheus.yml",
  "deploy/observability/collector/config.alloy",
  "scripts/render-fleet-observability-snmp-config"
].map { |path| File.read(File.join(ROOT, path)) }.join("\n")
check.call("public A2 assets contain no owner-private fleet identity, address, or credential",
  !public.match?(/192\.168\.|\b(?:atelier|forge|foundry|warden|crucible|witness|syracuse)\b|bhones|community:\s*\S+/i))

check.call("A2 adds no notification or remediation component",
  ![prometheus, rules, dashboard, alloy].map(&:to_s).join("\n").match?(/alertmanager|smtp|webhook|pagerduty/i) &&
    !dashboard.to_s.match?(/maintenance\.device\.execute|reboot\.execute/))

exit(errors.empty? ? 0 : 1)
