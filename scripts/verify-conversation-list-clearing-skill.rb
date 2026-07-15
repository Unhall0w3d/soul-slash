#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Soul conversation-list clearing skill verification:"

required = %w[
  Soul/skills/chats/REVIEW.md
  Soul/skills/chats/clear.rb
  Soul/skills/chats/clear_skill.yaml
  docs/soul/PHASE12C_CONVERSATION_CLEARING_AMENDMENT.md
  lib/soul_core/conversation_clear_service.rb
  lib/soul_core/conversation_clear_service_assessor.rb
  scripts/verify-conversation-list-clearing-skill.rb
]
required.each { |path| check(path, File.file?(path), errors) }

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "conversation-list-clearing", "--json")
report = JSON.parse(stdout) rescue nil
assessment_ok = status.success? && report && report["ok"] == true && report["assessment"] == "conversation_list_clearing_skill" && report.fetch("verification", {}).length == 17 && report.fetch("verification", {}).values.all?(true) && report["risk_class"] == "Class 3: Local user-data modification" && report["human_review_required"] == true
check("conversation clearing assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "conversation-list-clearing")
check("conversation clearing assessment text", status.success? && stdout.include?("Status: candidate_ready") && stdout.include?("Blockers\n- None"), errors)

registry = File.read("Soul/skills/registry.yaml")
service = File.read("lib/soul_core/conversation_clear_service.rb")
dashboard = File.read("assets/dashboard/dashboard.js")
check("skill is registered as approval-gated local write", registry.include?("chats.clear:") && registry.include?("confirmation_phrase: CLEAR_CONVERSATIONS") && registry.include?("requires_approval: true"), errors)
check("service uses archival metadata and match digest", service.include?("@store.archive") && service.include?("expected_digest") && service.include?("MAX_MATCHES = 500") && !service.match?(/File\.(?:delete|unlink|truncate)/), errors)
check("dashboard performs exact multi-selection preview before execute", dashboard.index('callSoul("chats.clear.preview"') < dashboard.index('callSoul("chats.clear.execute"') && dashboard.include?("Transcript files remain stored") && dashboard.include?("chat_ids: selectedClearChatIds()"), errors)

review = File.read("Soul/skills/chats/REVIEW.md")
review_sections = ["## Implementation summary", "## Files changed", "## Commands run", "## Deterministic test results", "## Local LLM eval results", "## Memory keys", "## Lifecycle states touched", "## Safety and persistence check", "## Known weaknesses", "## Human review checklist", "## Human review outcome"]
check("review artifact contains required sections", review_sections.all? { |heading| review.include?(heading) }, errors)

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase12c-foreground-dashboard.rb")
check("Phase 12C and earlier regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Conversation-list clearing is candidate-ready for human review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
