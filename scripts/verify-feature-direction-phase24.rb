
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "feature direction phase 24 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/feature_direction_assessor.rb",
  "scripts/verify-feature-direction-phase24.rb",
  "docs/maintenance/PHASE24_FEATURE_DIRECTION.md",
  "docs/FEATURE_DIRECTION.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires feature direction assessor" => app.include?('require_relative "feature_direction_assessor"'),
  "app exposes feature-direction assessment" => app.include?('"feature-direction", "features", "next-feature"'),
  "app help includes feature direction" => app.include?("assess feature-direction")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "feature-direction", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "feature_direction" &&
  json["read_only"] == true &&
  json["recommended_next_capability"] == "model_suitability_registry" &&
  json["ranked_candidates"].is_a?(Array) &&
  json["ranked_candidates"].length >= 4 &&
  json.dig("verification", "advisory_only") == true &&
  json.dig("verification", "no_models_downloaded") == true

puts "- JSON feature direction assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON feature direction failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "feature-direction")
text_ok =
  status.success? &&
  stdout.include?("Soul Feature Direction Assessment") &&
  stdout.include?("Recommended next capability: model_suitability_registry") &&
  stdout.include?("Ranked candidates")

puts "- text feature direction assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text feature direction failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "features", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok = status.success? && alias_json && alias_json["assessment"] == "feature_direction"
puts "- features alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "features alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/FEATURE_DIRECTION.md").include?("model_suitability_registry") &&
  File.read("docs/maintenance/PHASE24_FEATURE_DIRECTION.md").include?("Phase 24 does not implement")
puts "- phase 24 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 24 docs missing expected content" unless doc_ok

# During phase application, this verifier is expected to be untracked until the commit step.
# Do not call the phase 23 summary verifier here, because it correctly reports untracked
# verify-* files as curation candidates before they are staged.
stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-feature-direction-phase24.rb"]
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
