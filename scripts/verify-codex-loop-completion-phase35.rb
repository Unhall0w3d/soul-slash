
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Codex loop completion phase 35 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/codex_loop_completion_assessor.rb",
  "scripts/verify-codex-loop-completion-phase35.rb",
  "docs/maintenance/PHASE35_CODEX_LOOP_COMPLETION.md",
  "docs/CODEX_LOOP_COMPLETION.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_checks = {
  "app requires Codex loop completion assessor" => app.include?('require_relative "codex_loop_completion_assessor"'),
  "app exposes codex-loop assessment" => app.include?('"codex-loop", "codex-loop-completion", "bounded-codex-loop"'),
  "app help includes codex-loop" => app.include?("ruby bin/soul assess codex-loop")
}

app_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-loop", "--json")
json = JSON.parse(stdout) rescue nil

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "codex_loop_completion" &&
  json["ok"] == true &&
  json["status"] == "first_bounded_codex_loop_complete" &&
  json.dig("summary", "complete") == true &&
  json.fetch("missing_source_files").empty? &&
  json.fetch("missing_docs").empty? &&
  json.fetch("missing_fixtures").empty? &&
  json.fetch("missing_routes").empty? &&
  json.dig("documentation_checks", "preflight_section") == true &&
  json.dig("documentation_checks", "safe_fixture_expected") == true &&
  json.dig("documentation_checks", "blocked_fixture_expected") == true &&
  json.dig("documentation_checks", "no_auto_apply_warning") == true &&
  json.dig("verification", "no_codex_invoked") == true &&
  json.dig("verification", "no_patches_applied") == true &&
  json.dig("verification", "no_promotion_performed") == true

puts "- JSON codex-loop assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON codex-loop assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-loop")
text_ok =
  status.success? &&
  stdout.include?("Soul Codex Loop Completion Assessment") &&
  stdout.include?("Status: first_bounded_codex_loop_complete") &&
  stdout.include?("Phase 34: human_applied_doc_change")

puts "- text codex-loop assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text codex-loop assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "bounded-codex-loop", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "codex_loop_completion" &&
  alias_json["status"] == "first_bounded_codex_loop_complete"

puts "- bounded-codex-loop alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "bounded-codex-loop alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/CODEX_LOOP_COMPLETION.md").include?("first bounded Codex loop") &&
  File.read("docs/maintenance/PHASE35_CODEX_LOOP_COMPLETION.md").include?("Phase 35")
puts "- phase 35 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 35 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-codex-loop-completion-phase35.rb"]
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
