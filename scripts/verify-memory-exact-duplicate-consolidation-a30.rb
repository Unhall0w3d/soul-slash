#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/memory_audit_journal_service"
require_relative "../lib/soul_core/memory_exact_duplicate_consolidation_service"

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Dir.mktmpdir("soul-memory-a30-") do |root|
  sequence = 0
  clock = -> { Time.utc(2026, 8, 25, 12, 0, sequence) }
  store = SoulCore::ConversationMemoryStore.new(root: root, clock: clock,
    id_generator: -> { sequence += 1; format("fixture%03d", sequence) })
  audit = SoulCore::MemoryAuditJournalService.new(root: root, memory_store: store, clock: clock,
    id_generator: -> { sequence += 1; format("audit%03d", sequence) })
  audit.baseline(actor: "fixture", trigger: "test", reason: "fixture adoption", policy_version: "fixture.v1")

  create = lambda do |layer, content, confidence, metadata = {}|
    record = store.propose(layer: layer, content: content,
      source: { "kind" => "fixture", "reference" => "a30" }, confidence: confidence,
      metadata: metadata, audit_metadata: { "actor" => "fixture", "trigger" => "test",
        "reason" => "fixture", "policy_version" => "fixture.v1" })
    store.approve(record.fetch("id"), audit_metadata: { "actor" => "fixture", "trigger" => "test",
      "reason" => "fixture", "policy_version" => "fixture.v1" })
  end
  best = create.call("project", "Exact ordinary fact", 0.95)
  duplicate = create.call("project", " Exact   ordinary fact ", 0.80)
  near = create.call("project", "exact ordinary fact", 0.99)
  other_layer = create.call("semantic", "Exact ordinary fact", 0.99)
  protected = create.call("project", "Protected duplicate", 0.90, "protected" => true)
  protected_peer = create.call("project", "Protected duplicate", 0.80)

  service = SoulCore::MemoryExactDuplicateConsolidationService.new(memory_store: store, audit_service: audit, clock: clock)
  preview = service.preview
  assert.call(preview["ok"] && preview["mutation"] == "none" && preview.dig("data", "work_available"), "preview exposes bounded work without mutation")
  result = service.run(request_id: "fixture-cycle-1")
  assert.call(result["ok"] && result.dig("data", "survivor_id") == best.fetch("id"), "highest-confidence exact duplicate survives")
  assert.call(store.find(duplicate.fetch("id"))["status"] == "superseded", "one duplicate is superseded")
  assert.call(store.find(near.fetch("id"))["status"] == "approved", "case-different near duplicate remains active")
  assert.call(store.find(other_layer.fetch("id"))["status"] == "approved", "cross-layer duplicate remains active")
  assert.call(store.find(protected.fetch("id"))["status"] == "approved" && store.find(protected_peer.fetch("id"))["status"] == "approved", "protected group remains unchanged")
  assert.call(audit.verify["ok"], "canonical audit remains valid")
  assert.call(!result.to_s.include?("Exact ordinary fact") && result.dig("data", "content_included") == false, "receipt withholds memory content")
  assert.call(result.dig("data", "rollback_reference") == result.dig("data", "transaction_id"), "receipt exposes exact rollback reference")
  assert.call(store.events(memory_id: duplicate.fetch("id")).last.dig("audit_metadata", "policy_version") == SoulCore::MemoryExactDuplicateConsolidationService::POLICY_VERSION, "canonical event records policy evidence")

  replay = service.run(request_id: "fixture-cycle-1")
  assert.call(replay["ok"] && replay.dig("data", "idempotent") && replay["mutation"] == "none", "exact request replay is idempotent")

  no_work = service.run(request_id: "fixture-cycle-2")
  assert.call(no_work["ok"] && no_work.dig("data", "no_work"), "second cycle reports no ordinary exact duplicate work")
  assert.call(store.records(status: "approved").length == 5, "one invocation changes at most one record")
end

source = File.read(File.join(__dir__, "../lib/soul_core/memory_exact_duplicate_consolidation_service.rb"))
assert.call(!source.match?(/Thread\.new|systemd|Net::HTTP|TCPSocket|sleep\b/), "service adds no model, network, persistence, or background primitive")

cli = File.read(File.join(__dir__, "soul-memory-consolidate-exact"))
assert.call(cli.include?("preview") && cli.include?("run") && !cli.match?(/OptionParser|--path|--content/), "CLI exposes only the fixed preview and run surface")

puts "Memory exact-duplicate consolidation A30 passed (#{checks} checks)."
