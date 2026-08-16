#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
manifest = JSON.parse(File.read(File.join(ROOT, "config", "fleet_observability_deployment_a1.json")))
errors = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end

puts "Fleet observability A1 verification:"

check.call("A1 has exact authorized isolated resource profile",
  manifest["schema_version"] == "soul.fleet-observability.deployment.a1.v1" &&
    manifest["persistent_deployment_authorized"] == true &&
    manifest["central_guest"] == {
      "isolation" => "dedicated_unprivileged_linux_container",
      "cpu_cores" => 2, "memory_mib" => 3072, "swap_mib" => 512,
      "root_volume_gib" => 8, "metrics_volume_gib" => 36,
      "logs_volume_gib" => 20, "autostart" => true,
      "owner_private_identity_and_address" => true
    })

check.call("network separates one TLS application boundary from fixed SSH management",
  manifest.dig("network", "application_listener") == "https_443_only" &&
    manifest.dig("network", "management_listener") == "ssh_22_key_only_non_root_fixed_authority" &&
    manifest.dig("network", "backend_bind") == "loopback_only" &&
    manifest.dig("network", "grafana_authentication") == "required" &&
    manifest.dig("network", "ingest_authentication") == "basic_auth_over_tls" &&
    manifest.dig("network", "public_ingress") == false)

check.call("retention fits dedicated physical volumes",
  manifest.dig("retention", "metrics_time") == "30d" &&
    manifest.dig("retention", "metrics_size") == "28GB" &&
    manifest.dig("retention", "metrics_volume_max_percent") == 80 &&
    manifest.dig("retention", "logs_time") == "336h" &&
    manifest.dig("retention", "raw_telemetry_backup") == false)

check.call("pilot is metric-only until journal privacy review",
  manifest.dig("pilot", "metrics_enabled") == true &&
    manifest.dig("pilot", "journal_ingest_enabled") == false &&
    manifest.dig("pilot", "roles") == %w[operator_workstation primary_hypervisor secondary_hypervisor backup_target])

check.call("telemetry grants no operational mutation authority",
  manifest.dig("authority", "soul_query") == "none_in_a1" &&
    manifest.dig("authority", "remediation") == "none" &&
    manifest.dig("authority", "alert_mutation") == "none")

central = File.read(File.join(ROOT, "deploy", "observability", "central", "install-central.sh"))
collector = File.read(File.join(ROOT, "deploy", "observability", "collector", "install-collector.sh"))
handoff = File.read(File.join(ROOT, "deploy", "observability", "central", "finalize-credential-handoff.sh"))
alloy = File.read(File.join(ROOT, "deploy", "observability", "collector", "config.alloy"))
loki = File.read(File.join(ROOT, "deploy", "observability", "central", "loki.yml"))
caddy = File.read(File.join(ROOT, "deploy", "observability", "central", "Caddyfile.template"))
dashboard = JSON.parse(File.read(File.join(ROOT, "deploy", "observability", "central", "fleet-overview.json")))

check.call("central binaries and retention are pinned",
  central.include?("LOKI_VERSION=v3.7.6") &&
    central.include?("LOKI_ZIP_SHA256=09d213") &&
    central.include?("--no-install-recommends") &&
    central.include?("PrivateUsers=false") &&
    central.include?("systemctl restart prometheus prometheus-snmp-exporter loki grafana-server caddy") &&
    central.include?("admin reset-admin-password") &&
    central.include?("--storage.tsdb.retention.time=30d") &&
    central.include?("--storage.tsdb.retention.size=28GB") &&
    loki.include?("retention_period: 336h"))

check.call("only Caddy is designed for application LAN exposure",
  central.include?("--web.listen-address=127.0.0.1:9090") &&
    loki.include?("http_listen_address: 127.0.0.1") &&
    loki.include?("grpc_listen_address: 127.0.0.1") &&
    central.include?("http_addr = 127.0.0.1") &&
    caddy.include?("auto_https disable_redirects") &&
    caddy.include?("tls internal") && caddy.scan(/basicauth/).length == 2)

approved_a2_journal = alloy.include?('regex         = "soul-maintenance-fleet-status.service|soul-maintenance-resume.service"') &&
  alloy.include?('replace    = "bounded maintenance lifecycle event"') &&
  alloy.scan(/loki\.source\.journal/).length == 1
check.call("collector preserves stable labels and only the exact approved A2 journal extension",
  collector.include?("ALLOY_VERSION=v1.18.1") &&
    collector.include?("ALLOY_ZIP_SHA256=fac853") &&
    collector.include?("systemctl restart alloy") &&
    alloy.include?("enable_restarts = true") &&
    %w[device_id role platform environment].all? { |label| alloy.include?(label) } &&
    approved_a2_journal &&
    !alloy.match?(/ip_address|mac_address|operator_name/))

check.call("credential handoff removes only the Grafana plaintext bootstrap",
  handoff.include?("sed -i '/^GRAFANA_/d'") &&
    handoff.include?("INGEST_USER") && handoff.include?("INGEST_PASSWORD") &&
    handoff.include?("chmod 0600") && !handoff.include?("systemctl"))

check.call("dashboard is deterministic and fleet-oriented",
  dashboard["uid"] == "soul-fleet-overview-a1" &&
    dashboard.fetch("panels").length >= 4 &&
    dashboard.fetch("panels").reject { |panel| panel["type"] == "row" }
      .all? { |panel| panel.dig("targets", 0, "expr").is_a?(String) })

role_colors = {
  "/.* · operator_workstation/" => "#00E5FF",
  "/.* · primary_hypervisor/" => "#D4AF37",
  "/.* · secondary_hypervisor/" => "#A970FF",
  "/.* · backup_target/" => "#73BF69"
}
flatten = lambda do |panels|
  panels.flat_map { |panel| [panel, *flatten.call(panel.fetch("panels", []))] }
end
time_series = flatten.call(dashboard.fetch("panels")).select { |panel| panel["type"] == "timeseries" }
check.call("device colors remain stable across every time-series panel",
  time_series.length >= 3 && time_series.all? do |panel|
    overrides = panel.dig("fieldConfig", "overrides") || []
    actual = overrides.to_h do |override|
      [override.dig("matcher", "options"), override.dig("properties", 0, "value", "fixedColor")]
    end
    overrides.all? { |override| override.dig("matcher", "id") == "byRegexp" } &&
      panel.dig("targets", 0, "legendFormat") == "{{device_id}} · {{role}}" && actual == role_colors
  end)

public_text = [
  File.join(ROOT, "config", "fleet_observability_deployment_a1.json"),
  File.join(ROOT, "docs", "soul", "FLEET_OBSERVABILITY_A1_BRIEF.md"),
  File.join(ROOT, "docs", "assessments", "FLEET_OBSERVABILITY_A1_REVIEW.md"),
  *Dir.glob(File.join(ROOT, "deploy", "observability", "**", "*"))
].select { |path| File.file?(path) }
  .map { |path| File.read(path) }.join("\n")
check.call("A1 public assets contain no owner-private fleet identity",
  !public_text.match?(/192\.168\.|\b(?:atelier|forge|foundry|warden|crucible|witness|temper)\b|bhones/i))

review = File.read(File.join(ROOT, "docs", "assessments", "FLEET_OBSERVABILITY_A1_REVIEW.md"))
check.call("human live review remains explicit",
  review.include?("Operator visual review") && review.include?("[x]"))

exit(errors.empty? ? 0 : 1)
