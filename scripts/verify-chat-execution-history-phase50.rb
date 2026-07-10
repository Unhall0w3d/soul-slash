#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Chat execution history phase 50 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/chat_execution_history.rb",
  "lib/soul_core/chat_execution_history_assessor.rb",
  "lib/soul_core/read_only_skill_execution_gate.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-chat-execution-history-phase50.rb",
  "docs/maintenance/PHASE50_CHAT_EXECUTION_HISTORY.md",
  "docs/CHAT_EXECUTION_HISTORY.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
{
  "app requires chat execution history" => app.include?('require_relative "chat_execution_history"'),
  "app requires chat execution history assessor" => app.include?('require_relative "chat_execution_history_assessor"'),
  "app exposes chat execution history assessment" => app.include?('"chat-execution-history", "execution-history", "chat-history"'),
  "app help includes chat execution history" => app.include?("ruby bin/soul assess chat-execution-history")
}.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "chat-execution-history", "--json")
json = JSON.parse(stdout) rescue nil
history_ok =
  status.success? &&
  json &&
  json["assessment"] == "chat_execution_history" &&
  json["phase"] == 50 &&
  json["ok"] == true &&
  json["entries"].is_a?(Array) &&
  json["entries"].length == 3 &&
  json.dig("verification", "records_executed_results") == true &&
  json.dig("verification", "records_blocked_results") == true &&
  json.dig("verification", "uses_runtime_path_by_default") == true

puts "- JSON chat execution history assessment: #{history_ok ? 'ok' : 'missing'}"
errors << "JSON chat execution history assessment failed: #{stderr} #{stdout}" unless history_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "chat-execution-history")
text_ok =
  status.success? &&
  stdout.include?("Soul Chat Execution History Assessment") &&
  stdout.include?("Status: ready")

puts "- text chat execution history assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text chat execution history assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "check repo health")
chat_record_ok =
  status.success? &&
  stdout.include?("I executed the read-only system status check.") &&
  stdout.include?("History recorded: true")

puts "- chat records read-only execution: #{chat_record_ok ? 'ok' : 'missing'}"
errors << "chat read-only execution history failed: #{stderr} #{stdout}" unless chat_record_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "execution history")
history_render_ok =
  status.success? &&
  stdout.include?("Soul Chat Execution History") &&
  stdout.include?("system.status")

puts "- chat renders execution history: #{history_render_ok ? 'ok' : 'missing'}"
errors << "chat execution history render failed: #{stderr} #{stdout}" unless history_render_ok

stdout, stderr, status = run_cmd("git", "check-ignore", "Soul/runtime/chats")
runtime_ignore_ok = status.success?
puts "- Soul/runtime remains gitignored: #{runtime_ignore_ok ? 'ok' : 'missing'}"
errors << "Soul/runtime is not ignored: #{stderr} #{stdout}" unless runtime_ignore_ok

doc_ok =
  File.read("docs/CHAT_EXECUTION_HISTORY.md").include?("chat execution history") &&
  File.read("docs/maintenance/PHASE50_CHAT_EXECUTION_HISTORY.md").include?("Phase 50")
puts "- phase 50 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 50 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-chat-execution-history-phase50.rb"]
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
