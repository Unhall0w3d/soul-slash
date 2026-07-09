
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "first bounded Codex task phase 33 prompt repair verification:"

paths = [
  "lib/soul_core/first_bounded_codex_task.rb",
  "scripts/verify-first-bounded-codex-task-phase33.rb",
  "docs/maintenance/PHASE33_FIRST_BOUNDED_CODEX_TASK_PROMPT_REPAIR.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
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
  expected_files.all? { |path| File.exist?(path) }

puts "- JSON bounded Codex task generation: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON bounded Codex task generation failed: #{stderr} #{stdout}" unless json_ok

contract = JSON.parse(File.read("Soul/codex/tasks/phase33_first_bounded_task/contract.json")) rescue nil
contract_ok =
  contract &&
  contract.dig("task", "model_recommendation") == "gpt-5.5 medium" &&
  contract.fetch("allowed_files").include?("docs/CODEX_DRY_RUN_FIXTURE_PACK.md") &&
  contract.fetch("allowed_files").include?("docs/CODEX_DRY_RUN_REVIEW.md") &&
  contract.fetch("allowed_files").include?("docs/fixtures/codex_dry_run/README.md") &&
  contract.dig("output_format", "required_sections").include?("proposed_documentation_change") &&
  contract.dig("output_format", "field_notes", "files_changed").include?("would change if later applied by a human")

puts "- repaired contract usefulness fields: #{contract_ok ? 'ok' : 'missing'}"
errors << "repaired contract missing usefulness fields" unless contract_ok

schema = JSON.parse(File.read("Soul/codex/tasks/phase33_first_bounded_task/expected_response_schema.json")) rescue nil
schema_ok =
  schema &&
  schema.key?("proposed_documentation_change") &&
  schema.dig("proposed_documentation_change", "proposed_text").include?("Exact proposed wording")

puts "- expected response schema includes proposed text: #{schema_ok ? 'ok' : 'missing'}"
errors << "expected response schema missing proposed_documentation_change" unless schema_ok

prompt = File.read("Soul/codex/tasks/phase33_first_bounded_task/codex_prompt.md")
prompt_ok =
  prompt.include?("proposed_documentation_change") &&
  prompt.include?("files this proposal would change if a human later applied it") &&
  prompt.include?("A structural response with only a summary is not sufficient.") &&
  prompt.include?("docs/CODEX_DRY_RUN_FIXTURE_PACK.md")

puts "- repaired prompt clarity: #{prompt_ok ? 'ok' : 'missing'}"
errors << "repaired prompt clarity missing expected content" unless prompt_ok

instructions = File.read("Soul/codex/tasks/phase33_first_bounded_task/local_review_instructions.md")
instructions_ok =
  instructions.include?("Inspect usefulness") &&
  instructions.include?("proposed_documentation_change.proposed_text") &&
  instructions.include?("reject the response and revise the prompt")

puts "- repaired local review instructions: #{instructions_ok ? 'ok' : 'missing'}"
errors << "repaired local review instructions missing expected content" unless instructions_ok

sample_response = {
  "summary" => "Add a short usage-order note to the fixture-pack documentation.",
  "files_changed" => ["docs/CODEX_DRY_RUN_FIXTURE_PACK.md"],
  "proposed_documentation_change" => {
    "target_file" => "docs/CODEX_DRY_RUN_FIXTURE_PACK.md",
    "change_type" => "add_section",
    "proposed_text" => "## Recommended usage order\n\nRun the fixture pack before using a real Codex task. Confirm the safe fixture passes and the blocked fixtures fail before pasting any real task into Codex.",
    "placement_notes" => "Add after the Purpose section."
  },
  "commands_to_verify" => [
    "ruby bin/soul assess codex-dry-run-review --contract Soul/codex/tasks/phase33_first_bounded_task/contract.json --response Soul/codex/tasks/phase33_first_bounded_task/sample_response.json --json"
  ],
  "risks" => ["A passing dry-run review does not prove the wording is good."],
  "rollback" => "Remove the added documentation section.",
  "human_review_notes" => "Inspect the exact proposed wording before applying anything."
}
File.write("Soul/codex/tasks/phase33_first_bounded_task/sample_response.json", JSON.pretty_generate(sample_response))

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-dry-run-review", "--contract", "Soul/codex/tasks/phase33_first_bounded_task/contract.json", "--response", "Soul/codex/tasks/phase33_first_bounded_task/sample_response.json", "--json")
review_json = JSON.parse(stdout) rescue nil
review_ok =
  status.success? &&
  review_json &&
  review_json["assessment"] == "codex_dry_run_review" &&
  review_json["ok"] == true &&
  review_json["readiness"] == "review_ready" &&
  review_json.dig("sections", "missing").empty? &&
  review_json.dig("files", "disallowed_files").empty?

puts "- repaired sample response passes dry-run review: #{review_ok ? 'ok' : 'missing'}"
errors << "repaired sample response failed dry-run review: #{stderr} #{stdout}" unless review_ok

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
