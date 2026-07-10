#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Second read-only execution adapter phase 49 verification:"

paths = [
  "lib/soul_core/read_only_skill_execution_gate.rb",
  "lib/soul_core/read_only_skill_execution_gate_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-second-read-only-execution-adapter-phase49.rb",
  "docs/maintenance/PHASE49_SECOND_READ_ONLY_EXECUTION_ADAPTER.md",
  "docs/SECOND_READ_ONLY_EXECUTION_ADAPTER.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "read_only_skill_execution_gate" &&
  json["phase"] == 49 &&
  json["ok"] == true &&
  json["samples"].is_a?(Array) &&
  json["samples"].any? { |sample| sample.dig("actual", "skill_id") == "assistant-skill-catalog" && sample.dig("actual", "executed") == true } &&
  json["samples"].any? { |sample| sample.dig("actual", "skill_id") == "system.status" && sample.dig("actual", "executed") == true } &&
  json.dig("verification", "system_status_executed") == true &&
  json.dig("verification", "no_approval_required_execution") == true

puts "- JSON read-only gate phase 49 assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON read-only gate phase 49 assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate")
text_ok =
  status.success? &&
  stdout.include?("Soul Second Read-Only Execution Adapter Assessment") &&
  stdout.include?("Status: ready")

puts "- text read-only gate phase 49 assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text read-only gate phase 49 assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "check repo health")
chat_status_ok =
  status.success? &&
  stdout.include?("I executed the read-only system status check.") &&
  stdout.include?("Executed: true") &&
  stdout.include?("Skill: system.status")

puts "- chat executes system status: #{chat_status_ok ? 'ok' : 'missing'}"
errors << "chat system status execution failed: #{stderr} #{stdout}" unless chat_status_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
trash_ok =
  status.success? &&
  stdout.include?("Executed: false") &&
  stdout.include?("owner_confirmation_required")

puts "- approval-required skill remains blocked: #{trash_ok ? 'ok' : 'missing'}"
errors << "approval-required skill block failed: #{stderr} #{stdout}" unless trash_ok

doc_ok =
  File.read("docs/SECOND_READ_ONLY_EXECUTION_ADAPTER.md").include?("second read-only execution adapter") &&
  File.read("docs/maintenance/PHASE49_SECOND_READ_ONLY_EXECUTION_ADAPTER.md").include?("Phase 49")
puts "- phase 49 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 49 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-second-read-only-execution-adapter-phase49.rb"]
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
