#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Read-only skill execution gate phase 47 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/read_only_skill_execution_gate.rb",
  "lib/soul_core/read_only_skill_execution_gate_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-read-only-skill-execution-gate-phase47.rb",
  "docs/maintenance/PHASE47_READ_ONLY_SKILL_EXECUTION_GATE.md",
  "docs/READ_ONLY_SKILL_EXECUTION_GATE.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
{
  "app requires read-only gate" => app.include?('require_relative "read_only_skill_execution_gate"'),
  "app requires read-only gate assessor" => app.include?('require_relative "read_only_skill_execution_gate_assessor"'),
  "app exposes read-only gate assessment" => app.include?('"read-only-skill-gate", "read-only-execution", "skill-execution-gate"'),
  "app help includes read-only gate" => app.include?("ruby bin/soul assess read-only-skill-gate")
}.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "read_only_skill_execution_gate" &&
  json["ok"] == true &&
  json["status"] == "ready" &&
  json["samples"].is_a?(Array) &&
  json["samples"].all? { |sample| sample["matched"] } &&
  json["samples"].all? { |sample| sample.dig("actual", "executed") == false } &&
  json.dig("verification", "no_skill_execution") == true &&
  json.dig("verification", "dry_run_default") == true

puts "- JSON read-only gate assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON read-only gate assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate")
text_ok =
  status.success? &&
  stdout.include?("Soul Read-Only Skill Execution Gate Assessment") &&
  stdout.include?("Status: ready")

puts "- text read-only gate assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text read-only gate assessment failed: #{stderr} #{stdout}" unless text_ok

{
  "downloads inspect gated" => ["inspect my downloads", "Gate status: blocked"],
  "downloads trash blocked" => ["move approved downloads to trash", "owner_confirmation_required"],
  "skill catalog dry-run" => ["what skills do you have?", "read-only execution gate"]
}.each do |name, (message, expected)|
  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", message)
  ok = status.success? && stdout.downcase.include?(expected.downcase)
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} failed: #{stderr} #{stdout}" unless ok
end

doc_ok =
  File.read("docs/READ_ONLY_SKILL_EXECUTION_GATE.md").include?("read-only execution gate") &&
  File.read("docs/maintenance/PHASE47_READ_ONLY_SKILL_EXECUTION_GATE.md").include?("Phase 47")
puts "- phase 47 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 47 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-read-only-skill-execution-gate-phase47.rb"]
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
