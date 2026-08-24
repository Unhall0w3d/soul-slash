#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_observation_store"
require_relative "../lib/soul_core/memory_historical_chat_backfill_service"

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Dir.mktmpdir("soul-memory-a15-") do |root|
  chats = SoulCore::ChatStore.new(root: root)
  observations = SoulCore::ConversationObservationStore.new(root: root)
  retained = chats.create_chat(initial_title: "Already retained")
  retained_user = chats.add_message(retained.fetch("id"), role: "user", content: "Existing private fact")
  retained_assistant = chats.add_message(retained.fetch("id"), role: "assistant", content: "Existing response")
  observations.capture_exchange(user_message: retained_user, assistant_message: retained_assistant,
    request_id: "existing-request", interface: "dashboard")

  archived = chats.create_chat(initial_title: "Archived history")
  2.times do |index|
    chats.add_message(archived.fetch("id"), role: "user", content: "Private historical fact #{index}")
    chats.add_message(archived.fetch("id"), role: "assistant", content: "Private historical answer #{index}")
  end
  chats.archive(archived.fetch("id"))
  incomplete = chats.create_chat(initial_title: "Incomplete")
  chats.add_message(incomplete.fetch("id"), role: "user", content: "Unanswered private question")

  service = SoulCore::MemoryHistoricalChatBackfillService.new(root: root, chat_store: chats, observation_store: observations)
  preview = service.preview
  assert.call(preview["ok"] && preview.dig("data", "backfill", "exchange_count") == 2, "preview selects only uncaptured complete exchanges")
  assert.call(preview.dig("data", "backfill", "chat_count") == 1, "archived chat remains eligible")
  assert.call(preview.dig("data", "confirmation_phrase") == SoulCore::MemoryHistoricalChatBackfillService::CONFIRMATION, "preview requires exact confirmation")
  assert.call(!JSON.generate(preview).include?("Private historical"), "preview receipt contains no chat content")
  wrong = service.execute(confirmation: "BACKFILL", expected_digest: preview.dig("data", "expected_digest"))
  assert.call(!wrong["ok"] && wrong["lifecycle_state"] == "awaiting_input", "wrong confirmation cannot mutate")

  chats.add_message(incomplete.fetch("id"), role: "assistant", content: "Late historical response")
  stale = service.execute(confirmation: SoulCore::MemoryHistoricalChatBackfillService::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest"))
  assert.call(!stale["ok"] && stale["lifecycle_state"] == "blocked_for_human_review", "changed scope blocks stale execution")
  fresh = service.preview
  executed = service.execute(confirmation: fresh.dig("data", "confirmation_phrase"), expected_digest: fresh.dig("data", "expected_digest"))
  assert.call(executed["ok"] && executed.dig("data", "backfill", "captured_exchanges") == 3, "exact reviewed batch appends source observations")
  assert.call(executed.dig("data", "backfill", "message_count") == 6, "execute reports bounded message count")
  assert.call(!JSON.generate(executed).include?("Private historical"), "execute receipt contains no chat content")
  assert.call(observations.integrity["event_count"] == 8, "existing and backfilled observations share one valid chain")
  empty = service.preview
  assert.call(empty["ok"] && empty.dig("data", "no_work") && !empty.dig("data", "confirmation_required"), "completed backfill is resumable and reports no work")
end

Dir.mktmpdir("soul-memory-a15-symlink-") do |root|
  chats = SoulCore::ChatStore.new(root: root)
  chat = chats.create_chat(initial_title: "Unsafe")
  transcript = File.join(chats.root, "#{chat.fetch('id')}.jsonl")
  outside = File.join(root, "outside.jsonl")
  File.write(outside, "")
  File.delete(transcript)
  File.symlink(outside, transcript)
  result = SoulCore::MemoryHistoricalChatBackfillService.new(root: root, chat_store: chats).preview
  assert.call(!result["ok"] && result["lifecycle_state"] == "failed", "symlinked transcript fails closed")
end

source = File.read(File.join(__dir__, "../lib/soul_core/memory_historical_chat_backfill_service.rb"))
assert.call(!source.match?(/setInterval|setTimeout|requestAnimationFrame|systemd|cron|Thread\.new|fork\s*\(/), "implementation adds no background execution")
assert.call(source.include?("MAX_CHATS = 25") && source.include?("MAX_CHAT_RECORDS = 500") && source.include?("MAX_EXCHANGES = 50"), "foreground batch is explicitly bounded")

puts "MEMORY_HISTORICAL_CHAT_BACKFILL_A15=PASS (#{checks} checks)"
