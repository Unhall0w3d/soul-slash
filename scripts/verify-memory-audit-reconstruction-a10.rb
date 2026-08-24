#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/memory_audit_journal_service"

checks = 0
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Dir.mktmpdir("soul-memory-audit-a10") do |root|
  clock = -> { Time.utc(2026, 8, 23, 12, 0, 0) }
  sequence = 0
  store = SoulCore::ConversationMemoryStore.new(
    root: root,
    clock: clock,
    id_generator: -> { sequence += 1; format("fixture%02d", sequence) }
  )
  historical = store.propose(layer: "project", content: "historical fixture", source: "fixture", confidence: 0.8)
  ledger = store.path
  before = File.binread(ledger)
  service = SoulCore::MemoryAuditJournalService.new(root: root, memory_store: store, clock: clock, id_generator: -> { sequence += 1; format("audit%02d", sequence) })

  baseline = service.baseline(audit_metadata: { "transaction_id" => "tx-a10", "actor" => "fixture", "trigger" => "test", "reason" => "baseline", "policy_version" => "a10" })
  check.call("populated baseline completes", baseline["ok"] && baseline["pre_baseline_byte_count"] == before.bytesize)
  check.call("baseline preserves historical bytes", File.binread(ledger).start_with?(before))
  check.call("empty baseline completes", begin
    Dir.mktmpdir("soul-memory-audit-a10-empty") do |empty_root|
      empty_store = SoulCore::ConversationMemoryStore.new(root: empty_root)
      SoulCore::MemoryAuditJournalService.new(root: empty_root, memory_store: empty_store).baseline["ok"]
    end
  end)
  repeat = service.baseline
  check.call("baseline is idempotent", repeat["ok"] && repeat["idempotent"] && File.binread(ledger).start_with?(before))

  created = store.propose(layer: "preference", content: "bounded audit fixture", source: "fixture", confidence: 1.0, audit_metadata: { "transaction_id" => "tx-created", "actor" => "operator", "reason" => "fixture proposal" })
  created_event_id = store.events(memory_id: created["id"]).last.fetch("event_id")
  store.approve(created["id"], audit_metadata: { "transaction_id" => "tx-approval", "actor" => "reviewer", "reason" => "fixture approval" })
  approval_event = store.events(memory_id: created["id"]).last
  check.call("supplied audit metadata is retained", approval_event.dig("audit_metadata", "actor") == "reviewer" && approval_event.dig("audit_metadata", "reason") == "fixture approval")
  metadata_probe = store.propose(
    layer: "semantic", content: "metadata fixture", source: "fixture", confidence: 0.9,
    audit_metadata: {
      "transaction_id" => "tx-metadata", "actor" => "reviewer", "trigger" => "test",
      "reason" => "metadata coverage", "policy_version" => "a10",
      "model_runtime_identity" => "fixture-runtime", "before_state_sha256" => "a" * 64,
      "after_state_sha256" => "b" * 64, "evidence_digest" => "c" * 64,
      "rollback_reference" => "fixture-reference"
    }
  )
  metadata_event = store.events(memory_id: metadata_probe["id"]).last
  check.call("optional audit metadata is retained", metadata_event.dig("audit_metadata", "model_runtime_identity") == "fixture-runtime" && metadata_event.dig("audit_metadata", "evidence_digest") == "c" * 64)
  verified = service.verify
  check.call("post-baseline chain verifies", verified["ok"] && verified.dig("checks", "chain"))
  check.call("verification receipt is content-free", !JSON.generate(verified).include?("bounded audit fixture"))
  reconstructed = service.reconstruct(event_id: created_event_id)
  check.call("event point-in-time reconstruction is content-free", reconstructed["ok"] && reconstructed["record_count"] == 2 && reconstructed.dig("records", 1, "record_id") == created["id"] && !JSON.generate(reconstructed).include?("bounded audit fixture"))
  by_time = service.reconstruct(occurred_at: "2026-08-23T12:00:00Z")
  check.call("occurred_at point-in-time reconstruction works", by_time["ok"] && by_time["record_count"] == 3)

  delete_event = store.delete(created["id"], reason: "fixture delete")
  delete_event_id = store.events(memory_id: created["id"]).last.fetch("event_id")
  rollback = service.rollback(target_event_id: delete_event_id, reason: "fixture compensation")
  check.call("rollback restores deleted lifecycle exactly", rollback["ok"] && rollback["event"] == "restored" && store.find(created["id"])["status"] == "approved" && !store.find(created["id"].to_s).key?("deleted_at"))
  check.call("rollback receipt is content-free", !JSON.generate(rollback).include?("bounded audit fixture"))
  check.call("rollback preserves target history", store.events(memory_id: created["id"]).map { |event| event["event"] } == %w[created approved deleted restored])
  check.call("rollback is idempotent", service.rollback(target_event_id: delete_event_id)["idempotent"])
  check.call("chain remains valid after rollback", service.verify["ok"])

  candidate = store.propose(layer: "episodic", content: "approval rollback fixture", source: "fixture", confidence: 0.7)
  store.approve(candidate["id"])
  approval_id = store.events(memory_id: candidate["id"]).last.fetch("event_id")
  service.rollback(target_event_id: approval_id)
  check.call("approval rollback removes stale approval fields", store.find(candidate["id"])["status"] == "candidate" && !store.find(candidate["id"].to_s).key?("approved_at"))

  replacement = store.propose(layer: "project", content: "replacement rollback fixture", source: "fixture", confidence: 0.8)
  store.approve(replacement["id"])
  store.supersede(candidate["id"], by: replacement["id"], reason: "fixture supersession")
  supersede_id = store.events(memory_id: candidate["id"]).last.fetch("event_id")
  service.rollback(target_event_id: supersede_id)
  check.call("supersession rollback removes stale replacement fields", store.find(candidate["id"])["status"] == "candidate" && !store.find(candidate["id"].to_s).key?("superseded_by"))

  stale = store.propose(layer: "episodic", content: "stale rollback fixture", source: "fixture", confidence: 0.7)
  stale_created_id = store.events(memory_id: stale["id"]).last.fetch("event_id")
  store.approve(stale["id"])
  stale_result = service.rollback(target_event_id: stale_created_id)
  check.call("single rollback rejects stale target", !stale_result["ok"] && stale_result["error"].include?("stale") && store.find(stale["id"])["status"] == "approved")

  tx_a = store.propose(layer: "project", content: "transaction fixture A", source: "fixture", confidence: 0.8, audit_metadata: { "transaction_id" => "tx-group", "actor" => "operator" })
  tx_b = store.propose(layer: "project", content: "transaction fixture B", source: "fixture", confidence: 0.8, audit_metadata: { "transaction_id" => "tx-group", "actor" => "operator" })
  tx_rollback = service.rollback_transaction(transaction_id: "tx-group", reason: "fixture transaction compensation")
  check.call("transaction rollback compensates all targets", tx_rollback["ok"] && tx_rollback["event_count"] == 2 && store.find(tx_a["id"])["status"] == "deleted" && store.find(tx_b["id"])["status"] == "deleted")
  check.call("transaction rollback is idempotent", service.rollback_transaction(transaction_id: "tx-group")["idempotent"])
  check.call("transaction rollback receipt is content-free", !JSON.generate(tx_rollback).include?("transaction fixture"))

  stale_tx = store.propose(layer: "project", content: "stale transaction fixture", source: "fixture", confidence: 0.8, audit_metadata: { "transaction_id" => "tx-stale", "actor" => "operator" })
  store.approve(stale_tx["id"])
  stale_tx_result = service.rollback_transaction(transaction_id: "tx-stale")
  check.call("transaction rollback rejects later outside event", !stale_tx_result["ok"] && stale_tx_result["error"].include?("stale"))
  check.call("materialized records exclude audit machinery", store.records(include_deleted: true).all? { |record| (record.keys & %w[previous_event_sha256 event_sha256 audit_metadata rollback_of_event_id rollback_transaction_id rollback_reason restored_snapshot]).empty? })

  batch_before = File.binread(ledger)
  begin
    store.append_audit_events([
      { "event_id" => "invalid-batch-1", "event" => "deleted", "memory_id" => tx_a["id"], "occurred_at" => "2026-08-23T12:00:00Z", "status" => "deleted" },
      { "event_id" => "invalid-batch-2", "event" => "not-an-event", "memory_id" => tx_b["id"], "occurred_at" => "2026-08-23T12:00:00Z" }
    ])
    raise "FAIL: invalid batch appended"
  rescue ArgumentError
    check.call("invalid batch leaves ledger unchanged", File.binread(ledger) == batch_before)
  end
  begin
    store.append_audit_event(
      {
        "event_id" => created_event_id,
        "event" => "deleted",
        "memory_id" => created["id"],
        "occurred_at" => "2026-08-23T12:00:00Z",
        "status" => "deleted"
      }
    )
    raise "FAIL: duplicate event id appended"
  rescue ArgumentError
    check.call("duplicate event id is rejected", File.binread(ledger) == batch_before)
  end
  begin
    store.append_audit_event(
      {
        "event_id" => "bad-timestamp",
        "event" => "deleted",
        "memory_id" => created["id"],
        "occurred_at" => "not-a-time",
        "status" => "deleted"
      }
    )
    raise "FAIL: invalid timestamp appended"
  rescue ArgumentError
    check.call("invalid event timestamp is rejected", File.binread(ledger) == batch_before)
  end

  original = File.binread(ledger)
  File.open(ledger, "r+b") do |file|
    file.seek(original.index("historical fixture"))
    file.write("tampered fixture")
  end
  check.call("tampering fails closed", !service.verify["ok"])
  File.binwrite(ledger, original)
  check.call("restored fixture verifies", service.verify["ok"])
  lines = original.lines
  baseline_line = lines.index { |line| line.include?("\"event\":\"audit_baseline\"") }
  if baseline_line && lines.length > baseline_line + 2
    File.write(ledger, (lines[0..baseline_line] + lines[(baseline_line + 2)..]).join)
    check.call("broken-chain truncation fails closed", !service.verify["ok"])
    File.binwrite(ledger, original)
  end
  File.binwrite(ledger, original.lines[0...-1].join)
  check.call("clean suffix removal is not falsely claimed detectable", service.verify["ok"])
  File.binwrite(ledger, original)
  File.binwrite(ledger, File.binread(ledger).sub(/\n\z/, ""))
  check.call("partial final line fails closed", !service.verify["ok"])
