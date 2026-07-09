
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Documentation registry refresh phase 38 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/documentation_registry_refresh_assessor.rb",
  "scripts/verify-documentation-registry-refresh-phase38.rb",
  "docs/maintenance/PHASE38_DOCUMENTATION_REGISTRY_REFRESH.md",
  "docs/DOCUMENTATION_REGISTRY_REFRESH.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_checks = {
  "app requires documentation registry assessor" => app.include?('require_relative "documentation_registry_refresh_assessor"'),
  "app exposes documentation registry assessment" => app.include?('"documentation-registry", "doc-registry", "docs-registry"'),
  "app exposes documentation registry refresh" => app.include?('"documentation-registry-refresh", "doc-registry-refresh", "docs-registry-refresh"'),
  "app help includes docs registry assessment" => app.include?("ruby bin/soul assess documentation-registry"),
  "app help includes docs registry refresh" => app.include?("ruby bin/soul improve documentation-registry-refresh")
}

app_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "documentation-registry", "--json")
json = JSON.parse(stdout) rescue nil

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "documentation_registry_refresh" &&
  json["ok"] == true &&
  json["status"] == "ready" &&
  json.dig("registry", "present") == true &&
  json.dig("registry", "skill_count").to_i.positive? &&
  json.dig("verification", "read_only") == true &&
  json.dig("verification", "no_registry_changes") == true &&
  json.dig("verification", "no_skill_behavior_changed") == true

puts "- JSON documentation-registry assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON documentation-registry assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "documentation-registry")
text_ok =
  status.success? &&
  stdout.include?("Soul Documentation Registry Refresh Assessment") &&
  stdout.include?("Status: ready") &&
  stdout.include?("Registry")

puts "- text documentation-registry assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text documentation-registry assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "documentation-registry-refresh")
refresh_ok =
  status.success? &&
  stdout.include?("Wrote docs/SKILL_REGISTRY_SNAPSHOT.md") &&
  File.exist?("docs/SKILL_REGISTRY_SNAPSHOT.md") &&
  File.read("docs/SKILL_REGISTRY_SNAPSHOT.md").include?("# Skill Registry Snapshot")

puts "- documentation registry snapshot generation: #{refresh_ok ? 'ok' : 'missing'}"
errors << "documentation registry snapshot generation failed: #{stderr} #{stdout}" unless refresh_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "docs-registry", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "documentation_registry_refresh" &&
  alias_json["status"] == "ready"

puts "- docs-registry alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "docs-registry alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/DOCUMENTATION_REGISTRY_REFRESH.md").include?("documentation-registry") &&
  File.read("docs/maintenance/PHASE38_DOCUMENTATION_REGISTRY_REFRESH.md").include?("Phase 38")
puts "- phase 38 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 38 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-documentation-registry-refresh-phase38.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
unexpected_untracked = untracked - allowed_untracked

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  curation.dig("counts", "untracked_generated_local").to_i == 0 &&
  unexpected_untracked.empty?

puts "- repo curation remains clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation has unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if (untracked & allowed_untracked).any?
  puts "- current phase verifier pending commit: ok"
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
