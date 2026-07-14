#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
REQUIRED_FILES = %w[
  lib/soul_core/app.rb
  lib/soul_core/chat_responder.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_provider_registry.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_artifact_contract.rb
  lib/soul_core/conversation_artifact_store.rb
  lib/soul_core/conversation_artifact_decision_policy.rb
  lib/soul_core/conversation_artifact_controls.rb
  lib/soul_core/conversation_artifact_reference_resolver.rb
  lib/soul_core/conversation_artifact_inspector.rb
  lib/soul_core/phase11_bounded_artifact_inspection_assessor.rb
  docs/ARCHITECTURE.md
  docs/MILESTONES.md
  docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md
  docs/INTERACTION_ARCHITECTURE.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md
  docs/soul/BOUNDED_ARTIFACT_INSPECTION.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE11_BOUNDED_ARTIFACT_INSPECTION.md
  CHANGELOG.md
  scripts/verify-phase11-artifact-metadata-attachment.rb
  scripts/verify-phase11-bounded-artifact-inspection.rb
].freeze

results = []
failures = []

def capture(*command, env: {})
  Open3.capture3(env, *command, chdir: ROOT)
end

def record(results, failures, label, ok, detail = nil)
  results << [label, ok, detail]
  failures << label unless ok
end

puts "Conversational Soul Phase 11B bounded artifact inspection verification:"

REQUIRED_FILES.each do |relative|
  record(results, failures, relative, File.file?(File.join(ROOT, relative)))
end

REQUIRED_FILES.grep(/\.rb\z/).each do |relative|
  next unless File.file?(File.join(ROOT, relative))

  _stdout, stderr, status = capture(RbConfig.ruby, "-c", relative)
  record(results, failures, "syntax #{relative}", status.success?, stderr.strip)
end

if failures.empty?
  stdout, stderr, status = capture(RbConfig.ruby, "bin/soul", "assess", "phase11-bounded-artifact-inspection", "--json")
  parsed = status.success? ? JSON.parse(stdout) : nil
  record(
    results,
    failures,
    "Phase 11B assessment JSON",
    status.success? && parsed.is_a?(Hash) && parsed["ok"] == true && parsed["status"] == "ready",
    [stdout, stderr].join("\n").strip
  )

  stdout, stderr, status = capture(RbConfig.ruby, "bin/soul", "assess", "phase11-bounded-artifact-inspection")
  record(
    results,
    failures,
    "Phase 11B assessment text",
    status.success? && stdout.include?("Status: ready") && stdout.include?("Blockers\n- None"),
    [stdout, stderr].join("\n").strip
  )
end

inspector_path = File.join(ROOT, "lib/soul_core/conversation_artifact_inspector.rb")
if File.file?(inspector_path)
  source = File.read(inspector_path)
  record(results, failures, "inspection uses no-follow open", source.include?("File::NOFOLLOW"))
  record(results, failures, "inspection hashes exact bytes", source.include?("Digest::SHA256.hexdigest(bytes)"))
  record(results, failures, "inspection enforces provider privacy", source.include?("ConversationArtifactContract.provider_allowed?"))
  record(results, failures, "inspection supports explicit terminal states", %w[complete failed awaiting_input blocked_for_human_review].all? { |state| source.include?(state) })
end

review_path = File.join(ROOT, "docs/assessments/CONVERSATIONAL_SOUL_PHASE11_BOUNDED_ARTIFACT_INSPECTION.md")
if File.file?(review_path)
  review = File.read(review_path)
  required_sections = [
    "## Commands run", "## Deterministic test results", "## Local LLM eval results",
    "## Memory keys", "## Lifecycle states touched", "## Risk classification",
    "## Known weaknesses", "## Human review checklist"
  ]
  record(results, failures, "review artifact contains required sections", required_sections.all? { |heading| review.include?(heading) })
end

stdout, stderr, status = capture("git", "diff", "--check")
record(results, failures, "working-tree whitespace check", status.success?, [stdout, stderr].join.strip)
stdout, stderr, status = capture("git", "diff", "--cached", "--check")
record(results, failures, "staged whitespace check", status.success?, [stdout, stderr].join.strip)

unless ENV["SOUL_SKIP_NESTED_REGRESSIONS"] == "1"
  stdout, stderr, status = capture(
    RbConfig.ruby,
    "scripts/verify-phase11-artifact-metadata-attachment.rb",
    env: { "SOUL_SKIP_NESTED_REGRESSIONS" => "1" }
  )
  record(results, failures, "Phase 11A artifact foundation regression", status.success?, [stdout, stderr].join("\n").strip)
end

results.each do |label, ok, detail|
  puts "- #{label}: #{ok ? 'ok' : 'failed'}"
  puts detail unless ok || detail.to_s.empty?
end

if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 11B bounded artifact inspection is ready."
  exit 0
end

warn "Verification failed:"
failures.each { |failure| warn "- #{failure}" }
exit 1
