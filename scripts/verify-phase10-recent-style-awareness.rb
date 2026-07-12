#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
SKIP_NESTED_REGRESSIONS = ENV["SOUL_SKIP_NESTED_REGRESSIONS"] == "1"

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

def record(results, failures, label, ok, detail = nil, failure_kind: "failed")
  results << [label, ok, detail, failure_kind]
  failures << label unless ok
end

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

def phase_section(markdown, heading, next_heading)
  start_index = markdown.index(heading)
  return "" unless start_index

  end_index = markdown.index(next_heading, start_index + heading.length)
  end_index ? markdown[start_index...end_index] : markdown[start_index..]
end

FILES.each do |path|
  exists = File.exist?(File.join(ROOT, path))
  record(results, failures, path, exists, "missing required file", failure_kind: "missing")
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
  "personality doc links canonical style contract" => [
    "docs/SOUL_PERSONALITY.md",
    "docs/soul/RECENT_STYLE_AWARENESS.md"
  ]
}.freeze

source_checks.each do |label, (path, token)|
  content = File.exist?(File.join(ROOT, path)) ? File.read(File.join(ROOT, path), encoding: "UTF-8") : ""
  record(results, failures, label, content.include?(token))
end

roadmap_path = File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md")
roadmap = File.exist?(roadmap_path) ? File.read(roadmap_path, encoding: "UTF-8") : ""
phase10 = phase_section(
  roadmap,
  "### Phase 10: Identity, interests, and variation",
  "### Phase 11: Artifact-aware conversation"
)
record(
  results,
  failures,
  "roadmap retains Phase 10B recent-style awareness",
  phase10.include?("Delivered in Phase 10B") || phase10.include?("bounded recent-assistant-turn style analysis")
)
record(
  results,
  failures,
  "roadmap records a forward-compatible Phase 10 status",
  phase10.match?(/Status:\s*```text\s*(?:in progress|complete)\s*```/m)
)
record(
  results,
  failures,
  "roadmap keeps a standalone Phase 11 boundary",
  roadmap.include?("\n### Phase 11: Artifact-aware conversation\n") && !roadmap.include?("```### Phase 11:")
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

unless SKIP_NESTED_REGRESSIONS
  regression = "scripts/verify-phase10-identity-style-foundation.rb"
  regression_path = File.join(ROOT, regression)
  if File.exist?(regression_path)
    stdout, stderr, status = capture_regression(regression)
    record(
      results,
      failures,
      "Phase 10A identity and style-policy regression",
      status.success?,
      [stdout, stderr].join.strip
    )
  else
    record(
      results,
      failures,
      "Phase 10A identity and style-policy regression",
      false,
      "missing verifier: #{regression}",
      failure_kind: "missing"
    )
  end
end

puts "Conversational Soul Phase 10B recent-style awareness verification:"
results.each do |label, ok, detail, failure_kind|
  puts "- #{label}: #{ok ? 'ok' : failure_kind}"
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
