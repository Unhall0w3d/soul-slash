
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "model suitability policy phase 26 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/model_suitability_policy_assessor.rb",
  "scripts/verify-model-suitability-policy-phase26.rb",
  "docs/maintenance/PHASE26_MODEL_SUITABILITY_POLICY.md",
  "docs/MODEL_SUITABILITY_POLICY.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires model suitability policy assessor" => app.include?('require_relative "model_suitability_policy_assessor"'),
  "app exposes model-policy assessment" => app.include?('"model-policy", "model-suitability-policy", "suitability-policy"'),
  "app help includes model policy" => app.include?("assess model-policy")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "model-policy", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "model_suitability_policy" &&
  json["read_only"] == true &&
  json.dig("policy_tiers", "local_only", "cloud_allowed") == false &&
  json.dig("task_policy", "speech_to_text", "tier") == "local_only" &&
  json.dig("task_policy", "coding", "tier") == "approval_required" &&
  json.dig("codex_boundary", "recommended_model") == "gpt-5.5 medium" &&
  json.dig("verification", "no_cloud_routing_enabled") == true

puts "- JSON model policy assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON model policy failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "model-policy", "--task", "coding", "--json")
task_json = JSON.parse(stdout) rescue nil
task_ok =
  status.success? &&
  task_json &&
  task_json["selected_task"] == "coding" &&
  task_json["task_policy"].keys == ["coding"] &&
  task_json.dig("task_policy", "coding", "tier") == "approval_required"

puts "- task-filtered model policy assessment: #{task_ok ? 'ok' : 'missing'}"
errors << "task-filtered model policy failed: #{stderr} #{stdout}" unless task_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "suitability-policy", "--task", "speech-to-text", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "model_suitability_policy" &&
  alias_json["selected_task"] == "speech_to_text" &&
  alias_json.dig("task_policy", "speech_to_text", "tier") == "local_only"

puts "- suitability-policy alias and hyphenated task: #{alias_ok ? 'ok' : 'missing'}"
errors << "suitability-policy alias failed: #{stderr} #{stdout}" unless alias_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "model-policy")
text_ok =
  status.success? &&
  stdout.include?("Soul Model Suitability Policy Assessment") &&
  stdout.include?("Codex boundary") &&
  stdout.include?("gpt-5.5 medium")

puts "- text model policy assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text model policy failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/MODEL_SUITABILITY_POLICY.md").include?("Required Codex handoff fields") &&
  File.read("docs/maintenance/PHASE26_MODEL_SUITABILITY_POLICY.md").include?("Codex Handoff Contract")
puts "- phase 26 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 26 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-model-suitability-policy-phase26.rb"]
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
