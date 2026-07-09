
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "apply Codex dry-run fixture documentation phase 34 verification:"

paths = [
  "docs/CODEX_DRY_RUN_FIXTURE_PACK.md",
  "scripts/verify-apply-codex-dry-run-fixture-doc-phase34.rb",
  "docs/maintenance/PHASE34_APPLY_CODEX_DRY_RUN_FIXTURE_DOC.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

doc = File.exist?("docs/CODEX_DRY_RUN_FIXTURE_PACK.md") ? File.read("docs/CODEX_DRY_RUN_FIXTURE_PACK.md") : ""

content_checks = {
  "preflight section exists" => doc.include?("## Before a real Codex task"),
  "safe fixture command present" => doc.include?("safe_response.json"),
  "forbidden fixture command present" => doc.include?("blocked_response_forbidden_file.json"),
  "missing sections fixture command present" => doc.include?("blocked_response_missing_sections.json"),
  "review_ready expectation present" => doc.include?("`review_ready`"),
  "blocked expectation present" => doc.include?("`blocked`"),
  "automatic application warning present" => doc.include?("Do not apply Codex output automatically."),
  "bash fence present" => doc.include?("```bash")
}

content_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd(
  "ruby",
  "bin/soul",
  "assess",
  "codex-dry-run-review",
  "--contract",
  "docs/fixtures/codex_dry_run/safe_contract.json",
  "--response",
  "docs/fixtures/codex_dry_run/safe_response.json",
  "--json"
)
safe_json = JSON.parse(stdout) rescue nil
safe_ok =
  status.success? &&
  safe_json &&
  safe_json["assessment"] == "codex_dry_run_review" &&
  safe_json["ok"] == true &&
  safe_json["readiness"] == "review_ready"

puts "- safe fixture still review_ready: #{safe_ok ? 'ok' : 'missing'}"
errors << "safe fixture review failed: #{stderr} #{stdout}" unless safe_ok

stdout, stderr, _status = run_cmd(
  "ruby",
  "bin/soul",
  "assess",
  "codex-dry-run-review",
  "--contract",
  "docs/fixtures/codex_dry_run/safe_contract.json",
  "--response",
  "docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json",
  "--json"
)
blocked_forbidden = JSON.parse(stdout) rescue nil
forbidden_ok =
  blocked_forbidden &&
  blocked_forbidden["assessment"] == "codex_dry_run_review" &&
  blocked_forbidden["ok"] == false &&
  blocked_forbidden["readiness"] == "blocked"

puts "- forbidden fixture still blocked: #{forbidden_ok ? 'ok' : 'missing'}"
errors << "forbidden fixture review failed: #{stderr} #{stdout}" unless forbidden_ok

stdout, stderr, _status = run_cmd(
  "ruby",
  "bin/soul",
  "assess",
  "codex-dry-run-review",
  "--contract",
  "docs/fixtures/codex_dry_run/safe_contract.json",
  "--response",
  "docs/fixtures/codex_dry_run/blocked_response_missing_sections.json",
  "--json"
)
blocked_missing = JSON.parse(stdout) rescue nil
missing_ok =
  blocked_missing &&
  blocked_missing["assessment"] == "codex_dry_run_review" &&
  blocked_missing["ok"] == false &&
  blocked_missing["readiness"] == "blocked"

puts "- missing sections fixture still blocked: #{missing_ok ? 'ok' : 'missing'}"
errors << "missing sections fixture review failed: #{stderr} #{stdout}" unless missing_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-apply-codex-dry-run-fixture-doc-phase34.rb"]
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
