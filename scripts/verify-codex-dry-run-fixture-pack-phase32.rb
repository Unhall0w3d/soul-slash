
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "codex dry-run fixture pack phase 32 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/codex_dry_run_fixture_pack.rb",
  "scripts/verify-codex-dry-run-fixture-pack-phase32.rb",
  "docs/maintenance/PHASE32_CODEX_DRY_RUN_FIXTURE_PACK.md",
  "docs/CODEX_DRY_RUN_FIXTURE_PACK.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires Codex fixture pack" => app.include?('require_relative "codex_dry_run_fixture_pack"'),
  "app exposes codex-fixtures command" => app.include?('"codex-fixtures", "codex-fixture-pack", "dry-run-fixtures"'),
  "app help includes codex fixtures" => app.include?("improve codex-fixtures")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf("docs/fixtures/codex_dry_run")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "codex-fixtures", "--json")
json = JSON.parse(stdout) rescue nil
expected_files = [
  "docs/fixtures/codex_dry_run/safe_contract.json",
  "docs/fixtures/codex_dry_run/safe_response.json",
  "docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json",
  "docs/fixtures/codex_dry_run/blocked_response_missing_sections.json",
  "docs/fixtures/codex_dry_run/README.md"
]

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "codex_dry_run_fixture_pack" &&
  json["ok"] == true &&
  json.dig("verification", "no_codex_invoked") == true &&
  json.dig("verification", "no_patches_applied") == true &&
  expected_files.all? { |path| File.exist?(path) }

puts "- JSON fixture generation: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON fixture generation failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-dry-run-review", "--contract", "docs/fixtures/codex_dry_run/safe_contract.json", "--response", "docs/fixtures/codex_dry_run/safe_response.json", "--json")
safe_json = JSON.parse(stdout) rescue nil
safe_ok =
  status.success? &&
  safe_json &&
  safe_json["assessment"] == "codex_dry_run_review" &&
  safe_json["ok"] == true &&
  safe_json["readiness"] == "review_ready"

puts "- safe fixture review passes: #{safe_ok ? 'ok' : 'missing'}"
errors << "safe fixture review failed: #{stderr} #{stdout}" unless safe_ok

stdout, stderr, _status = run_cmd("ruby", "bin/soul", "assess", "codex-dry-run-review", "--contract", "docs/fixtures/codex_dry_run/safe_contract.json", "--response", "docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json", "--json")
forbidden_json = JSON.parse(stdout) rescue nil
forbidden_ok =
  forbidden_json &&
  forbidden_json["assessment"] == "codex_dry_run_review" &&
  forbidden_json["ok"] == false &&
  forbidden_json["readiness"] == "blocked" &&
  forbidden_json.dig("files", "forbidden_hits").include?(".env")

puts "- forbidden fixture review blocks: #{forbidden_ok ? 'ok' : 'missing'}"
errors << "forbidden fixture review failed: #{stderr} #{stdout}" unless forbidden_ok

stdout, stderr, _status = run_cmd("ruby", "bin/soul", "assess", "codex-dry-run-review", "--contract", "docs/fixtures/codex_dry_run/safe_contract.json", "--response", "docs/fixtures/codex_dry_run/blocked_response_missing_sections.json", "--json")
missing_json = JSON.parse(stdout) rescue nil
missing_ok =
  missing_json &&
  missing_json["assessment"] == "codex_dry_run_review" &&
  missing_json["ok"] == false &&
  missing_json["readiness"] == "blocked" &&
  missing_json.dig("sections", "missing").include?("rollback")

puts "- missing sections fixture review blocks: #{missing_ok ? 'ok' : 'missing'}"
errors << "missing sections fixture review failed: #{stderr} #{stdout}" unless missing_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "dry-run-fixtures")
text_ok =
  status.success? &&
  stdout.include?("Soul Codex Dry-Run Fixture Pack") &&
  stdout.include?("safe_contract.json")

puts "- dry-run-fixtures alias text output: #{text_ok ? 'ok' : 'missing'}"
errors << "dry-run-fixtures alias text failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/CODEX_DRY_RUN_FIXTURE_PACK.md").include?("does not invoke Codex") &&
  File.read("docs/maintenance/PHASE32_CODEX_DRY_RUN_FIXTURE_PACK.md").include?("does not")
puts "- phase 32 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 32 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-codex-dry-run-fixture-pack-phase32.rb"]
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
