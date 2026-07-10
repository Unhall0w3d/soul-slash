#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Chat interface foundation phase 41 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/chat_store.rb",
  "lib/soul_core/chat_responder.rb",
  "lib/soul_core/chat_command.rb",
  "scripts/verify-chat-interface-foundation-phase41.rb",
  "docs/maintenance/PHASE41_CHAT_INTERFACE_FOUNDATION.md",
  "docs/CHAT_INTERFACE_FOUNDATION.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_checks = {
  "app requires chat command" => app.include?('require_relative "chat_command"'),
  "app exposes chat command" => app.include?('when "chat", "chats"'),
  "app help includes chat command" => app.include?('ruby bin/soul chat [message]')
}

app_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "what skills do you have?")
single_ok =
  status.success? &&
  stdout.include?("Soul>") &&
  stdout.include?("registered skill")

puts "- single-shot chat response: #{single_ok ? 'ok' : 'missing'}"
errors << "single-shot chat response failed: #{stderr} #{stdout}" unless single_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "--list")
list_ok =
  status.success? &&
  (stdout.include?("chat_") || stdout.include?("No Soul chats yet."))

puts "- chat list command: #{list_ok ? 'ok' : 'missing'}"
errors << "chat list command failed: #{stderr} #{stdout}" unless list_ok

chat_files = Dir.glob("Soul/runtime/chats/*.json")
jsonl_files = Dir.glob("Soul/runtime/chats/*.jsonl")
storage_ok = !chat_files.empty? && !jsonl_files.empty?
puts "- local chat storage created: #{storage_ok ? 'ok' : 'missing'}"
errors << "local chat storage was not created" unless storage_ok

if storage_ok
  latest = chat_files.max_by { |path| File.mtime(path) }
  metadata = JSON.parse(File.read(latest)) rescue {}
  puts "- latest chat metadata readable: #{metadata['id'] ? 'ok' : 'missing'}"
  errors << "latest chat metadata unreadable" unless metadata["id"]
end

doc_ok =
  File.read("docs/CHAT_INTERFACE_FOUNDATION.md").include?("ruby bin/soul chat") &&
  File.read("docs/maintenance/PHASE41_CHAT_INTERFACE_FOUNDATION.md").include?("Phase 41")
puts "- phase 41 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 41 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = [
  "scripts/verify-chat-interface-foundation-phase41.rb"
]
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
