
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha implementation task pack phase 29 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/alpha_implementation_task_pack_generator.rb",
  "scripts/verify-alpha-implementation-task-pack-phase29.rb",
  "docs/maintenance/PHASE29_ALPHA_IMPLEMENTATION_TASK_PACK.md",
  "docs/ALPHA_IMPLEMENTATION_TASK_PACK.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires implementation task pack generator" => app.include?('require_relative "alpha_implementation_task_pack_generator"'),
  "app exposes implementation-pack command" => app.include?('"implementation-pack", "task-pack", "alpha-task-pack"'),
  "app help includes implementation pack" => app.include?("improve implementation-pack")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

fixture = "Soul/runtime/verification/phase29-test-proposal"
FileUtils.rm_rf(fixture)
FileUtils.mkdir_p("#{fixture}/alpha")
File.write("#{fixture}/proposal.md", "# Phase 29 Test Proposal\n")
File.write("#{fixture}/alpha/README.md", "# Alpha Fixture\n")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "implementation-pack", "--proposal", fixture, "--json")
json = JSON.parse(stdout) rescue nil
expected_written = [
  "#{fixture}/alpha/implementation_task_pack.json",
  "#{fixture}/alpha/implementation_task_pack.md",
  "#{fixture}/alpha/codex_handoff_contract.json",
  "#{fixture}/alpha/human_review_checklist.md",
  "#{fixture}/alpha/rollback_plan.md"
]

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "alpha_implementation_task_pack" &&
  json["ok"] == true &&
  json["proposal_path"] == fixture &&
  json["codex_invoked"] == false &&
  json["implementation_written"] == false &&
  json["promotion_allowed"] == false &&
  json.dig("verification", "proposal_local_only") == true &&
  expected_written.all? { |path| File.exist?(path) }

puts "- JSON implementation-pack generation: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON implementation-pack generation failed: #{stderr} #{stdout}" unless json_ok

pack = JSON.parse(File.read("#{fixture}/alpha/implementation_task_pack.json")) rescue nil
pack_ok =
  pack &&
  pack.dig("task", "model_recommendation") == "gpt-5.5 medium" &&
  pack.key?("codex_handoff_contract") &&
  pack.key?("allowed_files") &&
  pack.key?("forbidden_files") &&
  pack.key?("acceptance_criteria") &&
  pack.key?("verifier_expectations") &&
  pack.key?("human_review_checklist") &&
  pack.key?("rollback_plan") &&
  pack.fetch("boundaries").include?("Do not invoke Codex.")

puts "- task pack shape: #{pack_ok ? 'ok' : 'missing'}"
errors << "task pack missing required shape" unless pack_ok

contract = JSON.parse(File.read("#{fixture}/alpha/codex_handoff_contract.json")) rescue nil
contract_ok =
  contract &&
  contract.dig("task", "model_recommendation") == "gpt-5.5 medium" &&
  contract.key?("allowed_files") &&
  contract.key?("forbidden_files") &&
  contract.key?("acceptance_criteria") &&
  contract.key?("verifier_expectations") &&
  contract.key?("security_boundaries") &&
  contract.key?("rollback_notes")

puts "- embedded codex handoff contract shape: #{contract_ok ? 'ok' : 'missing'}"
errors << "embedded codex handoff contract missing required shape" unless contract_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "task-pack", "--proposal", fixture)
text_ok =
  status.success? &&
  stdout.include?("Soul Alpha Implementation Task Pack") &&
  stdout.include?("Written files") &&
  stdout.include?("Do not invoke Codex.")

puts "- task-pack alias text output: #{text_ok ? 'ok' : 'missing'}"
errors << "task-pack alias text failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/ALPHA_IMPLEMENTATION_TASK_PACK.md").include?("does not invoke Codex") &&
  File.read("docs/maintenance/PHASE29_ALPHA_IMPLEMENTATION_TASK_PACK.md").include?("does not")
puts "- phase 29 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 29 docs missing expected content" unless doc_ok

FileUtils.rm_rf(fixture)

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-alpha-implementation-task-pack-phase29.rb"]
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
