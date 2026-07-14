#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Approval token chat controls phase 60 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/approval_token_store.rb
  lib/soul_core/approval_token_chat_controls.rb
  lib/soul_core/approval_token_chat_controls_assessor.rb
  lib/soul_core/chat_responder.rb
  scripts/verify-approval-token-chat-controls-phase60.rb
  docs/maintenance/PHASE60_APPROVAL_TOKEN_CHAT_CONTROLS.md
  docs/APPROVAL_TOKEN_CHAT_CONTROLS.md
  docs/USABILITY_RETARGET_BACKLOG.md
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "approval-token-chat-controls", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["phase"] == 60 &&
  json["ok"] == true &&
  json.dig("verification", "approval_issues_token") == true &&
  json.dig("verification", "pending_list_works") == true &&
  json.dig("verification", "revoke_works") == true &&
  json.dig("verification", "preview_remains_non_mutating") == true &&
  json.dig("verification", "mutation_enabled") == false

puts "- approval chat controls assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "approval controls assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "approve downloads cleanup preview")
approve_ok =
  status.success? &&
  stdout.include?("Downloads cleanup preview approved.") &&
  stdout.include?("Mutation enabled: true") &&
  stdout.match?(/Token: [a-f0-9]{32}/)

puts "- chat approves cleanup preview: #{approve_ok ? 'ok' : 'missing'}"
errors << "chat approval failed: #{stderr} #{stdout}" unless approve_ok

token_id = stdout[/Token: ([a-f0-9]{32})/, 1]

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "pending approvals")
pending_ok =
  status.success? &&
  stdout.include?("Pending approvals") &&
  token_id &&
  stdout.include?(token_id)

puts "- chat lists pending approvals: #{pending_ok ? 'ok' : 'missing'}"
errors << "pending approvals failed: #{stderr} #{stdout}" unless pending_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "revoke approval #{token_id}")
revoke_ok =
  status.success? &&
  stdout.include?("Approval revoke result") &&
  stdout.include?("Status: revoked")

puts "- chat revokes approval: #{revoke_ok ? 'ok' : 'missing'}"
errors << "approval revoke failed: #{stderr} #{stdout}" unless revoke_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", "move approved downloads to trash")
blocked_ok =
  status.success? &&
  stdout.include?("Provide the approval token:") &&
  stdout.include?("<token> confirm")

puts "- downloads move/delete remains blocked: #{blocked_ok ? 'ok' : 'missing'}"
errors << "downloads move/delete block failed: #{stderr} #{stdout}" unless blocked_ok

stdout, stderr, status = run_cmd("git", "check-ignore", "Soul/runtime/approvals/approval_tokens.json")
ignore_ok = status.success?
puts "- approval runtime remains gitignored: #{ignore_ok ? 'ok' : 'missing'}"
errors << "approval runtime path not ignored: #{stderr} #{stdout}" unless ignore_ok

doc_ok =
  File.read("docs/APPROVAL_TOKEN_CHAT_CONTROLS.md").include?("approve downloads cleanup preview") &&
  File.read("docs/maintenance/PHASE60_APPROVAL_TOKEN_CHAT_CONTROLS.md").include?("Phase 60") &&
  File.read("docs/USABILITY_RETARGET_BACKLOG.md").include?("Phase 60")

puts "- phase 60 docs/backlog: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 60 docs/backlog missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-approval-token-chat-controls-phase60.rb"]
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
