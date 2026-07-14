#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Approval token scaffold phase 59 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/approval_token_store.rb
  lib/soul_core/approval_token_store_assessor.rb
  scripts/verify-approval-token-store-phase59.rb
  docs/maintenance/PHASE59_APPROVAL_TOKEN_STORE.md
  docs/APPROVAL_TOKEN_STORE.md
  docs/USABILITY_RETARGET_BACKLOG.md
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_ok =
  app.include?('require_relative "approval_token_store"') &&
  app.include?('require_relative "approval_token_store_assessor"') &&
  app.include?('"approval-token-store", "approval-tokens", "downloads-approval-token"')

puts "- app exposes approval token assessment: #{app_ok ? 'ok' : 'missing'}"
errors << "app does not expose approval token assessment" unless app_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "approval-token-store", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "approval_token_store" &&
  json["phase"] == 59 &&
  json["ok"] == true &&
  json.dig("verification", "valid_token_accepted") == true &&
  json.dig("verification", "scope_binding_enforced") == true &&
  json.dig("verification", "single_use_enforced") == true &&
  json.dig("verification", "revocation_enforced") == true &&
  json.dig("verification", "expiry_enforced") == true &&
  json.dig("verification", "runtime_only_path") == true &&
  json.dig("verification", "mutation_enabled") == false

puts "- JSON approval token assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "approval token JSON failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "approval-token-store")
text_ok =
  status.success? &&
  stdout.include?("Soul Approval Token Store Assessment") &&
  stdout.include?("Status: ready")

puts "- text approval token assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "approval token text failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("git", "check-ignore", "Soul/runtime/approvals/approval_tokens.json")
ignore_ok = status.success?
puts "- approval token runtime path is gitignored: #{ignore_ok ? 'ok' : 'missing'}"
errors << "approval token runtime path is not gitignored: #{stderr} #{stdout}" unless ignore_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
blocked_ok =
  status.success? &&
  stdout.include?("Provide the approval token:") &&
  stdout.include?("<token> confirm")

puts "- downloads move/delete remains blocked: #{blocked_ok ? 'ok' : 'missing'}"
errors << "downloads move/delete block failed: #{stderr} #{stdout}" unless blocked_ok

doc_ok =
  File.read("docs/APPROVAL_TOKEN_STORE.md").include?("single-use") &&
  File.read("docs/maintenance/PHASE59_APPROVAL_TOKEN_STORE.md").include?("Phase 59") &&
  File.read("docs/USABILITY_RETARGET_BACKLOG.md").include?("Phase 59")

puts "- phase 59 docs/backlog: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 59 docs/backlog missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-approval-token-store-phase59.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  (untracked - allowed).empty?

puts "- repo curation remains clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if errors.empty?
  puts "Verification complete."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
