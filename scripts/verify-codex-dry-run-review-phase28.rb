
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

def write_json(path, object)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(object))
end

puts "codex dry-run review phase 28 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/codex_dry_run_review.rb",
  "scripts/verify-codex-dry-run-review-phase28.rb",
  "docs/maintenance/PHASE28_CODEX_DRY_RUN_REVIEW.md",
  "docs/CODEX_DRY_RUN_REVIEW.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires dry-run reviewer" => app.include?('require_relative "codex_dry_run_review"'),
  "app exposes codex dry-run review" => app.include?('"codex-dry-run-review", "codex-review", "handoff-review"'),
  "app help includes codex dry-run review" => app.include?("assess codex-dry-run-review")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf("Soul/codex")
contract_path = "Soul/codex/handoffs/test-contract.json"
good_response_path = "Soul/codex/responses/good-response.json"
bad_response_path = "Soul/codex/responses/bad-response.json"

contract = {
  "task" => {"id" => "test_task"},
  "repo_context" => {"project" => "Soul"},
  "allowed_files" => [
    "lib/soul_core/<new_feature>.rb",
    "scripts/verify-<feature>.rb",
    "docs/maintenance/<PHASE_DOC>.md",
    "docs/<FEATURE_DOC>.md"
  ],
  "forbidden_files" => [".env", ".env.*", "Soul/runtime/*", "models/*"],
  "acceptance_criteria" => ["Stay bounded."],
  "verifier_expectations" => ["Verifier exists."],
  "security_boundaries" => ["No secrets."],
  "output_format" => {"required_sections" => ["summary"]},
  "rollback_notes" => ["Revert changed files."]
}

good_response = {
  "summary" => "Propose a bounded implementation.",
  "files_changed" => [
    "lib/soul_core/example_feature.rb",
    "scripts/verify-example-feature.rb",
    "docs/maintenance/PHASE_EXAMPLE.md",
    "docs/EXAMPLE_FEATURE.md"
  ],
  "commands_to_verify" => ["ruby scripts/verify-example-feature.rb"],
  "risks" => ["Example risk."],
  "rollback" => "Revert listed files.",
  "human_review_notes" => "Review behavior and verifier."
}

bad_response = {
  "summary" => "Bad proposal.",
  "files_changed" => [".env", "lib/soul_core/example_feature.rb"]
}

write_json(contract_path, contract)
write_json(good_response_path, good_response)
write_json(bad_response_path, bad_response)

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-dry-run-review", "--contract", contract_path, "--response", good_response_path, "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "codex_dry_run_review" &&
  json["ok"] == true &&
  json["readiness"] == "review_ready" &&
  json.dig("verification", "no_codex_invoked") == true &&
  json.dig("verification", "no_patches_applied") == true &&
  json.dig("files", "disallowed_files").empty? &&
  json.dig("sections", "missing").empty?

puts "- JSON dry-run review pass: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON dry-run review pass failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, _status = run_cmd("ruby", "bin/soul", "assess", "codex-dry-run-review", "--contract", contract_path, "--response", bad_response_path, "--json")
bad_json = JSON.parse(stdout) rescue nil
bad_ok =
  bad_json &&
  bad_json["assessment"] == "codex_dry_run_review" &&
  bad_json["ok"] == false &&
  bad_json["readiness"] == "blocked" &&
  bad_json.dig("files", "forbidden_hits").include?(".env") &&
  bad_json.dig("sections", "missing").include?("rollback") &&
  bad_json.fetch("blockers").any? { |item| item.include?("forbidden files") || item.include?("forbidden") }

puts "- JSON dry-run review block: #{bad_ok ? 'ok' : 'missing'}"
errors << "JSON dry-run review block failed: #{stderr} #{stdout}" unless bad_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-review", "--contract", contract_path, "--response", good_response_path)
text_ok =
  status.success? &&
  stdout.include?("Soul Codex Dry-Run Review") &&
  stdout.include?("Readiness: review_ready") &&
  stdout.include?("Verification")

puts "- codex-review alias text output: #{text_ok ? 'ok' : 'missing'}"
errors << "codex-review alias text failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/CODEX_DRY_RUN_REVIEW.md").include?("does not apply patches") &&
  File.read("docs/maintenance/PHASE28_CODEX_DRY_RUN_REVIEW.md").include?("does not")
puts "- phase 28 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 28 docs missing expected content" unless doc_ok

FileUtils.rm_rf("Soul/codex")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-codex-dry-run-review-phase28.rb"]
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
