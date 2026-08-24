#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/conversation_observation_store"
require_relative "../lib/soul_core/memory_audit_journal_service"
require_relative "../lib/soul_core/memory_live_qualification_service"
require_relative "../lib/soul_core/memory_local_proposal_synthesizer"

Response = Struct.new(:structured, keyword_init: true) do
  def ok? = true
  def error_message = nil
  def to_h = { "provider" => "local.dev", "model" => "gpt-oss:20b", "status" => "ok", "structured_output" => true }
end

class FixtureModel
  attr_reader :calls

  def initialize(proposal)
    @proposal = proposal
    @calls = []
  end

  def chat(**arguments)
    @calls << arguments
    Response.new(structured: { "proposals" => [@proposal] })
  end
end

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Dir.mktmpdir("soul-memory-a14-") do |root|
  clock = -> { Time.utc(2026, 8, 24, 18, 0, 0) }
  observations = SoulCore::ConversationObservationStore.new(root: root, clock: clock)
  captured = observations.capture_exchange(
    user_message: { "id" => "msg-user", "chat_id" => "chat-a14", "role" => "user",
                    "content" => "The durable qualification label is Cobalt Lantern.", "created_at" => clock.call.iso8601 },
    assistant_message: { "id" => "msg-assistant", "chat_id" => "chat-a14", "role" => "assistant",
                         "content" => "I will use that project label.", "created_at" => clock.call.iso8601 },
    request_id: "request-a14", interface: "dashboard"
  )
  evidence_ids = observations.batch.map { |item| item.fetch("observation_id") }
  proposal = {
    "layer" => "project", "content" => "The durable qualification label is Cobalt Lantern.",
    "confidence" => 0.97, "evidence_observation_ids" => evidence_ids
  }
  model = FixtureModel.new(proposal)
  synthesizer = SoulCore::MemoryLocalProposalSynthesizer.new(model_client: model, root: root)
  memories = SoulCore::ConversationMemoryStore.new(root: root, clock: clock)
  audit = SoulCore::MemoryAuditJournalService.new(root: root, memory_store: memories, clock: clock)
  baseline = audit.baseline(actor: "fixture", trigger: "a14", reason: "fixture baseline", policy_version: "a14")
  service = SoulCore::MemoryLiveQualificationService.new(
    root: root, synthesizer: synthesizer, observation_store: observations,
    memory_store: memories, audit_service: audit
  )

  assert.call(captured["ok"] && captured["event_count"] == 2, "real exchange capture fixture")
  assert.call(baseline["ok"], "audit baseline")
  assert.call(service.status.dig("data", "observations", "event_count") == 2, "content-free status")

  derivation = service.derive(request_id: "a14-qualification-derive")
  assert.call(derivation["ok"] && derivation.dig("data", "derivation", "proposal_count") == 1, "bounded live derivation")
  call = model.calls.fetch(0)
  assert.call(call[:reasoning] == "low" && call[:temperature].zero? && call[:max_tokens] == 2_048, "reviewed local model settings")
  assert.call(call[:response_schema] == SoulCore::MemoryLocalProposalSynthesizer::OUTPUT_SCHEMA, "closed response schema")

  admission = service.admit(request_id: "a14-qualification-admit")
  assert.call(admission["ok"] && admission.dig("data", "admission", "decision_counts", "admitted_active") == 1, "deterministic admission")
  transaction = admission.dig("data", "admission", "rollback_references").fetch(0)
  retrieval = service.retrieve(query: "Cobalt Lantern")
  assert.call(retrieval["ok"] && retrieval.dig("data", "retrieval", "count") == 1, "ordinary retrieval proof")
  assert.call(!JSON.generate(retrieval).include?("Cobalt Lantern"), "retrieval receipt is content-free")

  rollback = service.rollback(transaction_id: transaction)
  assert.call(rollback["ok"] && rollback.dig("data", "rollback", "event_count").to_i >= 1, "transaction compensation")
  after = service.retrieve(query: "Cobalt Lantern")
  assert.call(after["ok"] && after.dig("data", "retrieval", "abstained"), "compensated memory leaves retrieval")
  assert.call(audit.verify["ok"], "audit remains valid after compensation")
  assert.call(service.derive(request_id: "a14-qualification-derive").dig("data", "derivation", "idempotent"), "derivation replay is idempotent")
  assert.call(service.admit(request_id: "a14-qualification-admit").dig("data", "admission", "idempotent"), "admission replay is idempotent")
  assert.call(!service.rollback(transaction_id: "memory-admit:mpr_unrelated")["ok"], "unrelated compensation is rejected")
end

command_source = File.read(File.join(__dir__, "soul-memory-live-qualification"))
assert.call(command_source.include?("EnvLoader.load(File.join(root, \".env\"))"), "live command loads reviewed local configuration")

puts "Memory live qualification A14 verifier passed (#{checks} checks)."
