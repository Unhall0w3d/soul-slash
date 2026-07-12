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
  lib/soul_core/conversation_identity_controls.rb
  lib/soul_core/phase10_identity_style_foundation_assessor.rb
  docs/SOUL_PERSONALITY.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/IDENTITY_AND_STYLE_POLICY.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE10_IDENTITY_STYLE_FOUNDATION.md
  CHANGELOG.md
  scripts/verify-phase10-identity-style-foundation.rb
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
  detail = [stdout, stderr].join.strip
  record(results, failures, "syntax #{path}", status.success?, detail)
end

stdout, stderr, status = capture(
  "ruby",
  "bin/soul",
  "assess",
  "phase10-identity-style-foundation",
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
  "Phase 10 identity assessment JSON",
  status.success? && report.is_a?(Hash) && report["ok"] == true,
  [stdout, stderr].join.strip
)

stdout, stderr, status = capture(
  "ruby",
  "bin/soul",
  "assess",
  "phase10-identity-style-foundation"
)
record(
  results,
  failures,
  "Phase 10 identity assessment text rendering",
  status.success? && stdout.include?("Status: ready") && stdout.include?("Blockers\n- None"),
  [stdout, stderr].join.strip
)

source_checks = {
  "context injects identity policy" => [
    "lib/soul_core/conversation_context_builder.rb",
    "render_system_guidance"
  ],
  "context exposes identity metadata" => [
    "lib/soul_core/conversation_context_builder.rb",
    '"profile_id" => identity.fetch("profile_id")'
  ],
  "chat identity response uses declared profile" => [
    "lib/soul_core/chat_responder.rb",
    "@identity_controls.summary"
  ],
  "orchestrator keeps identity inspection deterministic" => [
    "lib/soul_core/conversation_orchestrator.rb",
    "identity policy inspection remains deterministic and read-only"
  ],
  "roadmap marks Phase 10 in progress" => [
    "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
    "Delivered in Phase 10A"
  ],
  "personality document points to canonical runtime policy" => [
    "docs/SOUL_PERSONALITY.md",
    "docs/soul/IDENTITY_AND_STYLE_POLICY.md"
  ]
}.freeze

source_checks.each do |label, (path, token)|
  content = File.exist?(File.join(ROOT, path)) ? File.read(File.join(ROOT, path)) : ""
  record(results, failures, label, content.include?(token))
end

stdout, stderr, status = capture("git", "diff", "--check")
record(results, failures, "working-tree whitespace check", status.success?, [stdout, stderr].join.strip)
stdout, stderr, status = capture("git", "diff", "--cached", "--check")
record(results, failures, "staged whitespace check", status.success?, [stdout, stderr].join.strip)

stdout, stderr, status = capture("git", "ls-files")
tracked = stdout.lines.map(&:strip)
forbidden = tracked.select do |path|
  path == "README_PHASE10_IDENTITY_STYLE_FOUNDATION.md" ||
    path == "docs/overlays/README_PHASE10_IDENTITY_STYLE_FOUNDATION.md" ||
    path.include?("overlay_files/scripts/patch-phase10-identity-style-foundation.rb") ||
    path.end_with?("soul_phase10_identity_style_foundation_overlay.zip")
end
record(
  results,
  failures,
  "Phase 10 delivery artifacts remain untracked",
  status.success? && forbidden.empty?,
  forbidden.join(", ")
)

regression = File.join(ROOT, "scripts/verify-phase9-memory-reflection-and-export-closeout.rb")
if File.exist?(regression)
  stdout, stderr, status = capture("ruby", "scripts/verify-phase9-memory-reflection-and-export-closeout.rb")
  record(
    results,
    failures,
    "Phase 9 memory closeout regression",
    status.success?,
    [stdout, stderr].join.strip
  )
else
  record(results, failures, "Phase 9 memory closeout regression", false, "missing verifier")
end

puts "Conversational Soul Phase 10A identity and style-policy verification:"
results.each do |label, ok, detail|
  puts "- #{label}: #{ok ? 'ok' : 'missing'}"
  next if ok || detail.to_s.empty?

  puts
  puts detail
  puts
end

if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 10A identity and style-policy foundation is ready."
  exit 0
end

puts "Verification failed:"
failures.each { |failure| puts "- #{failure}" }
exit 1
