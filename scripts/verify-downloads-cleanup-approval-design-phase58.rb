#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Downloads cleanup approval design phase 58 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/downloads_cleanup_approval_design_assessor.rb
  scripts/verify-downloads-cleanup-approval-design-phase58.rb
  docs/maintenance/PHASE58_DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md
  docs/DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md
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
  app.include?('require_relative "downloads_cleanup_approval_design_assessor"') &&
  app.include?('"downloads-cleanup-approval-design", "cleanup-approval-design", "downloads-approval-design"')
puts "- app exposes approval design assessment: #{app_ok ? 'ok' : 'missing'}"
errors << "app does not expose approval design assessment" unless app_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "downloads-cleanup-approval-design", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "downloads_cleanup_approval_design" &&
  json["phase"] == 58 &&
  json["ok"] == true &&
  json.dig("verification", "all_required_stages_documented") == true &&
  json.dig("verification", "all_required_safety_rules_documented") == true &&
  json.dig("verification", "move_to_trash_remains_blocked") == true &&
  json.dig("verification", "design_only") == true

puts "- JSON approval design assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "approval design JSON failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "downloads-cleanup-approval-design")
text_ok =
  status.success? &&
  stdout.include?("Soul Downloads Cleanup Approval Design Assessment") &&
  stdout.include?("Status: ready")

puts "- text approval design assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "approval design text failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
blocked_ok =
  status.success? &&
  stdout.include?("Executed: false") &&
  stdout.include?("owner_confirmation_required")

puts "- downloads move/delete remains blocked: #{blocked_ok ? 'ok' : 'missing'}"
errors << "downloads move/delete block failed: #{stderr} #{stdout}" unless blocked_ok

doc_ok =
  File.read("docs/USABILITY_RETARGET_BACKLOG.md").include?("clear stopping point") &&
  File.read("docs/DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md").include?("single_use_token") &&
  File.read("docs/maintenance/PHASE58_DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md").include?("Phase 58")

puts "- phase 58 docs and backlog: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 58 docs/backlog missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-downloads-cleanup-approval-design-phase58.rb"]
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
