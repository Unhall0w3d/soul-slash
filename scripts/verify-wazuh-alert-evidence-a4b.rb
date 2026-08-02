#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/wazuh_alert_evidence_service"
require_relative "../lib/soul_core/application_facade"

def check(label, condition)
  raise "FAIL: #{label}" unless condition
  puts "PASS: #{label}"
end

class FixtureTransport
  attr_reader :requests

  def initialize(payload:, status: 200)
    @payload = payload
    @status = status
    @requests = []
  end

  def call(**request)
    @requests << request
    SoulCore::WazuhAlertEvidenceService::Response.new(code: @status, body: JSON.generate(@payload))
  end
end

def fixture_payload
  {
    "hits" => {
      "total" => {"value" => 3, "relation" => "eq"},
      "hits" => [
        {"_id" => "raw-critical-id", "_source" => {"timestamp" => "2026-08-02T19:02:03.000Z", "rule" => {"level" => 13, "id" => "100003", "description" => "Critical fixture"}, "agent" => {"id" => "002", "name" => "Atelier"}}},
        {"_id" => "raw-high-id", "_source" => {"timestamp" => "2026-08-02T19:01:03.000Z", "rule" => {"level" => 10, "id" => "100002", "description" => "High fixture"}, "agent" => {"id" => "001", "name" => "crucible"}}},
        {"_id" => "raw-elevated-id", "_source" => {"timestamp" => "2026-08-02T19:00:03.000Z", "rule" => {"level" => 7, "id" => "100001", "description" => "Elevated fixture"}, "agent" => {"id" => "002", "name" => "Atelier"}}}
      ]
    }
  }
end

