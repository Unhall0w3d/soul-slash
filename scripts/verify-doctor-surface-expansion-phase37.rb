
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Doctor surface expansion phase 37 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/doctor_surface_assessor.rb",
  "scripts/verify-doctor-surface-expansion-phase37.rb",
  "docs/maintenance/PHASE37_DOCTOR_SURFACE_EXPANSION.md",
  "docs/DOCTOR_SURFACE.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_checks = {
  "app requires doctor surface assessor" => app.include?('require_relative "doctor_surface_assessor"'),
  "app exposes doctor-surface assessment" => app.include?('"doctor-surface", "doctor-coverage", "surface-doctor"'),
  "app help includes doctor-surface" => app.include?("ruby bin/soul assess doctor-surface")
}

app_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "doctor-surface", "--json")
json = JSON.parse(stdout) rescue nil

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "doctor_surface" &&
  json["ok"] == true &&
  json["status"] == "healthy" &&
  json.dig("doctor_scope", "read_only") == true &&
  json.dig("verification", "no_files_modified") == true &&
  json.dig("verification", "no_workflows_changed") == true &&
  json.dig("verification", "no_skill_behavior_changed") == true &&
  json.fetch("command_results").all? { |item| item["ok"] == true }

puts "- JSON doctor-surface assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON doctor-surface assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "doctor-surface")
text_ok =
  status.success? &&
  stdout.include?("Soul Doctor Surface Assessment") &&
  stdout.include?("Status: healthy") &&
  stdout.include?("Legacy surface")

puts "- text doctor-surface assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text doctor-surface assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "surface-doctor", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "doctor_surface" &&
  alias_json["status"] == "healthy"

puts "- surface-doctor alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "surface-doctor alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/DOCTOR_SURFACE.md").include?("doctor-surface") &&
  File.read("docs/maintenance/PHASE37_DOCTOR_SURFACE_EXPANSION.md").include?("Phase 37")
puts "- phase 37 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 37 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-doctor-surface-expansion-phase37.rb"]
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
