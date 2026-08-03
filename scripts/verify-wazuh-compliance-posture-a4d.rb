#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/wazuh_compliance_posture_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def fixture
  {
    "schema_version" => "soul.wazuh.compliance-posture.v1",
    "enabled" => true,
    "raw_wazuh_result" => {
      "agent_id" => "002", "policy_id" => "cis_arch_linux", "policy_name" => "CIS Benchmark for Arch Linux",
      "scan_id" => "fixture-1", "scan_hash" => "a" * 64, "scanned_at" => "2026-08-03T03:05:37Z",
      "passed" => 59, "failed" => 4, "not_applicable" => 7, "total_checks" => 70, "score" => 45
    },
    "adapted_review" => {
      "version" => "atelier-2026.08.03-v1", "reviewed_at" => "2026-08-03T12:00:00Z",
      "classifications" => [
        {"classification" => "verified_effective_control", "check_ids" => [3003], "summary" => "Drop-in verified."},
        {"classification" => "accepted_workstation_exception", "check_ids" => [1002], "summary" => "Container routing retained."},
        {"classification" => "policy_or_parser_limitation", "check_ids" => [14002], "summary" => "Duplicate policy mismatch."},
        {"classification" => "genuine_remaining_decision", "check_ids" => [20003], "summary" => "Owner decision remains."}
      ]
    }
  }
end

puts "Wazuh compliance posture A4d verification:"
Dir.mktmpdir("soul-wazuh-posture-a4d-") do |root|
  private_root = File.join(root, "Soul", "private", "security", "wazuh")
  FileUtils.mkdir_p(private_root, mode: 0o700)
  manifest = File.join(private_root, "compliance-posture.json")
  File.write(manifest, JSON.pretty_generate(fixture), mode: "w", perm: 0o600)
  env = {"SOUL_WAZUH_POSTURE_FILE" => manifest}
  service = SoulCore::WazuhCompliancePostureService.new(root: root, process_env: env, clock: -> { Time.utc(2026, 8, 3, 13, 0, 0) })
  data = service.status.fetch("data")

  check.call("raw Wazuh result remains explicit and unaltered", data["available"] && data["raw_result_preserved"] && data.dig("raw_wazuh_result", "score") == 45 && data.dig("raw_wazuh_result", "unaltered"))
  check.call("every raw failure is classified exactly once", data.dig("verification", "all_raw_failures_classified") && data.dig("adapted_review", "reviewed_failure_count") == 4)
  check.call("classification counts remain separate", data.dig("adapted_review", "verified_effective_control_count") == 1 && data.dig("adapted_review", "genuine_remaining_decision_count") == 1)
  check.call("posture is interpretation-only and read-only", data["read_only"] && !data["remote_query"] && !data["remote_mutation"] && !data.dig("verification", "score_recalculated"))

  facade = SoulCore::ApplicationFacade.new(root: root, process_env: env, wazuh_compliance_posture_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "wazuh-posture-fixture",
    "operation" => "security.wazuh.posture.snapshot",
    "parameters" => {},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call("application contract exposes a dedicated posture snapshot", envelope["lifecycle_state"] == "complete" && envelope.dig("data", "schema_version") == SoulCore::WazuhCompliancePostureService::SCHEMA_VERSION)

  invalid = fixture
  invalid["adapted_review"]["classifications"][1]["check_ids"] = [3003]
  File.write(manifest, JSON.pretty_generate(invalid), mode: "w")
  rejected = service.status.fetch("data")
  check.call("duplicate or incomplete classifications fail safely", !rejected["available"] && rejected["reason"].include?("unique"))

  File.write(manifest, JSON.pretty_generate(fixture), mode: "w")
  File.chmod(0o644, manifest)
  unsafe = service.status.fetch("data")
  check.call("non-private review manifests fail safely", !unsafe["available"] && unsafe["reason"].include?("owner-private"))
end

js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard shows raw score beside adapted classifications", js.include?("raw CIS") && js.include?("raw Wazuh score remains unchanged and authoritative") && js.include?("security.wazuh.posture.snapshot"))

abort("Wazuh compliance posture A4d verification failed: #{errors.join(', ')}") unless errors.empty?
puts "Wazuh compliance posture A4d verification passed."
