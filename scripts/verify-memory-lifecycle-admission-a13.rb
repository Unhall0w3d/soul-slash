#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "time"
require "fileutils"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/conversation_observation_store"
require_relative "../lib/soul_core/memory_audit_journal_service"
require_relative "../lib/soul_core/memory_lifecycle_admission_service"
require_relative "../lib/soul_core/memory_observation_derivation_service"

checks = 0
assert = lambda { |condition, label| raise("FAIL: #{label}") unless condition; checks += 1 }

Dir.mktmpdir("soul-a13-") do |root|
  tick = 0
  clock = -> { tick += 1; Time.utc(2026, 8, 24, 12, 0, tick) }
  observations = SoulCore::ConversationObservationStore.new(root: root, clock: clock)
  2.times do |index|
    receipt = observations.capture_exchange(
      user_message: { "id" => "u#{index}", "chat_id" => "chat", "role" => "user",
        "content" => index.zero? ? "I prefer concise reports." : "Project Atlas uses blue labels.", "created_at" => clock.call.iso8601(6) },
      assistant_message: { "id" => "a#{index}", "chat_id" => "chat", "role" => "assistant",
        "content" => "Understood.", "created_at" => clock.call.iso8601(6) },
      request_id: "capture#{index}", interface: "chat")
    assert.call(receipt["ok"], "observation capture")
  end
  synthesizer = lambda do |input|
    user_ids = input["observations"].select { |item| item["role"] == "user" }.map { |item| item["observation_id"] }
    assistant_id = input["observations"].find { |item| item["role"] == "assistant" }["observation_id"]
    JSON.generate("proposals" => [
      { "layer" => "preference", "content" => "The operator prefers concise reports.", "confidence" => 0.96, "evidence_observation_ids" => [user_ids.first] },
      { "layer" => "project", "content" => "Project Atlas uses blue labels.", "confidence" => 0.80, "evidence_observation_ids" => [user_ids.last] },
      { "layer" => "semantic", "content" => "The sudo password is retained.", "confidence" => 0.99, "evidence_observation_ids" => [user_ids.first] },
      { "layer" => "episodic", "content" => "An assistant acknowledged the exchange.", "confidence" => 0.99, "evidence_observation_ids" => [assistant_id] },
      { "layer" => "semantic", "content" => "A weak inference.", "confidence" => 0.40, "evidence_observation_ids" => [user_ids.first] }
    ])
  end
  derivation_path = File.join(root, "observation_derivations.jsonl")
  derivations = SoulCore::MemoryObservationDerivationService.new(root: root, observation_store: observations,
    synthesizer: synthesizer, model_identity: { "provider" => "local", "model" => "fixture", "core" => "DevCore" },
    path: derivation_path, clock: clock)
  assert.call(derivations.derive(request_id: "derive1")["ok"], "derivation succeeds")
  sequence = 0
  memories = SoulCore::ConversationMemoryStore.new(root: root, clock: clock, id_generator: -> { sequence += 1; "id#{sequence}" })
  audit = SoulCore::MemoryAuditJournalService.new(root: root, memory_store: memories, clock: clock, id_generator: -> { sequence += 1; "id#{sequence}" })
  assert.call(audit.baseline["ok"], "audit baseline")
  admissions = SoulCore::MemoryLifecycleAdmissionService.new(root: root, derivation_service: derivations,
    observation_store: observations, memory_store: memories, audit_service: audit,
    path: File.join(root, "memory_lifecycle_decisions.jsonl"), clock: clock)
  receipt = admissions.apply(request_id: "admit1")
  assert.call(receipt["ok"] && receipt["proposal_count"] == 5, "packet admitted")
  expected = { "admitted_active" => 1, "admitted_candidate" => 1, "blocked_for_human_review" => 1,
               "rejected_no_user_evidence" => 1, "rejected_low_confidence" => 1 }
  assert.call(receipt["decision_counts"] == expected, "deterministic decisions")
  assert.call(receipt["rollback_references"].length == 2 && receipt["rollback_references"].all? { |item| item.start_with?("memory-admit:mpr_") }, "content-free rollback references")
  records = memories.records(include_deleted: true)
  assert.call(records.length == 2, "only supported ordinary proposals stored")
  assert.call(records.count { |record| record["status"] == "approved" } == 1, "high confidence active")
  assert.call(records.count { |record| record["status"] == "candidate" } == 1, "medium confidence candidate")
  assert.call(records.none? { |record| record["content"].include?("password") }, "protected excluded")
  assert.call(audit.verify["ok"], "audit valid")
  assert.call(admissions.integrity["ok"], "decision journal valid")
  assert.call(receipt["content_included"] == false && !JSON.generate(receipt).include?("concise"), "receipt content-free")
  metadata = memories.events.reject { |event| event["event"] == "audit_baseline" }.map { |event| event["audit_metadata"] }
  assert.call(metadata.all? { |item| item["transaction_id"].start_with?("memory-admit:") }, "transaction scoped")
  assert.call(metadata.all? { |item| item["rollback_reference"] == item["transaction_id"] }, "rollback references")
  replay = admissions.apply(request_id: "admit1")
  assert.call(replay["ok"] && replay["idempotent"], "idempotent replay")
  assert.call(memories.records(include_deleted: true).length == 2, "replay creates no memory")
  assert.call(admissions.apply(request_id: "admit2")["no_work"], "cursor no work")
  active = memories.records(status: "approved").first
  transaction = memories.events(memory_id: active["id"]).find { |event| event["event"] == "created" }.dig("audit_metadata", "transaction_id")
  rollback = audit.rollback_transaction(transaction_id: transaction, reason: "A13 verifier compensation")
  assert.call(rollback["ok"], "admission transaction is compensatable")
  assert.call(memories.find(active["id"])["status"] == "deleted", "rollback restores pre-admission absence")
  assert.call(audit.verify["ok"], "audit valid after compensation")
  derivation_original = File.binread(derivation_path)
  File.binwrite(derivation_path, derivation_original.sub("A weak inference", "A weak tampering"))
  source_tamper = admissions.apply(request_id: "tampered_source")
  assert.call(!source_tamper["ok"], "source tamper fails before admission")
  File.binwrite(derivation_path, derivation_original)
  decision_path = File.join(root, "memory_lifecycle_decisions.jsonl")
  original = File.binread(decision_path)
  File.binwrite(decision_path, original.sub("admitted_active", "admitted_broken"))
  assert.call(!admissions.integrity["ok"], "decision tamper fails")
  File.binwrite(decision_path, original)
  missing_root = File.join(root, "missing")
  missing_memories = SoulCore::ConversationMemoryStore.new(root: missing_root)
  missing_audit = SoulCore::MemoryAuditJournalService.new(root: missing_root, memory_store: missing_memories)
  blocked = SoulCore::MemoryLifecycleAdmissionService.new(root: missing_root, derivation_service: derivations,
    observation_store: observations, memory_store: missing_memories, audit_service: missing_audit).apply(request_id: "blocked")
  assert.call(!blocked["ok"] && blocked["reason"].include?("baseline"), "baseline required")
  outside = File.join(Dir.tmpdir, "soul-a13-outside-#{Process.pid}")
  FileUtils.touch(outside)
  link = File.join(root, "linked-decisions.jsonl")
  File.symlink(outside, link)
  begin
    SoulCore::MemoryLifecycleAdmissionService.new(root: root, derivation_service: derivations,
      observation_store: observations, memory_store: memories, audit_service: audit, path: link)
    raise "FAIL: decision symlink accepted"
  rescue ArgumentError => error
    assert.call(error.message.include?("symlink"), "decision symlink rejected")
  ensure
    FileUtils.rm_f(outside)
  end
end

puts "MEMORY_LIFECYCLE_ADMISSION_A13_CHECKS=#{checks}"
