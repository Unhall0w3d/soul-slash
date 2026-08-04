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

def posture_entry(agent_id:, policy_id:, offset:, genuine: true)
  {
    "raw_wazuh_result" => {
      "agent_id" => agent_id, "policy_id" => policy_id, "policy_name" => "Fixture policy #{agent_id}",
      "scan_id" => "fixture-#{agent_id}", "scan_hash" => agent_id[-1] * 64, "scanned_at" => "2026-08-03T03:05:37Z",
      "passed" => 10, "failed" => genuine ? 4 : 3, "not_applicable" => 2, "total_checks" => genuine ? 16 : 15, "score" => 62
    },
    "adapted_review" => {
      "version" => "fixture-#{agent_id}-v1", "reviewed_at" => "2026-08-03T12:00:00Z",
      "classifications" => [
        {"classification" => "verified_effective_control", "check_ids" => [offset + 1], "summary" => "Effective control verified."},
        {"classification" => "accepted_workstation_exception", "check_ids" => [offset + 2], "summary" => "Endpoint design retained."},
        {"classification" => "policy_or_parser_limitation", "check_ids" => [offset + 3], "summary" => "Policy mismatch."},
        {"classification" => "genuine_remaining_decision", "check_ids" => genuine ? [offset + 4] : [], "summary" => genuine ? "Owner decision remains." : "No decision remains."}
      ]
    }
  }
end

def fixture
  {
    "schema_version" => "soul.wazuh.compliance-postures.v2",
    "enabled" => true,
    "postures" => [
      posture_entry(agent_id: "002", policy_id: "cis_arch_linux", offset: 1000),
      posture_entry(agent_id: "001", policy_id: "sca_distro_independent_linux", offset: 2000, genuine: false)
    ]
  }
end

def legacy_fixture
  entry = posture_entry(agent_id: "002", policy_id: "cis_arch_linux", offset: 3000)
  {"schema_version" => "soul.wazuh.compliance-posture.v1", "enabled" => true}.merge(entry)
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

  check.call("two raw Wazuh results remain explicit and unaltered", data["available"] && data["raw_result_preserved"] && data["postures"].length == 2 && data["postures"].all? { |posture| posture.dig("raw_wazuh_result", "unaltered") })
  check.call("every raw failure is classified exactly once", data.dig("verification", "all_raw_failures_classified") && data.dig("summary", "reviewed_failure_count") == 7 && data.dig("summary", "raw_failed") == 7)
  check.call("agent identities and per-agent states remain separate", data.dig("verification", "agent_ids_unique") && data["postures"].map { |posture| posture.dig("raw_wazuh_result", "agent_id") } == %w[002 001] && data["postures"].map { |posture| posture["state"] } == %w[attention reviewed])
  check.call("empty resolved category is accepted only by the multi-endpoint schema", data["postures"].last.dig("adapted_review", "genuine_remaining_decision_count").zero?)
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
  invalid["postures"][0]["adapted_review"]["classifications"][1]["check_ids"] = [1001]
  File.write(manifest, JSON.pretty_generate(invalid), mode: "w")
  rejected = service.status.fetch("data")
  check.call("duplicate or incomplete classifications fail safely", !rejected["available"] && rejected["reason"].include?("unique"))

  duplicate_agent = fixture
  duplicate_agent["postures"][1]["raw_wazuh_result"]["agent_id"] = "002"
  File.write(manifest, JSON.pretty_generate(duplicate_agent), mode: "w")
  rejected_agent = service.status.fetch("data")
  check.call("duplicate agent identities fail safely", !rejected_agent["available"] && rejected_agent["reason"].include?("agent identities"))

  File.write(manifest, JSON.pretty_generate(legacy_fixture), mode: "w")
  legacy = service.status.fetch("data")
  check.call("version-one manifest remains a bounded one-entry input", legacy["available"] && legacy["postures"].length == 1 && legacy.dig("raw_wazuh_result", "agent_id") == "002")

  File.write(manifest, JSON.pretty_generate(fixture), mode: "w")
  File.chmod(0o644, manifest)
  unsafe = service.status.fetch("data")
  check.call("non-private review manifests fail safely", !unsafe["available"] && unsafe["reason"].include?("owner-private"))
end

js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard selects exact agent posture and preserves raw authority", js.include?("posture.postures") && js.include?("raw Wazuh score remains unchanged and authoritative") && js.include?("security.wazuh.posture.snapshot"))

abort("Wazuh compliance posture A4d verification failed: #{errors.join(', ')}") unless errors.empty?
puts "Wazuh compliance posture A4d verification passed."
