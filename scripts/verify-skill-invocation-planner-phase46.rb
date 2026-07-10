#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Skill invocation planner phase 46 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/skill_invocation_planner.rb",
  "lib/soul_core/skill_invocation_planner_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-skill-invocation-planner-phase46.rb",
  "docs/maintenance/PHASE46_SKILL_INVOCATION_PLANNER.md",
  "docs/SKILL_INVOCATION_PLANNER.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
{
  "app requires planner" => app.include?('require_relative "skill_invocation_planner"'),
  "app requires planner assessor" => app.include?('require_relative "skill_invocation_planner_assessor"'),
  "app exposes planner assessment" => app.include?('"skill-invocation-planner", "invocation-planner", "skill-planner"'),
  "app help includes planner" => app.include?("ruby bin/soul assess skill-invocation-planner")
}.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "skill-invocation-planner", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "skill_invocation_planner" &&
  json["ok"] == true &&
  json["status"] == "ready" &&
  json["samples"].is_a?(Array) &&
  json["samples"].all? { |sample| sample["matched"] } &&
  json["samples"].all? { |sample| sample.dig("actual", "executable_now") == false } &&
  json.dig("verification", "no_skill_execution") == true

puts "- JSON skill-invocation-planner assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON skill-invocation-planner assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "skill-invocation-planner")
text_ok =
  status.success? &&
  stdout.include?("Soul Skill Invocation Planner Assessment") &&
  stdout.include?("Status: ready")

puts "- text skill-invocation-planner assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text skill-invocation-planner assessment failed: #{stderr} #{stdout}" unless text_ok

{
  "downloads trash planning" => ["move approved downloads to trash", "Executable now: false"],
  "downloads inspect planning" => ["inspect my downloads", "Skill candidate: downloads.inspect"],
  "weather planning" => ["what is the weather?", "Skill candidate: weather.report"]
}.each do |name, (message, expected)|
  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", message)
  ok = status.success? && stdout.include?(expected)
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} failed: #{stderr} #{stdout}" unless ok
end

doc_ok =
  File.read("docs/SKILL_INVOCATION_PLANNER.md").include?("safe execution plans") &&
  File.read("docs/maintenance/PHASE46_SKILL_INVOCATION_PLANNER.md").include?("Phase 46")
puts "- phase 46 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 46 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = [
  "scripts/verify-skill-invocation-planner-phase46.rb"
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
