
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "model suitability phase 25 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/model_suitability_assessor.rb",
  "scripts/verify-model-suitability-phase25.rb",
  "docs/maintenance/PHASE25_MODEL_SUITABILITY.md",
  "docs/MODEL_SUITABILITY.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires model suitability assessor" => app.include?('require_relative "model_suitability_assessor"'),
  "app exposes model-suitability assessment" => app.include?('"model-suitability", "models-suitability", "suitability"'),
  "app help includes model suitability" => app.include?("assess model-suitability")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "model-suitability", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "model_suitability" &&
  json["read_only"] == true &&
  json["known_tasks"].include?("coding") &&
  json["known_tasks"].include?("speech_to_text") &&
  json["providers"].any? { |provider| provider["id"] == "approved_cloud_llm" } &&
  json.dig("verification", "advisory_only") == true &&
  json.dig("verification", "no_models_downloaded") == true &&
  json.dig("verification", "no_secrets_read") == true

puts "- JSON model suitability assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON model suitability failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "model-suitability", "--task", "coding", "--json")
task_json = JSON.parse(stdout) rescue nil
task_ok =
  status.success? &&
  task_json &&
  task_json["selected_task"] == "coding" &&
  task_json["tasks"].keys == ["coding"] &&
  task_json.dig("suitability", "coding").any? { |entry| entry["provider_id"] == "approved_cloud_llm" }

puts "- task-filtered model suitability assessment: #{task_ok ? 'ok' : 'missing'}"
errors << "task-filtered model suitability failed: #{stderr} #{stdout}" unless task_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "model-suitability")
text_ok =
  status.success? &&
  stdout.include?("Soul Model Suitability Assessment") &&
  stdout.include?("Known tasks") &&
  stdout.include?("Suitability")

puts "- text model suitability assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text model suitability failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "suitability", "--task", "speech-to-text", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "model_suitability" &&
  alias_json["selected_task"] == "speech_to_text"

puts "- suitability alias and hyphenated task: #{alias_ok ? 'ok' : 'missing'}"
errors << "suitability alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/MODEL_SUITABILITY.md").include?("Codex or cloud coding tasks") &&
  File.read("docs/maintenance/PHASE25_MODEL_SUITABILITY.md").include?("advisory only")
puts "- phase 25 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 25 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-model-suitability-phase25.rb"]
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
