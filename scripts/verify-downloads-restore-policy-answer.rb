#!/usr/bin/env ruby
require "tmpdir"
require_relative "../lib/soul_core/downloads_restore_policy_answer"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/chat_store"

policy = SoulCore::DownloadsRestorePolicyAnswer.new
first = policy.answer(message: "For files Soul moved from Downloads to Trash, what safeguards govern restoring one?")
raise "initial policy answer missing" unless first&.include?("existing original path blocks")
followup = policy.answer(message: "What happens if the original path already exists?", previous_user_message: "What safeguards govern restoring files from Downloads to Trash?")
raise "collision answer missing" unless followup&.include?("cannot override") && followup.include?("does not automatically rename")
raise "unrelated question intercepted" if policy.answer(message: "What happens if a project path exists?")
raise "restore action intercepted" if policy.answer(message: "Please restore the last Downloads cleanup")
raise "other restore intercepted" if policy.answer(message: "What safeguards govern restoring a system backup?")
raise "Soul backup intercepted" if policy.answer(message: "What safeguards govern restoring my Soul backup?")
raise "polite restore action intercepted" if policy.answer(message: "Could you please restore files from Downloads Trash?")
raise "other user's Trash intercepted" if policy.answer(message: "What safeguards govern restoring my friend's Trash items?")
raise "context not bounded" unless policy.needs_context?("What happens if the original path already exists?") && !policy.needs_context?("Tell me about memory")

source = File.read(File.expand_path("../Soul/skills/downloads/restore_last_cleanup.rb", __dir__))
raise "restore preflight changed" unless source.include?("original path already exists; refusing to overwrite") && source.include?("if errors.empty? && options[:execute]")

Dir.mktmpdir("soul-restore-policy-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat_id = store.create_chat.fetch("id")
  runtime = SoulCore::ConversationRuntime.new(root: root, env: {}, store: store)
  store.add_message(chat_id, role: "user", content: "What safeguards govern restoring files Soul moved from Downloads to Trash?")
  result = runtime.respond(chat_id: chat_id, message: "What safeguards govern restoring files Soul moved from Downloads to Trash?", interface: "voice_presence")
  raise "runtime did not use fixed policy" unless result.mode == "deterministic" && result.content.include?("does not overwrite")
  store.add_message(chat_id, role: "assistant", content: result.content)
  store.add_message(chat_id, role: "user", content: "What happens if the original path already exists?")
  followup_result = runtime.respond(chat_id: chat_id, message: "What happens if the original path already exists?", interface: "voice_presence")
  raise "runtime did not block collision claim" unless followup_result.mode == "deterministic" && followup_result.content.include?("cannot override")
end

puts "PASS Downloads restore policy routing, collision refusal, and unrelated/action exclusions"
