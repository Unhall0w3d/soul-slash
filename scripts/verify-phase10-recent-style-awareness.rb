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
  lib/soul_core/conversation_style_analyzer.rb
  lib/soul_core/conversation_style_controls.rb
  lib/soul_core/phase10_recent_style_awareness_assessor.rb
  docs/SOUL_PERSONALITY.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/RECENT_STYLE_AWARENESS.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE10_RECENT_STYLE_AWARENESS.md
  CHANGELOG.md
  scripts/verify-phase10-recent-style-awareness.rb
].freeze

RUBY_FILES = FILES.select { |path| path.end_with?(".rb") }.freeze

results = []
failures = []

def record(results, failures, label, ok, detail = nil)
  results << [label, ok, detail]
  failures << label unless ok
end

def capture(*command)
  Open3.capture3(*command, chdir: ROOT)
end

FILES.each do |path|
  record(results, failures, path, File.exist?(File.join(ROOT, path)))
end

RUBY_FILES.each do |path|
  stdout, stderr, status = capture("ruby", "-c", path)
  record(results, failures, "syntax #{path}", status.success?, [stdout, stderr].join.strip)
end

stdout, stderr, status = capture(
  "ruby",
  "bin/soul",
  "assess",
  "phase10-recent-style-awareness",
  "--json"
)
report = nil
begin
  report = JSON.parse(stdout) if status.success?
rescue JSON::ParserError
  report = nil
end
record(
  results,
  failures,
  "Phase 10B recent-style assessment JSON",
  status.success? && report.is_a?(Hash) && report["ok"] == true,
  [stdout, stderr].join.strip
)

stdout, stderr, status = capture(
  "ruby",
  "bin/soul",
  "assess",
  "phase10-recent-style-awareness"
)
record(
  results,
  failures,
  "Phase 10B recent-style assessment text rendering",
  status.success? && stdout.include?("Status: ready") && stdout.include?("Blockers\n- None"),
  [stdout, stderr].join.strip
)

source_checks = {
  "context analyzes recent style" => [
    "lib/soul_core/conversation_context_builder.rb",
    "@style_analyzer.analyze(messages: all_messages)"
  ],
  "context exposes style metadata" => [
    "lib/soul_core/conversation_context_builder.rb",
    '"persistent_style_profile" => style.fetch("persistent_style_profile")'
  ],
  "chat exposes deterministic style controls" => [
    "lib/soul_core/chat_responder.rb",
    "@style_controls.respond"
  ],
  "orchestrator keeps style inspection deterministic" => [
    "lib/soul_core/conversation_orchestrator.rb",
    "recent-style inspection remains deterministic and read-only"
  ],
  "roadmap records Phase 10B" => [
    "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
    "Delivered in Phase 10B"
  ],
  "roadmap restores clean Phase 11 boundary" => [
    "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
    "\n### Phase 11: Artifact-aware conversation\n"
  ],
  "personality doc links canonical style contract" => [
    "docs/SOUL_PERSONALITY.md",
    "docs/soul/RECENT_STYLE_AWARENESS.md"
  ]
}.freeze

source_checks.each do |label, (path, token)|
  content = File.exist?(File.join(ROOT, path)) ? File.read(File.join(ROOT, path)) : ""
  record(results, failures, label, content.include?(token))
end

roadmap_content = File.exist?(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md")) ?
  File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md")) : ""
record(
  results,
  failures,
  "roadmap has no fused fence and Phase 11 heading",
  !roadmap_content.include?("```### Phase 11:")
)

stdout, stderr, status = capture("git", "diff", "--check")
record(results, failures, "working-tree whitespace check", status.success?, [stdout, stderr].join.strip)
stdout, stderr, status = capture("git", "diff", "--cached", "--check")
record(results, failures, "staged whitespace check", status.success?, [stdout, stderr].join.strip)

stdout, stderr, status = capture("git", "ls-files")
tracked = stdout.lines.map(&:strip)
forbidden = tracked.select do |path|
  path == "README_PHASE10_RECENT_STYLE_AWARENESS.md" ||
    path == "docs/overlays/README_PHASE10_RECENT_STYLE_AWARENESS.md" ||
    path.include?("overlay_files/scripts/patch-phase10-recent-style-awareness.rb") ||
    path.end_with?("soul_phase10_recent_style_awareness_overlay.zip")
end
record(
  results,
  failures,
  "Phase 10B delivery artifacts remain untracked",
  status.success? && forbidden.empty?,
  forbidden.join(", ")
)

regression = File.join(ROOT, "scripts/verify-phase10-identity-style-foundation.rb")
if File.exist?(regression)
  stdout, stderr, status = capture("ruby", "scripts/verify-phase10-identity-style-foundation.rb")
  record(
    results,
    failures,
    "Phase 10A identity and style-policy regression",
    status.success?,
    [stdout, stderr].join.strip
  )
else
  record(results, failures, "Phase 10A identity and style-policy regression", false, "missing verifier")
end

puts "Conversational Soul Phase 10B recent-style awareness verification:"
results.each do |label, ok, detail|
  puts "- #{label}: #{ok ? 'ok' : 'missing'}"
  next if ok || detail.to_s.empty?

  puts
  puts detail
  puts
end

if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 10B recent-style awareness is ready."
  exit 0
end

puts "Verification failed:"
failures.each { |failure| puts "- #{failure}" }
exit 1
