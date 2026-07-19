#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
FILES = %w[
  lib/soul_core/app.rb
  lib/soul_core/chat_responder.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_identity_profile.rb
  lib/soul_core/conversation_interest_store.rb
  lib/soul_core/conversation_interest_controls.rb
  lib/soul_core/conversation_style_controls.rb
  lib/soul_core/phase10_inspectable_interests_closeout_assessor.rb
  lib/soul_core/repo_curation_assessor.rb
  docs/SOUL_PERSONALITY.md
  docs/BRANDING.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/REPOSITORY_HYGIENE.md
  docs/soul/IDENTITY_AND_STYLE_POLICY.md
  docs/soul/RECENT_STYLE_AWARENESS.md
  docs/soul/REVIEWED_INTERESTS.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE10_CLOSEOUT.md
  CHANGELOG.md
  scripts/verify-phase10-inspectable-interests-closeout.rb
].freeze

results = []
failures = []

def capture(*command)
  Open3.capture3(*command, chdir: ROOT)
end

def capture_regression(path)
  Open3.capture3(
    { "SOUL_SKIP_NESTED_REGRESSIONS" => "1" },
    "ruby",
    path,
    chdir: ROOT
  )
end

def record(results, failures, label, ok, detail = nil, failure_kind: "failed")
  results << [label, ok, detail, failure_kind]
  failures << label unless ok
end

FILES.each do |path|
  exists = File.exist?(File.join(ROOT, path))
  record(results, failures, path, exists, "missing required file", failure_kind: "missing")
end

FILES.grep(/\.rb\z/).each do |path|
  stdout, stderr, status = capture("ruby", "-c", path)
  record(results, failures, "syntax #{path}", status.success?, [stdout, stderr].join.strip)
end

stdout, stderr, status = capture("ruby", "bin/soul", "assess", "phase10-inspectable-interests-closeout", "--json")
report = JSON.parse(stdout) rescue nil
record(
  results,
  failures,
  "Phase 10C assessment JSON",
  status.success? && report.is_a?(Hash) && report["ok"] == true,
  [stdout, stderr].join.strip
)
stdout, stderr, status = capture("ruby", "bin/soul", "assess", "phase10-inspectable-interests-closeout")
record(
  results,
  failures,
  "Phase 10C assessment text",
  status.success? && stdout.include?("Status: ready") && stdout.include?("Blockers\n- None"),
  [stdout, stderr].join.strip
)

roadmap = File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"), encoding: "UTF-8")
phase_headings = roadmap.scan(/^### Phase \d+:/)
record(results, failures, "roadmap phase headings are unique", phase_headings.uniq.length == phase_headings.length)
record(results, failures, "roadmap fences are balanced", roadmap.lines.count { |line| line.strip.start_with?("```") }.even?)
record(
  results,
  failures,
  "roadmap has standalone Phase 11 heading",
  roadmap.include?("\n### Phase 11: Artifact-aware conversation\n") && !roadmap.include?("```### Phase 11")
)
record(
  results,
  failures,
  "roadmap marks Phase 10 complete",
  roadmap.match?(/### Phase 10:.*?Status:\s*```text\s*complete\s*```/m)
)
record(
  results,
  failures,
  "roadmap preserves completed Phase 11 and current interface progression",
  roadmap.include?("Phase 11 is complete.") && roadmap.include?("Phase 12D.3") && roadmap.include?("Phase 13 is the clear stopping point")
)

stdout, stderr, status = capture("git", "ls-files")
tracked = stdout.lines.map(&:strip)
tracked_overlays = tracked.select { |path| path.match?(%r{(?:\A|/)[^/]+_overlay/}) }
record(
  results,
  failures,
  "tracked extracted overlay directories are absent",
  status.success? && tracked_overlays.empty?,
  tracked_overlays.join(", ")
)
record(results, failures, "branding overlay is removed", !File.exist?(File.join(ROOT, "soul_branding_overlay")))
branding_doc = File.join(ROOT, "docs/BRANDING.md")
branding_text = File.file?(branding_doc) ? File.read(branding_doc, encoding: "UTF-8") : ""
record(
  results,
  failures,
  "branding document is canonical",
  File.file?(branding_doc) &&
    branding_text.include?("# Soul/ Branding") &&
    branding_text.include?("assets/brand/soul-slash-repo-header.png") &&
    branding_text.include?("assets/brand/character/soul-portrait-unmasked.png")
)

stdout, stderr, status = capture("git", "diff", "--check")
record(results, failures, "working-tree whitespace check", status.success?, [stdout, stderr].join.strip)
stdout, stderr, status = capture("git", "diff", "--cached", "--check")
record(results, failures, "staged whitespace check", status.success?, [stdout, stderr].join.strip)

regressions = {
  "Phase 10B recent-style awareness regression" => "scripts/verify-phase10-recent-style-awareness.rb",
  "Phase 10A identity and style-policy regression" => "scripts/verify-phase10-identity-style-foundation.rb",
  "Phase 9 memory closeout regression" => "scripts/verify-phase9-memory-reflection-and-export-closeout.rb"
}.freeze

regressions.each do |label, regression|
  regression_path = File.join(ROOT, regression)
  unless File.exist?(regression_path)
    record(
      results,
      failures,
      label,
      false,
      "missing verifier: #{regression}",
      failure_kind: "missing"
    )
    next
  end

  stdout, stderr, status = capture_regression(regression)
  record(results, failures, label, status.success?, [stdout, stderr].join.strip)
end

puts "Conversational Soul Phase 10C inspectable interests and closeout verification:"
results.each do |label, ok, detail, failure_kind|
  puts "- #{label}: #{ok ? 'ok' : failure_kind}"
  next if ok || detail.to_s.empty?

  puts
  puts detail
  puts
end

if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 10 is complete."
  exit 0
end

puts "Verification failed:"
failures.each { |failure| puts "- #{failure}" }
exit 1
