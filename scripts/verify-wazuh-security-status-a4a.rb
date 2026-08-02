#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/wazuh_security_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class WazuhFixtureTransport
  attr_reader :calls

  def initialize(fail_auth: false)
    @fail_auth = fail_auth
    @calls = []
  end

  def call(uri:, request:, ca_certificate_path:, connect_address:, timeout_seconds:, max_response_bytes:)
    @calls << {
      "uri" => uri.to_s,
      "method" => request.method,
      "authorization" => request["Authorization"],
      "ca" => ca_certificate_path,
      "connect_address" => connect_address,
      "timeout" => timeout_seconds,
      "maximum" => max_response_bytes
    }
    return response(403, "denied") if @fail_auth && uri.path == "/security/user/authenticate"
    return response(200, "aaa.bbb.ccc") if uri.path == "/security/user/authenticate"
    return response(200, JSON.generate("error" => 0, "data" => {"title" => "Wazuh API", "api_version" => "4.12.0", "hostname" => "sentinel"})) if uri.path == "/"
    if uri.path == "/manager/status"
      return response(200, JSON.generate("error" => 0, "data" => {"affected_items" => [{"wazuh-analysisd" => "running", "wazuh-remoted" => "running"}]}))
    end
    if uri.path == "/agents"
      records = [
        {"id" => "000", "name" => "sentinel", "status" => "active"},
        {"id" => "001", "name" => "atelier", "status" => "active", "lastKeepAlive" => "2026-08-02T15:00:00Z", "version" => "Wazuh v4.12.0", "os" => {"name" => "CachyOS"}},
        {"id" => "002", "name" => "chancery", "status" => "disconnected", "lastKeepAlive" => "2026-08-02T14:58:00Z", "version" => "Wazuh v4.12.0", "os" => {"name" => "Windows 11"}}
      ]
      return response(200, JSON.generate("error" => 0, "data" => {"affected_items" => records}))
    end

    response(404, "not found")
  end

  private

  def response(code, body)
    SoulCore::WazuhSecurityStatusService::Response.new(code: code, body: body)
  end
end

def write_private(path, value)
  FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
  File.write(path, JSON.pretty_generate(value))
  File.chmod(0o600, path)
end

def request_for(operation)
  {
    "schema_version" => "soul.application.v1",
    "request_id" => "wazuh-a4a-verifier",
    "operation" => operation,
    "parameters" => {},
    "context" => {"interface" => "dashboard_test"}
  }
end

puts "Wazuh security status A4a verification:"

Dir.mktmpdir("soul-wazuh-a4a-") do |root|
  credential = File.join(root, "private", "api.json")
  certificate = File.join(root, "private", "wazuh-ca.pem")
  manifest = File.join(root, "private", "integration.json")
  write_private(credential, {"username" => "soul-reader", "password" => "fixture-password-123"})
  File.write(certificate, "fixture certificate\n")
  File.chmod(0o600, certificate)
  write_private(manifest, {
    "schema_version" => "soul.wazuh.integration.v1",
    "enabled" => true,
    "server_api_url" => "https://sentinel.test:55000",
    "dashboard_url" => "https://sentinel.test:8443",
    "credential_path" => credential,
    "ca_certificate_path" => certificate,
    "device_mappings" => [
      {"device_id" => "workstation", "agent_id" => "001"},
      {"device_id" => "chancery", "agent_id" => "002"},
      {"device_id" => "pihole", "agent_id" => "003"}
    ]
  })

  transport = WazuhFixtureTransport.new
  service = SoulCore::WazuhSecurityStatusService.new(
    root: root,
    process_env: {"SOUL_WAZUH_INTEGRATION_FILE" => manifest},
    clock: -> { Time.utc(2026, 8, 2, 15, 0, 0) },
    resolver: ->(_host) { ["192.168.124.210"] },
    transport: transport
  )
  result = service.collect
  data = result.fetch("data")
  devices = data.fetch("devices").to_h { |row| [row.fetch("device_id"), row] }

  check.call("collection is bounded, read-only, and stores only a status cache",
             result["ok"] && result["mutation"] == "status_cache" && data["read_only"] && !data["remote_mutation"] && data.dig("verification", "indexer_queried") == false)
  check.call("manager and endpoint health remain distinct from alert evidence",
             data["state"] == "attention" && data.dig("manager", "state") == "healthy" && data.dig("summary", "agent_count") == 2 && data["alert_query_available"] == false)
  check.call("exact private device mappings drive card associations",
             devices.dig("workstation", "state") == "monitored" && devices.dig("chancery", "state") == "attention" && devices.dig("pihole", "state") == "unavailable")
  check.call("only the reviewed server API endpoints are called",
             transport.calls.map { |row| [URI(row["uri"]).path, row["method"]] } == [["/security/user/authenticate", "POST"], ["/", "GET"], ["/manager/status", "GET"], ["/agents", "GET"]] &&
               transport.calls.all? { |row| row["connect_address"] == "192.168.124.210" })
  serialized = JSON.generate(result)
  check.call("credentials and bearer token never enter returned or persisted status",
             !serialized.include?("fixture-password") && !serialized.include?("aaa.bbb.ccc") && !File.read(File.join(root, "Soul", "private", "security", "wazuh", "status.json")).include?("fixture-password"))
  check.call("private snapshot is owner-only",
             (File.stat(File.join(root, "Soul", "private", "security", "wazuh", "status.json")).mode & 0o077).zero?)

  facade = SoulCore::ApplicationFacade.new(root: root, wazuh_security_status_service: service)
  envelope = facade.call(request_for("security.wazuh.snapshot"))
  check.call("application contract exposes the read-only snapshot operation",
             envelope["lifecycle_state"] == "complete" && envelope.dig("data", "schema_version") == SoulCore::WazuhSecurityStatusService::SCHEMA_VERSION)

  failed_transport = WazuhFixtureTransport.new(fail_auth: true)
  failed = SoulCore::WazuhSecurityStatusService.new(
    root: root,
    process_env: {"SOUL_WAZUH_INTEGRATION_FILE" => manifest},
    clock: -> { Time.utc(2026, 8, 2, 15, 2, 0) },
    resolver: ->(_host) { ["192.168.124.210"] },
    transport: failed_transport
  ).collect.fetch("data")
  check.call("authentication failure degrades safely and preserves the last success time",
             failed["available"] == false && failed["last_successful_at"] == "2026-08-02T15:00:00Z" && !failed["reason"].include?("denied"))

  public_result = SoulCore::WazuhSecurityStatusService.new(
    root: root,
    process_env: {"SOUL_WAZUH_INTEGRATION_FILE" => manifest},
    resolver: ->(_host) { ["8.8.8.8"] },
    transport: transport
  ).collect.fetch("data")
  check.call("public DNS resolution is rejected before any API call", public_result["available"] == false && public_result["reason"].include?("private IPv4"))
end

abort("Wazuh security status A4a verification failed: #{errors.join(', ')}") unless errors.empty?

puts "Wazuh security status A4a verification passed."
