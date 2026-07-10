#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Execution history filters phase 52 verification:"

paths = [
  "lib/soul_core/chat_execution_history.rb",
  "lib/soul_core/chat_execution_history_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-execution-history-filters-phase52.rb",
  "docs/maintenance/PHASE52_EXECUTION_HISTORY_FILTERS.md",
  "docs/EXECUTION_HISTORY_FILTERS.md"
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
  json["phase"] == 52 &&
  json["ok"] == true &&
  json.dig("verification", "filters_by_skill_id") == true &&
  json.dig("verification", "filters_by_status") == true &&
  json.dig("verification", "filters_by_executed") == true &&
  json.dig("verification", "parses_chat_filters") == true &&
  json.dig("verification", "exports_filtered_history") == true

puts "- JSON execution history filters assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "JSON execution history filters assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "chat-execution-history")
text_ok = status.success? && stdout.include?("Soul Execution History Filters Assessment") && stdout.include?("Status: ready")
puts "- text execution history filters assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text execution history filters assessment failed: #{stderr} #{stdout}" unless text_ok

run_cmd("ruby", "bin/soul", "chat", "check repo health")
run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "execution history skill system.status")
skill_filter_ok = status.success? && stdout.include?("Filters: skill_id=system.status") && stdout.include?("system.status")
puts "- chat filters history by skill: #{skill_filter_ok ? 'ok' : 'missing'}"
errors << "chat skill filter failed: #{stderr} #{stdout}" unless skill_filter_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "execution history blocked")
blocked_filter_ok = status.success? && stdout.include?("Filters: status=blocked")
puts "- chat filters history by status: #{blocked_filter_ok ? 'ok' : 'missing'}"
errors << "chat status filter failed: #{stderr} #{stdout}" unless blocked_filter_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "export execution history blocked")
export_filter_ok = status.success? && stdout.include?("Execution history exported.") && stdout.include?("Filters: status=blocked")
puts "- chat exports filtered history: #{export_filter_ok ? 'ok' : 'missing'}"
errors << "chat filtered export failed: #{stderr} #{stdout}" unless export_filter_ok

doc_ok =
  File.read("docs/EXECUTION_HISTORY_FILTERS.md").include?("execution history filters") &&
  File.read("docs/maintenance/PHASE52_EXECUTION_HISTORY_FILTERS.md").include?("Phase 52")
puts "- phase 52 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 52 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-execution-history-filters-phase52.rb"]
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
