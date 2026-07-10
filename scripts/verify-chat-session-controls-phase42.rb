#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

def latest_chat_id
  files = Dir.glob("Soul/runtime/chats/*.json")
  latest = files.max_by { |path| File.mtime(path) }
  return nil unless latest

  JSON.parse(File.read(latest))["id"]
rescue StandardError
  nil
end

puts "Chat session controls phase 42 verification:"

paths = [
  "lib/soul_core/chat_store.rb",
  "lib/soul_core/chat_command.rb",
  "scripts/verify-chat-session-controls-phase42.rb",
  "docs/maintenance/PHASE42_CHAT_SESSION_CONTROLS.md",
  "docs/CHAT_SESSION_CONTROLS.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "phase42 session controls test")
single_ok = status.success? && stdout.include?("Soul>")
puts "- single-shot chat still works: #{single_ok ? 'ok' : 'missing'}"
errors << "single-shot chat failed: #{stderr} #{stdout}" unless single_ok

chat_id = latest_chat_id
id_ok = chat_id && !chat_id.empty?
puts "- captured latest chat id: #{id_ok ? 'ok' : 'missing'}"
errors << "could not capture latest chat id" unless id_ok

if chat_id
  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--resume", chat_id, "what skills do you have?")
  resume_ok = status.success? && stdout.include?("registered skill")
  puts "- resume chat with message: #{resume_ok ? 'ok' : 'missing'}"
  errors << "resume chat failed: #{stderr} #{stdout}" unless resume_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--show", chat_id)
  show_ok = status.success? && stdout.include?(chat_id) && stdout.include?("user>") && stdout.include?("assistant>")
  puts "- show chat transcript: #{show_ok ? 'ok' : 'missing'}"
  errors << "show chat failed: #{stderr} #{stdout}" unless show_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--search", "session controls")
  search_ok = status.success? && stdout.include?(chat_id)
  puts "- search chats: #{search_ok ? 'ok' : 'missing'}"
  errors << "search chat failed: #{stderr} #{stdout}" unless search_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--pin", chat_id)
  pin_ok = status.success? && stdout.include?("Pinned chat")
  puts "- pin chat: #{pin_ok ? 'ok' : 'missing'}"
  errors << "pin chat failed: #{stderr} #{stdout}" unless pin_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--list")
  list_ok = status.success? && stdout.include?("★ #{chat_id}")
  puts "- list shows pinned chat: #{list_ok ? 'ok' : 'missing'}"
  errors << "list pinned chat failed: #{stderr} #{stdout}" unless list_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--rename", chat_id, "--title", "Phase 42 verification chat")
  rename_ok = status.success? && stdout.include?("Renamed chat")
  puts "- rename chat: #{rename_ok ? 'ok' : 'missing'}"
  errors << "rename chat failed: #{stderr} #{stdout}" unless rename_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--unpin", chat_id)
  unpin_ok = status.success? && stdout.include?("Unpinned chat")
  puts "- unpin chat: #{unpin_ok ? 'ok' : 'missing'}"
  errors << "unpin chat failed: #{stderr} #{stdout}" unless unpin_ok

  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--recent")
  recent_ok = status.success? && stdout.include?("Soul chats:")
  puts "- recent chats: #{recent_ok ? 'ok' : 'missing'}"
  errors << "recent chats failed: #{stderr} #{stdout}" unless recent_ok
end

doc_ok =
  File.read("docs/CHAT_SESSION_CONTROLS.md").include?("--resume") &&
  File.read("docs/maintenance/PHASE42_CHAT_SESSION_CONTROLS.md").include?("Phase 42")
puts "- phase 42 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 42 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-chat-session-controls-phase42.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
unexpected_untracked = untracked - allowed_untracked

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  unexpected_untracked.empty?

puts "- repo curation remains clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation has unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
