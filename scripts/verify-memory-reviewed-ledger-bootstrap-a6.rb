#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/reviewed_memory_ledger_bootstrap_service"

checks = 0
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

fixture = lambda do |root|
  directory = File.join(root, "Soul/private/memory")
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "approved_rules.md"), "# Rules\n\n- Keep mutation bounded.\n- Preserve provenance.\n")
  File.write(File.join(directory, "approved_lessons.md"), "# Lessons\n\n- Evidence precedes conclusions.\n")
end

Dir.mktmpdir("soul-reviewed-memory-a6") do |root|
  fixture.call(root)
  store = SoulCore::ConversationMemoryStore.new(root: root)
  service = SoulCore::ReviewedMemoryLedgerBootstrapService.new(root: root, memory_store: store)

  preview = service.preview
  check.call("preview blocks for exact human review", preview["lifecycle_state"] == "blocked_for_human_review")
  data = preview.fetch("data")
  check.call("preview is bounded and content-free", data["record_count"] == 3 && !JSON.generate(data).include?("Keep mutation"))
  check.call("preview exposes only fixed source identities", data.fetch("sources").map { |item| item["source_id"] } == %w[approved_rules approved_lessons])
  check.call("missing gate awaits input", service.execute(confirmation: "", expected_digest: "")["lifecycle_state"] == "awaiting_input")
  check.call("wrong gate is blocked", service.execute(confirmation: "wrong", expected_digest: data["expected_digest"])["lifecycle_state"] == "blocked_for_human_review")

  drift_digest = data.fetch("expected_digest")
  File.open(File.join(root, "Soul/private/memory/approved_rules.md"), "a") { |file| file.puts("- Reject drift.") }
  check.call("source drift is blocked", service.execute(confirmation: SoulCore::ReviewedMemoryLedgerBootstrapService::CONFIRMATION, expected_digest: drift_digest)["lifecycle_state"] == "blocked_for_human_review")

  fresh = service.preview.fetch("data")
  executed = service.execute(confirmation: fresh.fetch("confirmation_phrase"), expected_digest: fresh.fetch("expected_digest"))
  check.call("exact execution completes", executed["lifecycle_state"] == "complete")
  check.call("only approved semantic records are written", store.records(status: "approved").length == 4 && store.records.all? { |record| record["layer"] == "semantic" })
  check.call("each projected record has creation and approval", store.records.all? { |record| store.events(memory_id: record["id"]).map { |event| event["event"] } == %w[created approved] })
  check.call("execution response remains content-free", !JSON.generate(executed).include?("Keep mutation"))

  repeated_preview = service.preview.fetch("data")
  repeated = service.execute(confirmation: repeated_preview.fetch("confirmation_phrase"), expected_digest: repeated_preview.fetch("expected_digest"))
  check.call("repeat is idempotent", repeated["lifecycle_state"] == "complete" && repeated.dig("data", "imported_memory_ids").empty? && repeated.dig("data", "skipped_memory_ids").length == 4)

  first = store.records.first
  store.delete(first.fetch("id"), reason: "fixture conflict")
  conflict_preview = service.preview.fetch("data")
  conflict = service.execute(confirmation: conflict_preview.fetch("confirmation_phrase"), expected_digest: conflict_preview.fetch("expected_digest"))
  check.call("conflicting lifecycle blocks", conflict["lifecycle_state"] == "blocked_for_human_review" && conflict.dig("data", "conflicting_status") == "deleted")
end

Dir.mktmpdir("soul-reviewed-memory-resume-a6") do |root|
  fixture.call(root)
  store = SoulCore::ConversationMemoryStore.new(root: root)
  service = SoulCore::ReviewedMemoryLedgerBootstrapService.new(root: root, memory_store: store)
  preview = service.preview.fetch("data")
  descriptor = preview.fetch("records").first
  store.propose(
    layer: "semantic",
    content: "Keep mutation bounded.",
    source: { "kind" => "owner_reviewed_memory", "reference" => descriptor.fetch("source_id") },
    confidence: 1.0,
    metadata: { "reviewed_ledger_import_key" => descriptor.fetch("import_key") }
  )
  refreshed = service.preview.fetch("data")
  result = service.execute(confirmation: refreshed.fetch("confirmation_phrase"), expected_digest: refreshed.fetch("expected_digest"))
  check.call("interrupted candidate resumes through approval", result["lifecycle_state"] == "complete" && store.records(status: "approved").length == 3)
end

Dir.mktmpdir("soul-reviewed-memory-symlink-a6") do |root|
  fixture.call(root)
  target = File.join(root, "outside.md")
  File.write(target, "- Outside\n")
  path = File.join(root, "Soul/private/memory/approved_rules.md")
  FileUtils.rm_f(path)
  File.symlink(target, path)
  store = SoulCore::ConversationMemoryStore.new(root: root)
  service = SoulCore::ReviewedMemoryLedgerBootstrapService.new(root: root, memory_store: store)
  check.call("source symlink fails safely", service.preview["lifecycle_state"] == "failed")
end

puts "MEMORY_REVIEWED_LEDGER_BOOTSTRAP_A6=PASS (#{checks} checks)"
