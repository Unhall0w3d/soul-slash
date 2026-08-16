#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
manifest_path = File.join(ROOT, "config", "fleet_observability_architecture_a0.json")
brief_path = File.join(ROOT, "docs", "soul", "FLEET_OBSERVABILITY_A0_BRIEF.md")
review_path = File.join(ROOT, "docs", "assessments", "FLEET_OBSERVABILITY_A0_REVIEW.md")

errors = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end

manifest = JSON.parse(File.read(manifest_path))
serialized = JSON.generate(manifest)

puts "Fleet observability A0 verification:"

check.call(
  "architecture is explicitly planned and not deployed",
  manifest["schema_version"] == "soul.fleet-observability.architecture.a0.v1" &&
    manifest["state"] == "planned_not_deployed" &&
    manifest.dig("deployment", "persistent_deployment_authorized") == false &&
    manifest.dig("collection", "automatic_collection_authorized") == false
)

check.call(
  "selected stack has separated responsibilities",
  manifest["stack"] == {
    "endpoint_collector" => "grafana_alloy",
    "metrics_store" => "prometheus_single_node",
    "operational_log_store" => "loki_single_binary",
    "human_visualization" => "grafana",
    "security_authority" => "wazuh",
    "soul_access" => "foreground_read_only_api_projection"
  }
)

check.call(
  "deployment remains private and owner-configured",
  manifest.dig("deployment", "central_role") == "dedicated_unprivileged_linux_guest" &&
    manifest.dig("deployment", "central_host_selection") == "owner_private_configuration" &&
    manifest.dig("deployment", "network_scope") == "private_lan_only" &&
    manifest.dig("deployment", "public_ingress") == false &&
    manifest.dig("deployment", "authentication_required") == true &&
    manifest.dig("deployment", "tls_required") == true
)

required_metrics = %w[
  cpu_load_and_utilization memory_and_swap filesystem_capacity_and_inodes
  disk_io network_bytes_errors_and_drops hardware_temperature_when_available
  systemd_failed_unit_count uptime_and_boot_identity
]
check.call(
  "metrics and operational logs are allowlisted",
  required_metrics.all? { |metric| manifest.dig("collection", "metrics").include?(metric) } &&
    manifest.dig("collection", "operational_logs").length == 3
)

required_exclusions = %w[
  authentication_and_authorization_logs raw_wazuh_security_events
  shell_history_and_command_lines application_message_bodies
  soul_chats_memory_and_creative_content credentials_tokens_and_environment_values
]
check.call(
  "private content and raw security evidence are excluded",
  required_exclusions.all? { |item| manifest.dig("collection", "excluded_logs").include?(item) } &&
    manifest.dig("stack", "security_authority") == "wazuh"
)

check.call(
  "identity uses stable low-cardinality labels",
  manifest.dig("identity", "required_labels") == %w[device_id role platform environment] &&
    %w[ip_address mac_address filesystem_path operator_name].all? do |label|
      manifest.dig("identity", "forbidden_identity_labels").include?(label)
    end &&
    manifest.dig("identity", "cardinality_policy") == "bounded_allowlist_only"
)

check.call(
  "retention and backup boundaries are exact",
  manifest.dig("retention", "metrics_days") == 30 &&
    manifest.dig("retention", "operational_logs_days") == 14 &&
    manifest.dig("retention", "dedicated_volume_required") == true &&
    manifest.dig("retention", "metrics_volume_max_percent") == 80 &&
    manifest.dig("retention", "size_limit_required_before_deployment") == true &&
    manifest.dig("retention", "telemetry_backup_default") == "exclude_raw_data"
)

pilot = manifest.fetch("rollout").find { |wave| wave["wave"] == "pilot" }
check.call(
  "pilot is bounded to four core Linux roles",
  pilot && pilot["state"] == "not_deployed" &&
    pilot["device_roles"] == %w[
      operator_workstation primary_hypervisor secondary_hypervisor backup_target
    ]
)

check.call(
  "Soul summary remains future read-only normalization",
  manifest.dig("soul_contract", "future_operation") == "observability.fleet.summary" &&
    manifest.dig("soul_contract", "implemented_in_a0") == false &&
    manifest.dig("soul_contract", "raw_query_results_persisted_by_soul") == false &&
    manifest.dig("soul_contract", "bounded_normalized_summary_only") == true &&
    manifest.dig("soul_contract", "model_authored_facts") == false &&
    manifest.dig("soul_contract", "mutation_authority") == "none" &&
    manifest.dig("soul_contract", "automatic_remediation") == false
)

required_deferrals = %w[
  central_guest_creation package_or_container_installation alloy_endpoint_enrollment
  listeners_and_firewall_rules automatic_collection alert_and_notification_routing
  soul_api_adapter incident_narrator_adapter proxmox_api_metrics snmp_collection
  long_term_telemetry_backup
]
check.call(
  "persistent and broad extensions are deferred",
  required_deferrals.all? { |item| manifest.fetch("deferred").include?(item) }
)

check.call(
  "public architecture contains no private fleet identities or addresses",
  !serialized.match?(/\b(?:atelier|forge|foundry|warden|crucible|witness|temper)\b|192\.168\./i)
)

deployment_artifacts = Dir.glob(File.join(ROOT, "deploy", "observability", "**", "*"))
a1_manifest = File.join(ROOT, "config", "fleet_observability_deployment_a1.json")
check.call(
  "later deployment artifacts require the explicit A1 authority manifest",
  deployment_artifacts.empty? ||
    (File.file?(a1_manifest) && JSON.parse(File.read(a1_manifest))["persistent_deployment_authorized"] == true)
)

brief = File.read(brief_path)
review = File.read(review_path)
check.call(
  "brief and review preserve the human gate",
  brief.include?("A0 creates no guest, container, package") &&
    brief.include?("require an A1 deployment brief") &&
    review.include?("human architecture review remains pending") &&
    review.include?("A language-model evaluation cannot approve them")
)

exit(errors.empty? ? 0 : 1)
