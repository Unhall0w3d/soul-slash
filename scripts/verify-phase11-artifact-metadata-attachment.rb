#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
PHASE = "Conversational Soul Phase 11A artifact metadata and attachment verification"

REQUIRED_FILES = %w[
  lib/soul_core/app.rb
  lib/soul_core/chat_responder.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_artifact_contract.rb
  lib/soul_core/conversation_artifact_store.rb
  lib/soul_core/conversation_artifact_decision_policy.rb
  lib/soul_core/conversation_artifact_controls.rb
  lib/soul_core/phase11_artifact_metadata_attachment_assessor.rb
  docs/ARCHITECTURE.md
  docs/INTERACTION_ARCHITECTURE.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/REPOSITORY_HYGIENE.md
  docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE11_ARTIFACT_FOUNDATION.md
  CHANGELOG.md
  .gitignore
  scripts/verify-phase11-artifact-metadata-attachment.rb
].freeze

RUBY_FILES = REQUIRED_FILES.select { |path| path.end_with?(".rb") }.freeze

results = []
failures = []

def record(results, failures, label, ok, detail = nil)
  results << [label, ok, detail]
  failures << label unless ok
end

def capture(*command, env: {})
  Open3.capture3(env, *command, chdir: ROOT)
end

def file_text(relative)
  File.read(File.join(ROOT, relative), encoding: "UTF-8")
end

puts "#{PHASE}:"

REQUIRED_FILES.each do |relative|
  ok = File.file?(File.join(ROOT, relative))
  record(results, failures, relative, ok)
end

RUBY_FILES.each do |relative|
  next unless File.file?(File.join(ROOT, relative))

  _stdout, _stderr, status = capture(RbConfig.ruby, "-c", relative)
  record(results, failures, "syntax #{relative}", status.success?)
end

if failures.empty?
  stdout, stderr, status = capture(RbConfig.ruby, "bin/soul", "assess", "phase11-artifact-metadata-attachment", "--json")
  parsed = status.success? ? JSON.parse(stdout) : nil
  record(
    results,
    failures,
    "Phase 11A assessment JSON",
    status.success? && parsed.is_a?(Hash) && parsed["ok"] == true && parsed["status"] == "ready",
    stderr.strip
  )

  stdout, stderr, status = capture(RbConfig.ruby, "bin/soul", "assess", "phase11-artifact-metadata-attachment")
  record(
    results,
    failures,
    "Phase 11A assessment text",
    status.success? && stdout.include?("Status: ready") && stdout.include?("Blockers\n- None"),
    stderr.strip
  )
end

if File.file?(File.join(ROOT, "lib/soul_core/conversation_orchestrator.rb"))
  source = file_text("lib/soul_core/conversation_orchestrator.rb")
  record(results, failures, "orchestrator uses artifact decision policy", source.include?("ConversationArtifactDecisionPolicy.new"))
  record(results, failures, "artifact controls remain deterministic", source.include?("artifact registration and attachment controls remain deterministic"))
  record(results, failures, "broad file keyword route removed", !source.include?("ARTIFACT_PATTERNS ="))
end

if File.file?(File.join(ROOT, "lib/soul_core/conversation_context_builder.rb"))
  source = file_text("lib/soul_core/conversation_context_builder.rb")
  record(results, failures, "context selects attached artifacts", source.include?("@artifact_store.context_for"))
  record(results, failures, "context injects metadata-only boundary", source.include?("Attached conversation artifacts (metadata only)"))
  record(results, failures, "context exposes artifact metadata", source.include?('"artifacts" => {'))
end

if File.file?(File.join(ROOT, "lib/soul_core/chat_responder.rb"))
  source = file_text("lib/soul_core/chat_responder.rb")
  record(results, failures, "chat exposes deterministic artifact controls", source.include?("@artifact_controls.respond"))
end

if File.file?(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"))
  roadmap = file_text("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
  headings = roadmap.scan(/^### Phase \d+:[^\n]+$/)
  record(results, failures, "roadmap phase headings are unique", headings.uniq.length == headings.length)
  record(results, failures, "roadmap fences are balanced", roadmap.scan(/^```/).length.even?)
  record(results, failures, "roadmap marks Phase 11 complete", roadmap.match?(/^### Phase 11: Artifact-aware conversation\s*$.*?^complete\s*$/m))
  record(results, failures, "roadmap keeps standalone Phase 12 heading", roadmap.match?(/^### Phase 12: Interface contract\s*$/))
  record(results, failures, "roadmap has no fused fence heading", !roadmap.match?(/^```### Phase /))
end

if File.file?(File.join(ROOT, ".gitignore"))
  ignored = capture("git", "check-ignore", "-q", "Soul/artifacts/conversation_artifacts.jsonl")[2].success?
  record(results, failures, "local artifact registry is ignored", ignored)
end

stdout, stderr, status = capture("git", "diff", "--check")
record(results, failures, "working-tree whitespace check", status.success?, [stdout, stderr].join.strip)
stdout, stderr, status = capture("git", "diff", "--cached", "--check")
record(results, failures, "staged whitespace check", status.success?, [stdout, stderr].join.strip)

tracked_delivery = capture(
  "git", "ls-files", "--",
  "README_PHASE11_ARTIFACT_METADATA_ATTACHMENT.md",
  "overlay_files/scripts/patch-phase11-artifact-metadata-attachment.rb"
)[0].lines.map(&:strip).reject(&:empty?)
record(results, failures, "Phase 11A delivery artifacts remain untracked", tracked_delivery.empty?, tracked_delivery.join(", "))

unless ENV["SOUL_SKIP_NESTED_REGRESSIONS"] == "1"
  regression = "scripts/verify-phase10-inspectable-interests-closeout.rb"
  if File.file?(File.join(ROOT, regression))
    stdout, stderr, status = capture(
      RbConfig.ruby,
      regression,
      env: { "SOUL_SKIP_NESTED_REGRESSIONS" => "1" }
    )
    record(results, failures, "Phase 10 closeout regression", status.success?, [stdout, stderr].join("\n").strip)
  else
    record(results, failures, "Phase 10 closeout regression", false, "missing")
  end
end

results.each do |label, ok, detail|
  status_label = ok ? "ok" : (detail.to_s == "missing" ? "missing" : "failed")
  puts "- #{label}: #{status_label}"
  puts detail unless ok || detail.to_s.empty?
end

if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 11A artifact foundation is ready."
  exit 0
end

warn "Verification failed:"
failures.each { |failure| warn "- #{failure}" }
exit 1