Dir.mktmpdir("soul-wazuh-alert-a4b-") do |root|
  private_root = File.join(root, "Soul", "private", "security", "wazuh")
  Dir.mkdir(File.join(root, "Soul"), 0o700)
  Dir.mkdir(File.join(root, "Soul", "private"), 0o700)
  Dir.mkdir(File.join(root, "Soul", "private", "security"), 0o700)
  Dir.mkdir(private_root, 0o700)
  credential = File.join(private_root, "indexer-reader.json")
  certificate = File.join(private_root, "indexer-ca.pem")
  manifest = File.join(private_root, "alerts-integration.json")
  File.write(credential, JSON.generate("username" => "fixture-reader", "password" => "fixture-password-long"), mode: "w", perm: 0o600)
  File.write(certificate, "fixture certificate", mode: "w", perm: 0o600)
  File.write(manifest, JSON.pretty_generate(
    "schema_version" => "soul.wazuh.alerts.integration.v1",
    "enabled" => true,
    "indexer_url" => "https://127.0.0.1:49200",
    "dashboard_url" => "https://vigil.herz.soul",
    "credential_path" => credential,
    "ca_certificate_path" => certificate,
    "ssh_alias" => "vigil-alerts",
    "minimum_level" => 7,
    "maximum_alerts" => 100,
    "lookback_minutes" => 60,
    "voice_notifications" => {"enabled" => true, "minimum_level" => 10, "cooldown_seconds" => 900, "lookback_minutes" => 1440}
  ), mode: "w", perm: 0o600)

  transport = FixtureTransport.new(payload: fixture_payload)
  tunnel_calls = []
  tunnel = lambda do |config, &block|
    tunnel_calls << config.slice("indexer_url", "local_port", "ssh_alias")
    block.call
  end
  service = SoulCore::WazuhAlertEvidenceService.new(
    root: root,
    process_env: {"SOUL_WAZUH_ALERTS_INTEGRATION_FILE" => manifest},
    clock: -> { Time.utc(2026, 8, 2, 19, 3, 0) },
    transport: transport,
    tunnel: tunnel
  )
  result = service.collect
  data = result.fetch("data")
  check("collection uses one loopback SSH tunnel", tunnel_calls == [{"indexer_url" => "https://127.0.0.1:49200", "local_port" => 49_200, "ssh_alias" => "vigil-alerts"}])
  check("collection is normalized and read-only", data.values_at("available", "read_only", "remote_mutation") == [true, true, false] && data.dig("verification", "write_operation_available") == false)
  check("bounded severity summary is correct", data.fetch("summary").values_at("alert_count", "elevated", "high", "critical") == [3, 1, 1, 1])
  check("raw alert identifiers and credentials are excluded", !JSON.generate(data).include?("raw-critical-id") && !JSON.generate(data).include?("fixture-password-long") && data.fetch("alerts").all? { |alert| alert.fetch("event_id").match?(/\A[a-f0-9]{64}\z/) })
  request = transport.requests.fetch(0)
  body = JSON.parse(request.fetch(:request).body)
  check("query is an exact bounded read-only search", request.fetch(:request).method == "POST" && request.fetch(:uri).request_uri.start_with?(SoulCore::WazuhAlertEvidenceService::SEARCH_PATH) && body.fetch("size") == 100 && body.fetch("_source") == SoulCore::WazuhAlertEvidenceService::SOURCE_FIELDS)
  check("query applies exact time and level bounds", body.dig("query", "bool", "filter", 0, "range", "timestamp", "gte") == "now-60m" && body.dig("query", "bool", "filter", 1, "range", "rule.level", "gte") == 7)
  snapshot_path = File.join(private_root, "alerts.json")
  check("alert snapshot is owner-only", File.file?(snapshot_path) && (File.stat(snapshot_path).mode & 0o077).zero?)
  snapshot = service.snapshot.fetch("data")
  check("snapshot preserves normalized evidence", snapshot.fetch("source") == "persisted_wazuh_alert_snapshot" && snapshot.fetch("alerts").length == 3)
  facade = SoulCore::ApplicationFacade.new(root: root, wazuh_alert_evidence_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "wazuh-alert-a4b-fixture",
    "operation" => "security.wazuh.alerts.snapshot",
    "parameters" => {},
    "context" => {"interface" => "dashboard_test"}
  })
  check("application contract exposes only read-only alert operations", envelope.fetch("lifecycle_state") == "complete" && envelope.dig("data", "source") == "persisted_wazuh_alert_snapshot")
  notification = service.notification_candidates.fetch("data")
  notification_request = transport.requests.fetch(1)
  notification_body = JSON.parse(notification_request.fetch(:request).body)
  check("notification candidates use an independent high-priority-only bound", notification.fetch("purpose") == "durable_notification_candidates" && notification_body.fetch("size") == 256 && notification_body.dig("query", "bool", "filter", 1, "range", "rule.level", "gte") == 10)

  failed_transport = FixtureTransport.new(payload: {}, status: 403)
  failed = SoulCore::WazuhAlertEvidenceService.new(
    root: root,
    process_env: {"SOUL_WAZUH_ALERTS_INTEGRATION_FILE" => manifest},
    clock: -> { Time.utc(2026, 8, 2, 19, 4, 0) },
    transport: failed_transport,
    tunnel: tunnel
  ).collect.fetch("data")
  check("authorization failure degrades safely", failed.fetch("available") == false && failed.fetch("last_successful_at") == "2026-08-02T19:03:00Z" && failed.fetch("alerts").empty?)

  File.chmod(0o600, manifest)
  invalid = JSON.parse(File.read(manifest)).merge("indexer_url" => "https://192.168.124.9:9200")
  File.write(manifest, JSON.generate(invalid), mode: "w")
  rejected = SoulCore::WazuhAlertEvidenceService.new(root: root, process_env: {"SOUL_WAZUH_ALERTS_INTEGRATION_FILE" => manifest}, transport: transport, tunnel: tunnel).collect.fetch("data")
  check("non-loopback indexer origins are rejected", rejected.fetch("available") == false && rejected.fetch("reason").include?("loopback HTTPS origin"))
end

puts "Wazuh alert evidence A4b verification complete."
