
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "codex handoff contract phase 27 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/codex_handoff_contract_assessor.rb",
  "scripts/verify-codex-handoff-contract-phase27.rb",
  "docs/maintenance/PHASE27_CODEX_HANDOFF_CONTRACT.md",
  "docs/CODEX_HANDOFF_CONTRACT.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires codex handoff assessor" => app.include?('require_relative "codex_handoff_contract_assessor"'),
  "app exposes codex-handoff assessment" => app.include?('"codex-handoff", "handoff-contract", "codex-contract"'),
  "app help includes codex handoff" => app.include?("assess codex-handoff")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf("Soul/codex/handoffs")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-handoff", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "codex_handoff_contract" &&
  json["read_only"] == true &&
  json["write_requested"] == false &&
  json["contract_path"].nil? &&
  json.dig("contract", "task", "model_recommendation") == "gpt-5.5 medium" &&
  json.dig("validation", "valid") == true &&
  json.dig("verification", "no_codex_invoked") == true &&
  json.dig("verification", "no_implementation_written") == true

puts "- JSON codex handoff assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON codex handoff failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-handoff")
text_ok =
  status.success? &&
  stdout.include?("Soul Codex Handoff Contract") &&
  stdout.include?("Required fields") &&
  stdout.include?("Forbidden files")

puts "- text codex handoff assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text codex handoff failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "codex-handoff", "--task", "model_suitability_registry", "--write", "--json")
write_json = JSON.parse(stdout) rescue nil
contract_path = write_json && write_json["contract_path"]
write_ok =
  status.success? &&
  write_json &&
  write_json["write_requested"] == true &&
  contract_path &&
  File.exist?(contract_path) &&
  write_json.dig("contract", "task", "id") == "model_suitability_registry"

puts "- writable codex handoff contract: #{write_ok ? 'ok' : 'missing'}"
errors << "writable codex handoff failed: #{stderr} #{stdout}" unless write_ok

if contract_path && File.exist?(contract_path)
  contract = JSON.parse(File.read(contract_path)) rescue nil
  contract_ok =
    contract &&
    contract.key?("allowed_files") &&
    contract.key?("forbidden_files") &&
    contract.key?("acceptance_criteria") &&
    contract.key?("verifier_expectations") &&
    contract.key?("security_boundaries") &&
    contract.key?("rollback_notes")
  puts "- written contract shape: #{contract_ok ? 'ok' : 'missing'}"
  errors << "written contract missing required shape" unless contract_ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "handoff-contract", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok = status.success? && alias_json && alias_json["assessment"] == "codex_handoff_contract"
puts "- handoff-contract alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "handoff-contract alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/CODEX_HANDOFF_CONTRACT.md").include?("Required fields") &&
  File.read("docs/maintenance/PHASE27_CODEX_HANDOFF_CONTRACT.md").include?("does not")
puts "- phase 27 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 27 docs missing expected content" unless doc_ok

FileUtils.rm_rf("Soul/codex/handoffs")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-codex-handoff-contract-phase27.rb"]
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
