#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "yaml"

require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_evidence_store"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/conversation_security_status_service"
require_relative "../lib/soul_core/conversation_tool_catalog"
require_relative "../lib/soul_core/invocation_catalog_service"

class SecuritySourceFixture
  attr_reader :calls

  def initialize(data, method_name: :collect)
    @data = data
    @method_name = method_name
    @calls = 0
  end

  def collect
    raise "wrong fixture method" unless @method_name == :collect
    @calls += 1
    outcome
  end

  def status
    raise "wrong fixture method" unless @method_name == :status
    @calls += 1
    outcome
  end

  private

  def outcome
    { "ok" => true, "lifecycle_state" => "complete", "data" => Marshal.load(Marshal.dump(@data)), "mutation" => "none" }
  end
end

class EmptyProviderRegistry
  def configured = []
  def find(_provider_id) = nil
end

class SecurityConversationFixture
  attr_reader :calls

  def initialize(content, report)
    @content = content
    @report = report
    @calls = 0
  end

  def report
    @calls += 1
    { "ok" => true, "lifecycle_state" => "complete", "content" => @content, "report" => @report, "mutation" => "none" }
  end
end

def check(checks, label, condition)
  raise label unless condition
  checks << label
end

checks = []
clock = -> { Time.utc(2026, 8, 3, 6, 0, 0) }
health_data = {
  "available" => true,
  "state" => "healthy",
  "collected_at" => "2026-08-03T05:59:58Z",
  "last_successful_at" => "2026-08-03T05:59:58Z",
  "dashboard_url" => "https://private.example.invalid",
  "manager" => { "state" => "healthy", "active_daemons" => 10, "daemon_count" => 10 },
  "summary" => { "agent_count" => 2, "active" => 2, "disconnected" => 0, "pending" => 0, "never_connected" => 0, "unknown" => 0 }
}
alert_data = {
  "available" => true,
  "state" => "attention",
  "collected_at" => "2026-08-03T05:59:59Z",
  "last_successful_at" => "2026-08-03T05:59:59Z",
  "dashboard_url" => "https://private.example.invalid",
  "query" => { "lookback_minutes" => 1440, "minimum_level" => 7, "matching_alerts" => 314, "returned_alerts" => 100, "truncated" => true },
  "summary" => { "elevated" => 99, "high" => 1, "critical" => 0, "latest_at" => "2026-08-03T05:58:00Z" },
  "alerts" => [{ "event_id" => "secret-event-id", "rule_id" => "999", "description" => "sensitive alert description", "agent_name" => "private-agent" }]
}
posture_data = {
  "available" => true,
  "state" => "attention",
  "loaded_at" => "2026-08-03T05:59:57Z",
  "raw_result_preserved" => true,
  "postures" => [{ "raw_wazuh_result" => { "agent_id" => "001" } }, { "raw_wazuh_result" => { "agent_id" => "002" } }],
  "summary" => { "posture_count" => 2, "raw_passed" => 179, "raw_failed" => 136, "raw_not_applicable" => 12, "genuine_remaining_decision_count" => 1 }
}

health = SecuritySourceFixture.new(health_data)
alerts = SecuritySourceFixture.new(alert_data)
posture = SecuritySourceFixture.new(posture_data, method_name: :status)
service = SoulCore::ConversationSecurityStatusService.new(
  wazuh_status_service: health,
  alert_evidence_service: alerts,
  posture_service: posture,
  clock: clock
)
result = service.report
serialized = JSON.generate(result)

check(checks, "one foreground collection is made from each accepted source", health.calls == 1 && alerts.calls == 1 && posture.calls == 1)
check(checks, "high alert aggregate produces attention without claiming global security", result.dig("report", "state") == "attention" && result["content"].include?("needs attention within the checked Wazuh scope"))
check(checks, "declared query scope and bounded counts remain explicit", result["content"].include?("24h, level 7+") && result["content"].include?("314 matched") && result["content"].include?("newest 100") && result["content"].include?("result is truncated"))
check(checks, "raw and normalized event details are absent", !serialized.include?("secret-event-id") && !serialized.include?("sensitive alert description") && !serialized.include?("private-agent") && !serialized.include?("private.example"))
check(checks, "multi-endpoint posture is aggregate-only and preserves separate raw authority", result["content"].include?("2 endpoint reviews preserve their separate raw Wazuh results") && result["content"].include?("136 raw failures") && !serialized.include?("private posture explanation"))
check(checks, "ClamAV and remediation limitations are explicit", result["content"].include?("ClamAV freshness and latest scan receipts were not collected") && result["content"].include?("no remediation was performed or authorized"))

