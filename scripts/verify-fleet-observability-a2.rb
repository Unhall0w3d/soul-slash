#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
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
overview = JSON.parse(File.read(File.join(ROOT, "deploy", "observability", "central", "fleet-overview.json")))
alloy = File.read(File.join(ROOT, "deploy", "observability", "collector", "config.alloy"))
central = File.read(File.join(ROOT, "deploy", "observability", "central", "install-central.sh"))
collector = File.read(File.join(ROOT, "deploy", "observability", "collector", "install-collector.sh"))
renderer = File.read(File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"))

check.call("manifest preserves the read-only A2 boundary",
  manifest.dig("a2", "notifications") == false && manifest.dig("a2", "remediation") == false &&
    manifest["mutation_authority"] == "none")

jobs = prometheus.fetch("scrape_configs").to_h { |job| [job.fetch("job_name"), job] }
switch_job = jobs.fetch("switch_interfaces", {})
linux_host_job = jobs.fetch("linux_host_snmp", {})
check.call("SNMP exporter remains loopback-only with owner-private file discovery",
  switch_job["metrics_path"] == "/snmp" &&
    switch_job.dig("file_sd_configs", 0, "files") == ["/etc/prometheus/soul-switch-targets.json"] &&
    switch_job.fetch("relabel_configs", []).any? { |rule| rule["replacement"] == "127.0.0.1:9116" } &&
    central.include?("prometheus-snmp-exporter") &&
    central.include?("PrivateUsers=false") && central.include?("--web.listen-address=127.0.0.1:9116"))

check.call("Linux host SNMP uses a separate owner-private target lane",
  linux_host_job["metrics_path"] == "/snmp" &&
    linux_host_job.dig("params", "module") == ["linux_host"] &&
    linux_host_job.dig("file_sd_configs", 0, "files") == ["/etc/prometheus/soul-linux-snmp-targets.json"] &&
    linux_host_job.fetch("relabel_configs", []).any? { |rule| rule["replacement"] == "127.0.0.1:9116" })

linux_host_row = overview.fetch("panels").find { |panel| panel["title"] == "Linux-host SNMP detail" }
linux_host_panels = linux_host_row&.fetch("panels", []) || []
linux_host_expressions = linux_host_panels.flat_map { |panel| panel.fetch("targets", []).map { |target| target["expr"].to_s } }
check.call("Fleet Overview keeps reusable Linux host SNMP evidence in one collapsed detail row",
  linux_host_row&.fetch("collapsed") == true &&
    linux_host_panels.map { |panel| panel["title"] } == [
      "SNMP scrape health", "SNMP processor load", "SNMP physical memory used",
      "SNMP filesystem used", "SNMP temperature sensors", "SNMP physical-disk throughput"
    ] &&
    linux_host_expressions.all? { |expression| expression.include?('job="linux_host_snmp"') } &&
    %w[hrProcessorLoad memAvailReal memTotalReal dskPercent dskPath lmTempSensorsValue lmTempSensorsDevice diskIONReadX diskIONWrittenX diskIODevice].all? do |metric|
      linux_host_expressions.any? { |expression| expression.include?(metric) }
    end &&
    !linux_host_expressions.join("\n").match?(/\b(?:atelier|forge|foundry|crucible)\b|192\.168\./i))

check.call("owner-private renderer uses bounded generic switch slots",
  renderer.include?("(1..8).filter_map") &&
    renderer.include?('SOUL_OBSERVABILITY_SWITCH_#{slot}') &&
    renderer.include?("at least one complete owner-private switch slot is required") &&
    !renderer.match?(/SOUL_FLEET_|\b(?:loom|lattice)\b/i))

Dir.mktmpdir("soul-snmp-renderer") do |directory|
  env_path = File.join(directory, "private.env")
  upstream_path = File.join(directory, "upstream.yml")
  linux_module_path = File.join(directory, "linux.yml")
  output_path = File.join(directory, "output")
  Dir.mkdir(output_path)
  File.write(env_path, <<~ENV)
    SOUL_OBSERVABILITY_SWITCH_1_ID=switch-a
    SOUL_OBSERVABILITY_SWITCH_1_ADDRESS=switch-a.example.test
    SOUL_OBSERVABILITY_SWITCH_1_SNMP_COMMUNITY=fixture-switch-secret
    SOUL_OBSERVABILITY_LINUX_HOST_1_ID=host-a
    SOUL_OBSERVABILITY_LINUX_HOST_1_ADDRESS=host-a.example.test
    SOUL_OBSERVABILITY_LINUX_HOST_1_SNMP_COMMUNITY=fixture-host-secret
    SOUL_OBSERVABILITY_LINUX_HOST_1_ROLE=operator_workstation
  ENV
  File.chmod(0o600, env_path)
  File.write(upstream_path, YAML.dump({"modules" => {"if_mib" => {"walk" => ["1.3.6.1.2.1.2"]}}}))
  File.write(linux_module_path, YAML.dump({"modules" => {"linux_host" => {"walk" => ["1.3.6.1.4.1.2021.4"]}}}))
  stdout, stderr, status = Open3.capture3(
    File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"),
    env_path, upstream_path, output_path, linux_module_path
  )
  rendered_snmp = YAML.safe_load_file(File.join(output_path, "soul-snmp.yml"), aliases: false)
  rendered_switches = JSON.parse(File.read(File.join(output_path, "soul-switch-targets.json")))
  rendered_hosts = JSON.parse(File.read(File.join(output_path, "soul-linux-snmp-targets.json")))
  modes = Dir.children(output_path).to_h { |name| [name, File.stat(File.join(output_path, name)).mode & 0o777] }
  check.call("renderer combines generic switch and Linux host inputs without printing credentials",
    status.success? && stderr.empty? &&
      !stdout.include?("fixture-switch-secret") && !stdout.include?("fixture-host-secret") &&
      rendered_snmp.fetch("auths").keys == %w[switch_1_v2 linux_host_1_v2] &&
      rendered_snmp.fetch("modules").keys == %w[if_mib linux_host] &&
      rendered_switches.dig(0, "labels", "role") == "managed_switch" &&
      rendered_hosts.dig(0, "labels", "role") == "operator_workstation" &&
      modes.values.all? { |mode| mode == 0o600 })
  before = Dir.children(output_path).to_h { |name| [name, File.binread(File.join(output_path, name))] }
  original_env = File.read(env_path)
  File.write(env_path, original_env.sub("fixture-switch-secret", "seven77"))
  _, seven_error, seven_result = Open3.capture3(
    File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"),
    env_path, upstream_path, output_path, linux_module_path
  )
  check.call("renderer accepts the approved seven-character switch community boundary",
    seven_result.success? && seven_error.empty?)
  seven_outputs = Dir.children(output_path).to_h { |name| [name, File.binread(File.join(output_path, name))] }
  File.write(env_path, original_env.sub("fixture-switch-secret", "six666"))
  _, short_secret_error, short_secret_result = Open3.capture3(
    File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"),
    env_path, upstream_path, output_path, linux_module_path
  )
  check.call("renderer rejects a six-character switch community before writing output",
    !short_secret_result.success? && short_secret_error.include?("switch-a community is invalid") &&
      seven_outputs.all? { |name, content| File.binread(File.join(output_path, name)) == content })
  File.write(env_path, original_env)
  _, restore_error, restore_result = Open3.capture3(
    File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"),
    env_path, upstream_path, output_path, linux_module_path
  )
  check.call("renderer restores the original fixture after boundary checks",
    restore_result.success? && restore_error.empty? &&
      before.all? { |name, content| File.binread(File.join(output_path, name)) == content })
  File.write(env_path, File.readlines(env_path).reject { |line| line.start_with?("SOUL_OBSERVABILITY_LINUX_HOST_") }.join)
  _, refusal, refused = Open3.capture3(
    File.join(ROOT, "scripts", "render-fleet-observability-snmp-config"), env_path, upstream_path, output_path
  )
  check.call("switch-only rerender refuses host loss before writing any output",
    !refused.success? && refusal.include?("remove existing Linux hosts") &&
      before.all? { |name, content| File.binread(File.join(output_path, name)) == content })
end

alert_names = rules.fetch("groups").flat_map { |group| group.fetch("rules") }.map { |rule| rule["alert"] }
check.call("bounded alerts cover endpoint, storage, memory, host network, switch, and interface evidence",
  alert_names == %w[SoulEndpointStale SoulRootFilesystemPressure SoulMemoryPressure SoulHostNetworkErrors SoulSwitchScrapeUnavailable SoulSwitchPortErrors] &&
    rules.fetch("groups").flat_map { |group| group.fetch("rules") }.all? { |rule| rule.dig("labels", "scope") && rule["for"] })

annotation_names = dashboard.dig("annotations", "list").map { |entry| entry["name"] }
panel_titles = dashboard.fetch("panels").map { |panel| panel["title"] }
check.call("operational dashboard has reboot and maintenance overlays plus reviewed evidence panels",
  dashboard["uid"] == "soul-fleet-operations-a2" &&
    annotation_names == ["Reboots", "Maintenance lifecycle"] &&
    ["Firing bounded alerts", "Reporting switches", "Fleet resource pressure", "Host interface faults and receive discards", "Switch interface errors", "Redacted maintenance lifecycle"].all? { |title| panel_titles.include?(title) })

host_network = dashboard.fetch("panels").find { |panel| panel["title"] == "Host interface faults and receive discards" }
check.call("host interface panel separates errors, transmit drops, and informational receive discards",
  host_network&.fetch("targets", [])&.map { |target| target["legendFormat"] } == [
    "{{device_id}} · errors",
    "{{device_id}} · transmit drops (attention)",
    "{{device_id}} · receive discards (informational)"
  ] && host_network["description"].include?("link-local control traffic"))

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
  "deploy/observability/central/linux-host-generator.yml",
  "deploy/observability/collector/config.alloy",
  "scripts/render-fleet-observability-snmp-config"
].map { |path| File.read(File.join(ROOT, path)) }.join("\n")
check.call("public A2 assets contain no owner-private fleet identity, address, or credential",
  !public.match?(/192\.168\.|\b(?:atelier|forge|foundry|warden|crucible|witness|syracuse)\b|bhones|community:\s*\S+/i))

check.call("A2 adds no notification or remediation component",
  ![prometheus, rules, dashboard, alloy].map(&:to_s).join("\n").match?(/alertmanager|smtp|webhook|pagerduty/i) &&
    !dashboard.to_s.match?(/maintenance\.device\.execute|reboot\.execute/))

exit(errors.empty? ? 0 : 1)
