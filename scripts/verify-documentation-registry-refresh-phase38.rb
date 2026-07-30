
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "yaml"

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
registry = YAML.load_file("Soul/skills/registry.yaml").fetch("skills")
expected_ids = registry.keys.map(&:to_s).sort
projected_ids = json&.dig("registry", "skill_ids")
projected_record_ids = json&.fetch("skill_records", [])&.map { |record| record["id"] }&.sort
skills_doc = File.read("docs/SKILLS.md")
skills_doc_ids = expected_ids.select do |id|
  skills_doc.match?(/(?<![A-Za-z0-9_.-])#{Regexp.escape(id)}(?![A-Za-z0-9_.-])/)
end

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "documentation_registry_refresh" &&
  json["ok"] == true &&
  json["status"] == "ready" &&
  json["current"] == true &&
  json.dig("registry", "present") == true &&
  json.dig("registry", "skill_count") == expected_ids.length &&
  projected_ids == expected_ids &&
  projected_record_ids == expected_ids &&
  skills_doc_ids == expected_ids &&
  json.dig("documentation", "documented_skill_ids") == expected_ids &&
  json.dig("documentation", "missing_from_docs") == [] &&
  json.dig("documentation", "human_documentation_complete") == true &&
  json.dig("documentation", "snapshot_present") == true &&
  json.dig("documentation", "snapshot_current") == true &&
  json["warnings"] == [] &&
  json["blockers"] == [] &&
  json.dig("verification", "read_only") == true &&
  json.dig("verification", "no_registry_changes") == true &&
  json.dig("verification", "no_skill_behavior_changed") == true

puts "- exact registry projection and current JSON assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON documentation-registry assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "documentation-registry")
text_ok =
  status.success? &&
  stdout.include?("Soul Documentation Registry Refresh Assessment") &&
  stdout.include?("Status: ready") &&
  stdout.include?("- snapshot_current: true") &&
  stdout.include?("- missing_from_docs: None") &&
  stdout.include?("Registry")

puts "- text documentation-registry assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text documentation-registry assessment failed: #{stderr} #{stdout}" unless text_ok

snapshot_path = "docs/SKILL_REGISTRY_SNAPSHOT.md"
snapshot = File.exist?(snapshot_path) ? File.read(snapshot_path) : ""
snapshot_ids = snapshot.scan(/^### `([^`]+)`$/).flatten
missing_metadata_ids = registry.filter_map do |id, record|
  id.to_s unless record.key?("name") && record.key?("category") && record.key?("status")
end
missing_status_ids = registry.filter_map { |id, record| id.to_s unless record.key?("status") }

metadata_ok =
  snapshot_ids == expected_ids &&
  !missing_metadata_ids.empty? &&
  !missing_status_ids.empty? &&
  snapshot.include?("name: not declared") &&
  snapshot.include?("category: not declared") &&
  snapshot.include?("status: registered (availability not declared)") &&
  !snapshot.include?("category: uncategorized") &&
  !snapshot.include?("status: unknown") &&
  !snapshot.match?(/^Generated:/)

puts "- deterministic snapshot and honest missing-metadata labels: #{metadata_ok ? 'ok' : 'missing'}"
errors << "snapshot projection or missing-metadata labels are incorrect" unless metadata_ok

snapshot_bytes_before = snapshot.b
snapshot_mtime_before = File.exist?(snapshot_path) ? File.stat(snapshot_path).mtime.to_r : nil
sleep 0.02
stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "documentation-registry-refresh")
snapshot_bytes_after = File.exist?(snapshot_path) ? File.binread(snapshot_path) : nil
snapshot_mtime_after = File.exist?(snapshot_path) ? File.stat(snapshot_path).mtime.to_r : nil
refresh_ok =
  status.success? &&
  stdout.include?("docs/SKILL_REGISTRY_SNAPSHOT.md is already current") &&
  snapshot_bytes_after == snapshot_bytes_before &&
  snapshot_mtime_after == snapshot_mtime_before

puts "- current snapshot refresh preserves bytes and mtime: #{refresh_ok ? 'ok' : 'missing'}"
errors << "idempotent documentation registry refresh failed: #{stderr} #{stdout}" unless refresh_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "docs-registry", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "documentation_registry_refresh" &&
  alias_json["status"] == "ready" &&
  alias_json.dig("documentation", "snapshot_current") == true

puts "- docs-registry alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "docs-registry alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/DOCUMENTATION_REGISTRY_REFRESH.md").include?("human-maintained documentation coverage") &&
  File.read("docs/DOCUMENTATION_REGISTRY_REFRESH.md").include?("snapshot_current") &&
  File.read("docs/maintenance/PHASE38_DOCUMENTATION_REGISTRY_REFRESH.md").include?("Phase 38") &&
  File.read("docs/maintenance/PHASE38_DOCUMENTATION_REGISTRY_REFRESH.md").include?("historical Phase 38 title")
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
