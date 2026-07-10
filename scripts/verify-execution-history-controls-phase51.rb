#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Execution history controls phase 51 verification:"

paths = [
  "lib/soul_core/chat_execution_history.rb",
  "lib/soul_core/chat_execution_history_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-execution-history-controls-phase51.rb",
  "docs/maintenance/PHASE51_EXECUTION_HISTORY_CONTROLS.md",
  "docs/EXECUTION_HISTORY_CONTROLS.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "chat-execution-history", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "chat_execution_history" &&
  json["phase"] == 51 &&
  json["ok"] == true &&
  json.dig("verification", "exports_json") == true &&
  json.dig("verification", "exports_jsonl") == true &&
  json.dig("verification", "blocks_unconfirmed_clear") == true &&
  json.dig("verification", "clears_with_confirmation") == true
puts "- JSON execution history controls assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "JSON execution history controls assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "chat-execution-history")
text_ok = status.success? && stdout.include?("Soul Chat Execution History Controls Assessment") && stdout.include?("Status: ready")
puts "- text execution history controls assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text execution history controls assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "check repo health")
record_ok = status.success? && stdout.include?("History recorded: true")
puts "- chat records execution: #{record_ok ? 'ok' : 'missing'}"
errors << "chat record failed: #{stderr} #{stdout}" unless record_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "export execution history")
export_ok = status.success? && stdout.include?("Execution history exported.") && stdout.include?("Path:")
puts "- chat exports execution history: #{export_ok ? 'ok' : 'missing'}"
errors << "chat export failed: #{stderr} #{stdout}" unless export_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "clear execution history")
blocked_clear_ok = status.success? && stdout.include?("requires confirm") && stdout.include?("Deleted: false")
puts "- chat blocks unconfirmed clear: #{blocked_clear_ok ? 'ok' : 'missing'}"
errors << "chat unconfirmed clear block failed: #{stderr} #{stdout}" unless blocked_clear_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "clear execution history confirm")
clear_ok = status.success? && stdout.include?("Status: cleared")
puts "- chat clears with confirmation: #{clear_ok ? 'ok' : 'missing'}"
errors << "chat confirmed clear failed: #{stderr} #{stdout}" unless clear_ok

stdout, stderr, status = run_cmd("git", "check-ignore", "Soul/runtime/exports/execution_history/example.json")
export_ignore_ok = status.success?
puts "- Soul/runtime exports remain gitignored: #{export_ignore_ok ? 'ok' : 'missing'}"
errors << "Soul/runtime exports are not ignored: #{stderr} #{stdout}" unless export_ignore_ok

doc_ok =
  File.read("docs/EXECUTION_HISTORY_CONTROLS.md").include?("execution history controls") &&
  File.read("docs/maintenance/PHASE51_EXECUTION_HISTORY_CONTROLS.md").include?("Phase 51")
puts "- phase 51 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 51 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-execution-history-controls-phase51.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
unexpected_untracked = untracked - allowed_untracked
curation_ok = status.success? && curation && curation.dig("counts", "tracked_overlay_notes").to_i == 0 && unexpected_untracked.empty?
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
