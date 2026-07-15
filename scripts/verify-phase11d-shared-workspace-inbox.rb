#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 11D shared workspace and artifact inbox verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/conversation_artifact_store.rb
  lib/soul_core/conversation_artifact_inbox_store.rb
  lib/soul_core/conversation_workspace_service.rb
  lib/soul_core/conversation_workspace_controls.rb
  lib/soul_core/conversation_artifact_creation_service.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/phase11d_shared_workspace_inbox_assessor.rb
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/PHASE11D_SHARED_WORKSPACE_INBOX_BRIEF.md
  docs/soul/SHARED_WORKSPACE_AND_ARTIFACT_INBOX.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE11D_SHARED_WORKSPACE_INBOX.md
  scripts/verify-phase11d-shared-workspace-inbox.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3(
  "ruby", "bin/soul", "assess", "phase11d-shared-workspace-inbox", "--json"
)
report = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  report &&
  report["ok"] == true &&
  report["assessment"] == "phase11d_shared_workspace_inbox" &&
  report["phase"] == "11D" &&
  report["risk_class"] == "Class 2: Local state write, non-destructive" &&
  report.fetch("verification", {}).values.all?(true) &&
  report.fetch("lifecycle_states", []).sort == %w[awaiting_input blocked_for_human_review canceled complete failed].sort &&
  report["human_review_required"] == true
check("Phase 11D assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby", "bin/soul", "assess", "phase11d-shared-workspace-inbox"
)
text_ok =
  status.success? &&
  stdout.include?("Soul Phase 11D Shared Workspace and Artifact Inbox Assessment") &&
  stdout.include?("Status: candidate_ready") &&
  stdout.include?("Blockers\n- None")
check("Phase 11D assessment text", text_ok, errors)
unless text_ok
  warn stderr
  warn stdout
end

inbox_store = File.read("lib/soul_core/conversation_artifact_inbox_store.rb")
workspace_service = File.read("lib/soul_core/conversation_workspace_service.rb")
creation_service = File.read("lib/soul_core/conversation_artifact_creation_service.rb")
review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE11D_SHARED_WORKSPACE_INBOX.md")
brief = File.read("docs/soul/PHASE11D_SHARED_WORKSPACE_INBOX_BRIEF.md")

check("inbox store is append-only and locked", inbox_store.include?("File::LOCK_EX") && !inbox_store.include?("File::TRUNC"), errors)
check("workspace cap is explicit", workspace_service.include?("MAX_RECORDS = 50"), errors)
check("workspace projection is metadata-only", workspace_service.include?('"metadata_only" => true') && workspace_service.include?('"content_read" => false'), errors)
check("Phase 11C preserves delivery failure separately", creation_service.include?("deliver_created_artifact") && creation_service.include?('"delivery_state" => "failed"'), errors)
check("approved brief remains explicit", brief.include?("implementation_authorized: yes") && brief.include?("Outcome: approved"), errors)

forbidden = %w[Thread.new TCPServer HTTPServer WEBrick cron systemctl inotify watcher polling]
source = [inbox_store, workspace_service, File.read("lib/soul_core/conversation_workspace_controls.rb")].join("\n")
check("no persistent or background source primitives", forbidden.none? { |needle| source.include?(needle) }, errors)

review_sections = [
  "## Implementation summary",
  "## Files changed",
  "## Commands run",
  "## Deterministic test results",
  "## Local LLM eval results",
  "## Memory keys",
  "## Lifecycle states touched",
  "## Risk classification",
  "## Safety and persistence check",
  "## Known weaknesses",
  "## Human review checklist",
  "## Human review outcome"
]
check("review artifact contains required sections", review_sections.all? { |heading| review.include?(heading) }, errors)

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase11c-bounded-artifact-creation.rb")
check("Phase 11C and earlier artifact regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 11D shared workspace and artifact inbox is candidate-ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
