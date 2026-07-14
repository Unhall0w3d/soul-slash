
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha implementation review gate phase 30 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/alpha_implementation_review_gate.rb",
  "scripts/verify-alpha-implementation-review-gate-phase30.rb",
  "docs/maintenance/PHASE30_ALPHA_IMPLEMENTATION_REVIEW_GATE.md",
  "docs/ALPHA_IMPLEMENTATION_REVIEW_GATE.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires implementation review gate" => app.include?('require_relative "alpha_implementation_review_gate"'),
  "app exposes implementation-review command" => app.include?('"implementation-review", "implementation-gate", "review-implementation"'),
  "app help includes implementation review" => app.include?("improve implementation-review")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

fixture = "Soul/runtime/verification/phase30-test-proposal"
FileUtils.rm_rf(fixture)
FileUtils.mkdir_p("#{fixture}/alpha")
File.write("#{fixture}/proposal.md", "# Phase 30 Test Proposal\n")
File.write("#{fixture}/alpha/README.md", "# Alpha Fixture\n")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "implementation-pack", "--proposal", fixture, "--json")
pack_json = JSON.parse(stdout) rescue nil
pack_ok = status.success? && pack_json && pack_json["assessment"] == "alpha_implementation_task_pack"
puts "- fixture implementation-pack generation: #{pack_ok ? 'ok' : 'missing'}"
errors << "fixture implementation-pack generation failed: #{stderr} #{stdout}" unless pack_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "implementation-review", "--proposal", fixture, "--json")
review_json = JSON.parse(stdout) rescue nil
review_ok =
  status.success? &&
  review_json &&
  review_json["assessment"] == "alpha_implementation_review_gate" &&
  review_json["ok"] == true &&
  ["review_ready", "review_ready_with_warnings"].include?(review_json["readiness"]) &&
  review_json["promotion_allowed"] == false &&
  review_json["implementation_allowed"] == false &&
  review_json["codex_invoked"] == false &&
  review_json.dig("verification", "no_codex_invoked") == true &&
  review_json.dig("files", "missing").empty? &&
  review_json.dig("task_pack", "missing_keys").empty? &&
  review_json.dig("codex_handoff_contract", "missing_keys").empty?

puts "- JSON implementation-review gate pass: #{review_ok ? 'ok' : 'missing'}"
errors << "JSON implementation-review gate pass failed: #{stderr} #{stdout}" unless review_ok

FileUtils.rm("#{fixture}/alpha/rollback_plan.md")
stdout, stderr, _status = run_cmd("ruby", "bin/soul", "improve", "implementation-review", "--proposal", fixture, "--json")
blocked_json = JSON.parse(stdout) rescue nil
blocked_ok =
  blocked_json &&
  blocked_json["assessment"] == "alpha_implementation_review_gate" &&
  blocked_json["ok"] == false &&
  blocked_json["readiness"] == "blocked" &&
  blocked_json.dig("files", "missing").include?("rollback_plan.md") &&
  blocked_json.fetch("blockers").any? { |item| item.include?("rollback_plan.md") }

puts "- JSON implementation-review gate block: #{blocked_ok ? 'ok' : 'missing'}"
errors << "JSON implementation-review gate block failed: #{stderr} #{stdout}" unless blocked_ok

# Regenerate for alias text check.
run_cmd("ruby", "bin/soul", "improve", "implementation-pack", "--proposal", fixture, "--json")
stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "implementation-gate", "--proposal", fixture)
text_ok =
  status.success? &&
  stdout.include?("Soul Alpha Implementation Review Gate") &&
  stdout.include?("Readiness:") &&
  stdout.include?("Promotion allowed: false")

puts "- implementation-gate alias text output: #{text_ok ? 'ok' : 'missing'}"
errors << "implementation-gate alias text failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/ALPHA_IMPLEMENTATION_REVIEW_GATE.md").include?("does not invoke Codex") &&
  File.read("docs/maintenance/PHASE30_ALPHA_IMPLEMENTATION_REVIEW_GATE.md").include?("does not")
puts "- phase 30 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 30 docs missing expected content" unless doc_ok

FileUtils.rm_rf(fixture)

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-alpha-implementation-review-gate-phase30.rb"]
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
