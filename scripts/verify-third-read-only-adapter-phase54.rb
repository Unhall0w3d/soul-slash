#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Third read-only adapter phase 54 verification:"

paths = [
  "lib/soul_core/intent_router.rb",
  "lib/soul_core/read_only_skill_execution_gate.rb",
  "lib/soul_core/read_only_skill_execution_gate_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-third-read-only-adapter-phase54.rb",
  "docs/maintenance/PHASE54_THIRD_READ_ONLY_ADAPTER.md",
  "docs/THIRD_READ_ONLY_ADAPTER.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "read_only_skill_execution_gate" &&
  json["phase"] == 54 &&
  json["ok"] == true &&
  json.dig("verification", "history_summary_executed") == true &&
  json.dig("verification", "history_summary_reports_counts") == true &&
  json.dig("verification", "no_approval_required_execution") == true

puts "- JSON read-only gate phase 54 assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "JSON read-only gate phase 54 assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate")
text_ok =
  status.success? &&
  stdout.include?("Soul Third Read-Only Execution Adapter Assessment") &&
  stdout.include?("Status: ready")

puts "- text read-only gate phase 54 assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text read-only gate phase 54 assessment failed: #{stderr} #{stdout}" unless text_ok

run_cmd("ruby", "bin/soul", "chat", "check repo health")
stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "execution history summary")
summary_ok =
  status.success? &&
  stdout.include?("I executed the read-only execution history summary.") &&
  stdout.include?("Executed: true") &&
  stdout.include?("Skill: execution.history.summary") &&
  stdout.include?("Counts by skill:")

puts "- chat executes execution history summary: #{summary_ok ? 'ok' : 'missing'}"
errors << "chat execution history summary failed: #{stderr} #{stdout}" unless summary_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
blocked_ok =
  status.success? &&
  stdout.include?("Executed: false") &&
  stdout.include?("owner_confirmation_required")

puts "- approval-required skill remains blocked: #{blocked_ok ? 'ok' : 'missing'}"
errors << "approval-required skill block failed: #{stderr} #{stdout}" unless blocked_ok

doc_ok =
  File.read("docs/THIRD_READ_ONLY_ADAPTER.md").include?("third read-only adapter") &&
  File.read("docs/maintenance/PHASE54_THIRD_READ_ONLY_ADAPTER.md").include?("Phase 54")
puts "- phase 54 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 54 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-third-read-only-adapter-phase54.rb"]
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
