#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Execution history pruning phase 53 verification:"

paths = [
  "lib/soul_core/chat_execution_history.rb",
  "lib/soul_core/chat_execution_history_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-execution-history-pruning-phase53.rb",
  "docs/maintenance/PHASE53_EXECUTION_HISTORY_PRUNING.md",
  "docs/EXECUTION_HISTORY_PRUNING.md"
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
  json["phase"] == 53 &&
  json["ok"] == true &&
  json.dig("verification", "previews_without_mutation") == true &&
  json.dig("verification", "requires_confirmation") == true &&
  json.dig("verification", "prunes_with_confirmation") == true &&
  json.dig("verification", "exports_before_delete") == true &&
  json.dig("verification", "keeps_requested_count") == true

puts "- JSON execution history pruning assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "JSON execution history pruning assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "chat-execution-history")
text_ok = status.success? && stdout.include?("Soul Execution History Pruning Assessment") && stdout.include?("Status: ready")
puts "- text execution history pruning assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text execution history pruning assessment failed: #{stderr} #{stdout}" unless text_ok

3.times { run_cmd("ruby", "bin/soul", "chat", "check repo health") }

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "prune execution history keep 1")
preview_ok =
  status.success? &&
  stdout.include?("Execution history prune preview.") &&
  stdout.include?("Pruned: false") &&
  stdout.include?("Add `confirm`")

puts "- chat previews prune without mutation: #{preview_ok ? 'ok' : 'missing'}"
errors << "chat prune preview failed: #{stderr} #{stdout}" unless preview_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "prune execution history keep 1 confirm")
prune_ok =
  status.success? &&
  stdout.include?("Execution history pruned.") &&
  stdout.include?("Pruned: true") &&
  stdout.include?("Exported removed entries:")

puts "- chat prunes with confirmation: #{prune_ok ? 'ok' : 'missing'}"
errors << "chat confirmed prune failed: #{stderr} #{stdout}" unless prune_ok

stdout, stderr, status = run_cmd("git", "check-ignore", "Soul/runtime/exports/execution_history/example.json")
ignore_ok = status.success?
puts "- Soul/runtime exports remain gitignored: #{ignore_ok ? 'ok' : 'missing'}"
errors << "Soul/runtime exports are not ignored: #{stderr} #{stdout}" unless ignore_ok

doc_ok =
  File.read("docs/EXECUTION_HISTORY_PRUNING.md").include?("execution history pruning") &&
  File.read("docs/maintenance/PHASE53_EXECUTION_HISTORY_PRUNING.md").include?("Phase 53")
puts "- phase 53 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 53 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-execution-history-pruning-phase53.rb"]
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
