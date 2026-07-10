#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Assistant skill catalog phase 43 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/assistant_skill_catalog.rb",
  "scripts/verify-assistant-skill-catalog-phase43.rb",
  "docs/maintenance/PHASE43_ASSISTANT_SKILL_CATALOG.md",
  "docs/ASSISTANT_SKILL_CATALOG_DESIGN.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_checks = {
  "app requires assistant skill catalog" => app.include?('require_relative "assistant_skill_catalog"'),
  "app exposes assistant skill catalog assessment" => app.include?('"assistant-skill-catalog", "skill-catalog", "skills-catalog"'),
  "app exposes assistant skill catalog refresh" => app.include?('"assistant-skill-catalog-refresh", "skill-catalog-refresh", "skills-catalog-refresh"'),
  "app help includes catalog assessment" => app.include?("ruby bin/soul assess assistant-skill-catalog"),
  "app help includes catalog refresh" => app.include?("ruby bin/soul improve assistant-skill-catalog-refresh")
}

app_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "assistant-skill-catalog", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "assistant_skill_catalog" &&
  json["ok"] == true &&
  json["status"] == "ready" &&
  json.dig("registry", "skill_count").to_i.positive? &&
  json.fetch("skills").all? { |skill| skill["id"] && skill["human_name"] && skill["risk"] && skill["example_utterances"].is_a?(Array) } &&
  json.dig("verification", "no_registry_changes") == true

puts "- JSON assistant-skill-catalog assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON assistant-skill-catalog assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "assistant-skill-catalog")
text_ok =
  status.success? &&
  stdout.include?("Soul Assistant Skill Catalog Assessment") &&
  stdout.include?("Status: ready") &&
  stdout.include?("Skills")

puts "- text assistant-skill-catalog assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text assistant-skill-catalog assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "assistant-skill-catalog-refresh")
refresh_ok =
  status.success? &&
  stdout.include?("Wrote docs/ASSISTANT_SKILL_CATALOG.md") &&
  File.exist?("docs/ASSISTANT_SKILL_CATALOG.md") &&
  File.read("docs/ASSISTANT_SKILL_CATALOG.md").include?("# Assistant Skill Catalog") &&
  File.read("docs/ASSISTANT_SKILL_CATALOG.md").include?("confirmation_required")

puts "- assistant skill catalog generation: #{refresh_ok ? 'ok' : 'missing'}"
errors << "assistant skill catalog generation failed: #{stderr} #{stdout}" unless refresh_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "skills-catalog", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "assistant_skill_catalog" &&
  alias_json["status"] == "ready"

puts "- skills-catalog alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "skills-catalog alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/ASSISTANT_SKILL_CATALOG_DESIGN.md").include?("assistant-facing skill catalog") &&
  File.read("docs/maintenance/PHASE43_ASSISTANT_SKILL_CATALOG.md").include?("Phase 43")
puts "- phase 43 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 43 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-assistant-skill-catalog-phase43.rb"]
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
