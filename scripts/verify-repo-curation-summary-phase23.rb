
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "repo curation summary phase 23 verification:"

required_files = [
  "docs/maintenance/CURATION_STATUS.md",
  "docs/maintenance/CURATION_DECISIONS.md",
  "docs/maintenance/PHASE23_REPO_CURATION_SUMMARY.md",
  "docs/REPOSITORY_MAP.md",
  "scripts/verify-repo-curation-summary-phase23.rb",
  "scripts/verify-repo-hygiene-phase20.rb",
  "scripts/verify-repo-curation-phase21.rb",
  "scripts/verify-repo-curation-decisions-phase22.rb"
]

required_files.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil

allowed_current_phase_candidates = [
  "scripts/verify-repo-curation-summary-phase23.rb"
]

untracked_review_candidates =
  curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []

unexpected_untracked_review_candidates = untracked_review_candidates - allowed_current_phase_candidates

curation_ok =
  status.success? &&
  curation &&
  curation["assessment"] == "repo_curation" &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  unexpected_untracked_review_candidates.empty? &&
  curation.dig("counts", "untracked_generated_local").to_i == 0

puts "- clean repo-curation assessment: #{curation_ok ? 'ok' : 'missing'}"
unless curation_ok
  errors << "repo-curation is not clean: #{stderr} #{stdout}"
end

if (untracked_review_candidates & allowed_current_phase_candidates).any?
  puts "- current phase verifier pending commit: ok"
end

stdout, stderr, status = run_cmd("ruby", "scripts/verify-repo-hygiene-phase20.rb")
hygiene_ok = status.success? && stdout.include?("Verification complete.")
puts "- repo hygiene verifier: #{hygiene_ok ? 'ok' : 'missing'}"
errors << "repo hygiene failed: #{stderr} #{stdout}" unless hygiene_ok

stdout, stderr, status = run_cmd("ruby", "scripts/verify-repo-curation-phase21.rb")
phase21_ok = status.success? && stdout.include?("Verification complete.")
puts "- phase 21 verifier: #{phase21_ok ? 'ok' : 'missing'}"
errors << "phase 21 verifier failed: #{stderr} #{stdout}" unless phase21_ok

stdout, stderr, status = run_cmd("ruby", "scripts/verify-repo-curation-decisions-phase22.rb")
phase22_ok = status.success? && stdout.include?("Verification complete.")
puts "- phase 22 verifier: #{phase22_ok ? 'ok' : 'missing'}"
errors << "phase 22 verifier failed: #{stderr} #{stdout}" unless phase22_ok

status_doc = File.read("docs/maintenance/CURATION_STATUS.md") rescue ""
map_doc = File.read("docs/REPOSITORY_MAP.md") rescue ""
phase_doc = File.read("docs/maintenance/PHASE23_REPO_CURATION_SUMMARY.md") rescue ""

doc_checks = {
  "curation status records complete state" => status_doc.include?("Status: complete for phases 20-22"),
  "curation status records tracked overlay zero" => status_doc.include?("tracked_overlay_notes: 0"),
  "repository map references curation status" => map_doc.include?("docs/maintenance/CURATION_STATUS.md"),
  "phase 23 doc says no runtime behavior change" => phase_doc.include?("does not change runtime behavior")
}

doc_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing expected text" unless ok
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
