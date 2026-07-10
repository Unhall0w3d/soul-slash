#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Downloads move-to-trash phase 62 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/downloads_move_to_trash_executor.rb
  lib/soul_core/downloads_move_to_trash_assessor.rb
  lib/soul_core/chat_responder.rb
  scripts/verify-downloads-move-to-trash-phase62.rb
  docs/maintenance/PHASE62_DOWNLOADS_MOVE_TO_TRASH.md
  docs/DOWNLOADS_MOVE_TO_TRASH.md
  docs/USABILITY_RETARGET_BACKLOG.md
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "downloads-move-to-trash", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["phase"] == 62 &&
  json["ok"] == true &&
  json.dig("verification", "explicit_confirmation_required") == true &&
  json.dig("verification", "approved_execution_succeeds") == true &&
  json.dig("verification", "candidate_moved_to_trash") == true &&
  json.dig("verification", "non_candidate_preserved") == true &&
  json.dig("verification", "trashinfo_created") == true &&
  json.dig("verification", "token_consumed") == true &&
  json.dig("verification", "history_recorded") == true

puts "- move-to-trash assessment uses temp data successfully: #{assessment_ok ? 'ok' : 'missing'}"
errors << "move-to-trash assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
blocked_ok =
  status.success? &&
  stdout.include?("Provide the approval token:")

puts "- chat requires explicit token: #{blocked_ok ? 'ok' : 'missing'}"
errors << "chat did not require token: #{stderr} #{stdout}" unless blocked_ok

fake_token = "0" * 32
stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash #{fake_token}")
confirm_block_ok =
  status.success? &&
  stdout.include?("explicit_confirmation_required") &&
  stdout.include?("Executed: false")

puts "- chat requires literal confirm: #{confirm_block_ok ? 'ok' : 'missing'}"
errors << "chat did not require confirm: #{stderr} #{stdout}" unless confirm_block_ok

doc_ok =
  File.read("docs/DOWNLOADS_MOVE_TO_TRASH.md").include?("trash, never permanent delete") &&
  File.read("docs/maintenance/PHASE62_DOWNLOADS_MOVE_TO_TRASH.md").include?("Phase 62") &&
  File.read("docs/USABILITY_RETARGET_BACKLOG.md").include?("Phase 62")

puts "- phase 62 docs/backlog: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 62 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-downloads-move-to-trash-phase62.rb"]
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