posture_attention = SoulCore::ConversationSecurityStatusService.new(
  wazuh_status_service: SecuritySourceFixture.new(health_data),
  alert_evidence_service: SecuritySourceFixture.new(alert_data.merge("state" => "healthy", "summary" => { "elevated" => 0, "high" => 0, "critical" => 0 })),
  posture_service: SecuritySourceFixture.new(posture_data, method_name: :status),
  clock: clock
).report
check(checks, "a genuine endpoint posture decision independently produces attention", posture_attention.dig("report", "state") == "attention")

partial_alerts = SecuritySourceFixture.new({ "available" => false, "state" => "unavailable", "reason" => "tunnel unavailable", "last_successful_at" => "2026-08-02T00:00:00Z" })
partial = SoulCore::ConversationSecurityStatusService.new(
  wazuh_status_service: SecuritySourceFixture.new(health_data),
  alert_evidence_service: partial_alerts,
  clock: clock
).report
check(checks, "partial evidence is reported rather than inferred healthy", partial.dig("report", "state") == "partial" && partial["content"].include?("partial Wazuh evidence") && partial["content"].include?("tunnel unavailable"))

unavailable = SoulCore::ConversationSecurityStatusService.new(
  wazuh_status_service: SecuritySourceFixture.new({ "available" => false, "state" => "unavailable", "reason" => "API unavailable" }),
  alert_evidence_service: SecuritySourceFixture.new({ "available" => false, "state" => "unavailable", "reason" => "index unavailable" }),
  clock: clock
).report
check(checks, "fully unavailable sources remain a completed honest read", unavailable["ok"] && unavailable.dig("report", "state") == "unavailable" && unavailable["content"].include?("currently unavailable"))

orchestrator = SoulCore::ConversationOrchestrator.new
status_question = orchestrator.plan(message: "How does security look?", provider_available: true)
alert_question = orchestrator.plan(message: "Are there recent security alerts?", provider_available: true)
discussion = orchestrator.plan(message: "I'm working on the security lane today.", provider_available: true)
check(checks, "natural security questions route to one deterministic tool", status_question.kind == "skill_only" && status_question.tool_ids == ["security.status"] && alert_question.tool_ids == ["security.status"])
check(checks, "topical security discussion remains conversation", discussion.kind == "direct_model" && discussion.tool_ids.empty?)
tool = SoulCore::ConversationToolCatalog.new.find("security.status")
check(checks, "tool is read-only and disables model synthesis", tool.risk_class == "read_only_network" && tool.synthesis_allowed == false)

Dir.mktmpdir("soul-security-chat-a4e-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat_id = store.create_chat(initial_title: "Security fixture").fetch("id")
  content = result.fetch("content")
  conversation = SecurityConversationFixture.new(content, result.fetch("report"))
  runtime = SoulCore::ConversationRuntime.new(
    root: root,
    store: store,
    env: {},
    registry: EmptyProviderRegistry.new,
    security_status_service: conversation
  )
  response = runtime.respond(chat_id: chat_id, message: "How does security look?")
  evidence = SoulCore::ConversationEvidenceStore.new(root: root).recent(chat_id, limit: 1).first
  evidence_json = JSON.generate(evidence)

  check(checks, "Chat returns the deterministic aggregate without a model", response.mode == "skill_only" && response.content == content && response.metadata.dig("orchestration", "tool_ids") == ["security.status"] && conversation.calls == 1)
  check(checks, "retained conversation evidence is privacy-filtered", evidence["evidence_profile"] == "security_status" && evidence.dig("source", "verification", "raw_events_returned") == false && !evidence_json.include?("sensitive alert description"))
  check(checks, "retained evidence names fields it did not collect", evidence["not_collected"].any? { |item| item.include?("ClamAV") } && evidence["not_collected"].any? { |item| item.include?("event IDs") })
end

registry = YAML.safe_load_file(File.join(__dir__, "..", "Soul", "skills", "registry.yaml"))
skill = registry.dig("skills", "security.status")
check(checks, "production skill registry exposes the bounded internal handler", skill["status"] == "available" && skill["requires_approval"] == false && skill["risk"] == "read_only_network")
invocation = SoulCore::InvocationCatalogService.new(root: File.expand_path("..", __dir__)).list(query: "security monitoring")
check(checks, "invocation catalog explains the no-remediation boundary", invocation["records"].map { |entry| entry["id"] } == ["security-status"] && invocation.dig("records", 0, "boundary").include?("remediation"))
voice_bridge = File.read(File.join(__dir__, "soul-voice-presence-bridge"))
check(checks, "Voice Presence uses ordinary Chat and actual tool metadata", voice_bridge.include?('request("chats.send"') && voice_bridge.include?('metadata", "orchestration", "tool_ids"'))

puts "Wazuh conversational security status A4e verification:"
checks.each { |label| puts "PASS: #{label}" }
puts "#{checks.length} checks passed."
