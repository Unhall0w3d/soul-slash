#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 11C bounded artifact creation verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/approval_token_store.rb
  lib/soul_core/conversation_artifact_contract.rb
  lib/soul_core/conversation_artifact_store.rb
  lib/soul_core/conversation_artifact_inspector.rb
  lib/soul_core/conversation_artifact_operation_store.rb
  lib/soul_core/conversation_artifact_creation_service.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_orchestration_contract.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/phase11c_bounded_artifact_creation_assessor.rb
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION_BRIEF.md
  docs/soul/BOUNDED_ARTIFACT_CREATION_AND_REVISION.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION.md
  scripts/verify-phase11c-bounded-artifact-creation.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3(
  "ruby", "bin/soul", "assess", "phase11c-bounded-artifact-creation", "--json"
)
report = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  report &&
  report["ok"] == true &&
  report["assessment"] == "phase11c_bounded_artifact_creation" &&
  report["phase"] == "11C" &&
  report["risk_class"] == "Class 2: Local state write, non-destructive" &&
  report.fetch("verification", {}).values.all?(true) &&
  report.fetch("lifecycle_states", []).sort == %w[awaiting_input blocked_for_human_review canceled complete failed].sort &&
  report["human_review_required"] == true
check("Phase 11C assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby", "bin/soul", "assess", "phase11c-bounded-artifact-creation"
)
text_ok =
  status.success? &&
  stdout.include?("Soul Phase 11C Bounded Artifact Creation Assessment") &&
  stdout.include?("Status: candidate_ready") &&
  stdout.include?("Blockers\n- None")
check("Phase 11C assessment text", text_ok, errors)
unless text_ok
  warn stderr
  warn stdout
end

service = File.read("lib/soul_core/conversation_artifact_creation_service.rb")
operation_store = File.read("lib/soul_core/conversation_artifact_operation_store.rb")
context_builder = File.read("lib/soul_core/conversation_context_builder.rb")
contract = File.read("lib/soul_core/conversation_artifact_contract.rb")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
brief = File.read("docs/soul/PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION_BRIEF.md")
review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION.md")

check("write uses exclusive no-follow open", service.include?("File::EXCL | File::NOFOLLOW"), errors)
check("write verifies exact bytes and digest", service.include?("verify_created_file") && service.include?("Digest::SHA256.hexdigest(bytes)"), errors)
check("approval scope binds source and target", service.include?('"source_sha256"') && service.include?('"target_path"') && service.include?("scope_for"), errors)
check("terminal operation state removes draft content", operation_store.include?('record.delete("content")'), errors)
check("approval tokens are redacted from model context", context_builder.include?("REDACTED_APPROVAL_TOKEN") && context_builder.include?("sanitize_approval_tokens"), errors)
check("registration hashes a no-follow file handle", contract.include?("measure_regular_file") && contract.include?("File::RDONLY | File::NOFOLLOW"), errors)
check("cloud provider is excluded", service.include?("LOCAL_PROVIDER_CLASSES") && service.include?("cloud providers are not allowed"), errors)
check("roadmap records Phase 11C delivery", roadmap.include?("Delivered in Phase 11C"), errors)
check("approved brief remains explicit", brief.include?("implementation_authorized: yes") && brief.include?("Outcome: approved"), errors)

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

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase11-bounded-artifact-inspection.rb")
check("Phase 11B regression", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase11c-readiness.rb")
check("Phase 11C readiness regression", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 11C bounded artifact creation is candidate-ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