end

Dir.mktmpdir("soul-memory-audit-a10-safety") do |root|
  outside = File.join(root, "outside.jsonl")
  File.write(outside, "{}\n")
  symlink = File.join(root, "ledger.jsonl")
  File.symlink(outside, symlink)
  service = SoulCore::MemoryAuditJournalService.new(root: root, path: symlink)
  check.call("symlinked ledger fails closed", !service.verify["ok"] && !service.baseline["ok"])
  escaped = SoulCore::MemoryAuditJournalService.new(root: root, path: File.join(root, "..", "outside.jsonl"))
  check.call("path escape fails closed", !escaped.verify["ok"])
end

Dir.mktmpdir("soul-memory-audit-a10-malformed") do |root|
  path = File.join(root, "ledger.jsonl")
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "not json\n")
  service = SoulCore::MemoryAuditJournalService.new(root: root, path: path)
  check.call("malformed JSON fails closed", !service.verify["ok"] && !service.baseline["ok"])
end

Dir.mktmpdir("soul-memory-audit-a10-store-safety") do |root|
  ledger = File.join(root, "ledger.jsonl")
  File.write(ledger, "not json\n")
  store = SoulCore::ConversationMemoryStore.new(root: root, path: ledger, create: false)
  begin
    store.append_audit_baseline
    raise "FAIL: direct baseline accepted malformed JSON"
  rescue ArgumentError
    checks += 1
  end
  malformed_append = File.join(root, "malformed-before-baseline.jsonl")
  File.write(malformed_append, "not json\n")
  malformed_store = SoulCore::ConversationMemoryStore.new(root: root, path: malformed_append, create: false)
  begin
    malformed_store.propose(layer: "project", content: "blocked malformed append", source: "fixture", confidence: 0.5)
    raise "FAIL: malformed legacy append was accepted"
  rescue ArgumentError
    checks += 1
  end
  File.write(ledger, "{}\n")
  store.append_audit_baseline
  original = File.binread(ledger)
  File.binwrite(ledger, original.sub("{}\n", "{\"tampered\":true}\n"))
  begin
    store.propose(layer: "project", content: "blocked append", source: "fixture", confidence: 0.5)
    raise "FAIL: append accepted baseline prefix drift"
  rescue ArgumentError
    checks += 1
  end
end

Dir.mktmpdir("soul-memory-audit-a10-protected") do |root|
  store = SoulCore::ConversationMemoryStore.new(root: root)
  protected_record = store.propose(layer: "project", content: "protected fixture", source: "fixture", confidence: 1.0, metadata: { "protected" => true })
  service = SoulCore::MemoryAuditJournalService.new(root: root, memory_store: store)
  service.baseline
  target_id = store.events(memory_id: protected_record["id"]).last.fetch("event_id")
  protected_result = service.rollback(target_event_id: target_id)
  check.call("protected rollback is rejected", !protected_result["ok"] && protected_result["error"].include?("protected"))
end

puts "MEMORY_AUDIT_RECONSTRUCTION_A10=PASS (#{checks} checks)"
