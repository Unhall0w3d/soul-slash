#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Downloads move dry-run phase 61 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/downloads_move_dry_run_executor.rb
  lib/soul_core/downloads_move_dry_run_assessor.rb
  lib/soul_core/chat_responder.rb
  scripts/verify-downloads-move-dry-run-phase61.rb
  docs/maintenance/PHASE61_DOWNLOADS_MOVE_DRY_RUN.md
  docs/DOWNLOADS_MOVE_DRY_RUN.md
  docs/USABILITY_RETARGET_BACKLOG.md
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "downloads-move-dry-run", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["phase"] == 61 &&
  json["ok"] == true &&
  json.dig("verification", "dry_run_succeeds") == true &&
  json.dig("verification", "mutation_none") == true &&
  json.dig("verification", "token_not_consumed") == true &&
  json.dig("verification", "revoked_token_blocked") == true

puts "- downloads move dry-run assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "dry-run assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "approve downloads cleanup preview")
token_id = stdout[/Token: ([a-f0-9]{32})/, 1]
approve_ok = status.success? && token_id
puts "- chat creates approval token: #{approve_ok ? 'ok' : 'missing'}"
errors << "approval token creation failed: #{stderr} #{stdout}" unless approve_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "dry run downloads move #{token_id}")
dry_run_ok =
  status.success? &&
  stdout.include?("Downloads move dry-run complete.") &&
  stdout.include?("Mutation: none") &&
  stdout.include?("Token consumed: false") &&
  stdout.include?("Would move files:")

puts "- chat performs approved dry-run: #{dry_run_ok ? 'ok' : 'missing'}"
errors << "chat dry-run failed: #{stderr} #{stdout}" unless dry_run_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "pending approvals")
pending_ok = status.success? && token_id && stdout.include?(token_id)
puts "- dry-run leaves token pending: #{pending_ok ? 'ok' : 'missing'}"
errors << "dry-run consumed or hid token: #{stderr} #{stdout}" unless pending_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
blocked_ok = status.success? && stdout.include?("Executed: false") && stdout.include?("owner_confirmation_required")
puts "- real move remains blocked: #{blocked_ok ? 'ok' : 'missing'}"
errors << "real move was not blocked: #{stderr} #{stdout}" unless blocked_ok

doc_ok =
  File.read("docs/DOWNLOADS_MOVE_DRY_RUN.md").include?("dry run downloads move") &&
  File.read("docs/maintenance/PHASE61_DOWNLOADS_MOVE_DRY_RUN.md").include?("Phase 61") &&
  File.read("docs/USABILITY_RETARGET_BACKLOG.md").include?("Phase 61")

puts "- phase 61 docs/backlog: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 61 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-downloads-move-dry-run-phase61.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
curation_ok = status.success? && curation && curation.dig("counts", "tracked_overlay_notes").to_i == 0 && (untracked - allowed).empty?
puts "- repo curation remains clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if errors.empty?
  puts "Verification complete."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
