
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "first bounded Codex task phase 33 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/first_bounded_codex_task.rb",
  "scripts/verify-first-bounded-codex-task-phase33.rb",
  "docs/maintenance/PHASE33_FIRST_BOUNDED_CODEX_TASK.md",
  "docs/FIRST_BOUNDED_CODEX_TASK.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires first bounded Codex task" => app.include?('require_relative "first_bounded_codex_task"'),
  "app exposes bounded-codex-task command" => app.include?('"bounded-codex-task", "first-codex-task", "codex-task"'),
  "app help includes bounded Codex task" => app.include?("improve bounded-codex-task")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf("Soul/codex/tasks/phase33_first_bounded_task")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "bounded-codex-task", "--json")
json = JSON.parse(stdout) rescue nil
expected_files = [
  "Soul/codex/tasks/phase33_first_bounded_task/contract.json",
  "Soul/codex/tasks/phase33_first_bounded_task/codex_prompt.md",
  "Soul/codex/tasks/phase33_first_bounded_task/expected_response_schema.json",
  "Soul/codex/tasks/phase33_first_bounded_task/local_review_instructions.md",
  "Soul/codex/tasks/phase33_first_bounded_task/README.md"
]

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "first_bounded_codex_task" &&
  json["ok"] == true &&
  json["recommended_model"] == "gpt-5.5 medium" &&
  json.dig("verification", "no_codex_invoked") == true &&
  json.dig("verification", "no_patches_applied") == true &&
  expected_files.all? { |path| File.exist?(path) }

puts "- JSON bounded Codex task generation: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON bounded Codex task generation failed: #{stderr} #{stdout}" unless json_ok

contract = JSON.parse(File.read("Soul/codex/tasks/phase33_first_bounded_task/contract.json")) rescue nil
contract_ok =
  contract &&
  contract.dig("task", "model_recommendation") == "gpt-5.5 medium" &&
  contract.dig("task", "id") == "phase33_fixture_doc_review" &&
  contract.fetch("allowed_files").include?("docs/fixtures/codex_dry_run/<FEATURE_DOC>.md") &&
  contract.fetch("forbidden_files").include?("lib/soul_core/*") &&
  contract.fetch("forbidden_files").include?("scripts/*") &&
  contract.fetch("security_boundaries").include?("Do not apply any output automatically.")

puts "- bounded contract shape: #{contract_ok ? 'ok' : 'missing'}"
errors << "bounded contract missing required shape" unless contract_ok

prompt = File.exist?("Soul/codex/tasks/phase33_first_bounded_task/codex_prompt.md") ? File.read("Soul/codex/tasks/phase33_first_bounded_task/codex_prompt.md") : ""
prompt_ok =
  prompt.include?("gpt-5.5 medium") &&
  prompt.include?("Return only JSON") &&
  prompt.include?("Do not edit code.") &&
  prompt.include?("docs/CODEX_DRY_RUN_FIXTURE_PACK.md")

puts "- Codex prompt boundaries: #{prompt_ok ? 'ok' : 'missing'}"
errors << "Codex prompt boundaries missing" unless prompt_ok

instructions = File.exist?("Soul/codex/tasks/phase33_first_bounded_task/local_review_instructions.md") ? File.read("Soul/codex/tasks/phase33_first_bounded_task/local_review_instructions.md") : ""
instructions_ok =
  instructions.include?("gpt-5.5 medium") &&
  instructions.include?("codex-dry-run-review") &&
  instructions.include?("does not mean the proposal is correct")

puts "- local review instructions: #{instructions_ok ? 'ok' : 'missing'}"
errors << "local review instructions missing expected content" unless instructions_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "codex-task")
text_ok =
  status.success? &&
  stdout.include?("Soul First Bounded Codex Task Package") &&
  stdout.include?("Recommended model: gpt-5.5 medium") &&
  stdout.include?("Review command template")

puts "- codex-task alias text output: #{text_ok ? 'ok' : 'missing'}"
errors << "codex-task alias text failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/FIRST_BOUNDED_CODEX_TASK.md").include?("does not invoke Codex") &&
  File.read("docs/maintenance/PHASE33_FIRST_BOUNDED_CODEX_TASK.md").include?("gpt-5.5 medium")
puts "- phase 33 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 33 docs missing expected content" unless doc_ok

FileUtils.rm_rf("Soul/codex/tasks/phase33_first_bounded_task")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-first-bounded-codex-task-phase33.rb"]
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
