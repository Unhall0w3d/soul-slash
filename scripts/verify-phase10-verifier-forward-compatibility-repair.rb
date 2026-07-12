#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("..", __dir__)
FILES = %w[
  lib/soul_core/phase10_identity_style_foundation_assessor.rb
  scripts/verify-phase10-identity-style-foundation.rb
  scripts/verify-phase10-recent-style-awareness.rb
  scripts/verify-phase9-memory-reflection-and-export-closeout.rb
  scripts/verify-phase10-inspectable-interests-closeout.rb
  scripts/verify-phase10-verifier-forward-compatibility-repair.rb
  docs/assessments/CONVERSATIONAL_SOUL_PHASE10_VERIFIER_FORWARD_COMPATIBILITY_REPAIR.md
].freeze

results = []
failures = []

def record(results, failures, label, ok, detail = nil, failure_kind: "failed")
  results << [label, ok, detail, failure_kind]
  failures << label unless ok
end

def capture(*command, env: {})
  Open3.capture3(env, *command, chdir: ROOT)
end

FILES.each do |path|
  exists = File.exist?(File.join(ROOT, path))
  record(results, failures, path, exists, "missing required file", failure_kind: "missing")
end

FILES.grep(/\.rb\z/).each do |path|
  stdout, stderr, status = capture("ruby", "-c", path)
  record(results, failures, "syntax #{path}", status.success?, [stdout, stderr].join.strip)
end

source_checks = {
  "identity assessor accepts reviewed interests without automatic invention" => [
    "lib/soul_core/phase10_identity_style_foundation_assessor.rb",
    "%w[not_declared_in_this_phase reviewed_registry]"
  ],
  "Phase 10A verifier has nested-regression guard" => [
    "scripts/verify-phase10-identity-style-foundation.rb",
    'SKIP_NESTED_REGRESSIONS = ENV["SOUL_SKIP_NESTED_REGRESSIONS"] == "1"'
  ],
  "Phase 10B verifier checks durable recent-style delivery" => [
    "scripts/verify-phase10-recent-style-awareness.rb",
    "roadmap retains Phase 10B recent-style awareness"
  ],
  "Phase 9 verifier stops recursive ancestry after Phase 10 closeout" => [
    "scripts/verify-phase9-memory-reflection-and-export-closeout.rb",
    "later_phase_complete"
  ],
  "Phase 10C invokes explicit bounded regressions" => [
    "scripts/verify-phase10-inspectable-interests-closeout.rb",
    '"Phase 9 memory closeout regression"'
  ],
  "verifiers distinguish failed from missing" => [
    "scripts/verify-phase10-inspectable-interests-closeout.rb",
    'failure_kind: "missing"'
  ]
}.freeze

source_checks.each do |label, (path, token)|
  content = File.exist?(File.join(ROOT, path)) ? File.read(File.join(ROOT, path), encoding: "UTF-8") : ""
  record(results, failures, label, content.include?(token))
end

bounded_env = { "SOUL_SKIP_NESTED_REGRESSIONS" => "1" }
{
  "Phase 9 bounded regression" => "scripts/verify-phase9-memory-reflection-and-export-closeout.rb",
  "Phase 10A bounded regression" => "scripts/verify-phase10-identity-style-foundation.rb",
  "Phase 10B bounded regression" => "scripts/verify-phase10-recent-style-awareness.rb"
}.each do |label, path|
  unless File.exist?(File.join(ROOT, path))
    record(results, failures, label, false, "missing verifier: #{path}", failure_kind: "missing")
    next
  end

  stdout, stderr, status = capture("ruby", path, env: bounded_env)
  record(results, failures, label, status.success?, [stdout, stderr].join.strip)
end

phase10c = "scripts/verify-phase10-inspectable-interests-closeout.rb"
if File.exist?(File.join(ROOT, phase10c))
  stdout, stderr, status = capture("ruby", phase10c)
  record(results, failures, "Phase 10C aggregate verification", status.success?, [stdout, stderr].join.strip)
else
  record(results, failures, "Phase 10C aggregate verification", false, "missing verifier: #{phase10c}", failure_kind: "missing")
end

stdout, stderr, status = capture("git", "diff", "--check")
record(results, failures, "working-tree whitespace check", status.success?, [stdout, stderr].join.strip)
stdout, stderr, status = capture("git", "diff", "--cached", "--check")
record(results, failures, "staged whitespace check", status.success?, [stdout, stderr].join.strip)

puts "Conversational Soul Phase 10 verifier forward-compatibility repair verification:"
results.each do |label, ok, detail, failure_kind|
  puts "- #{label}: #{ok ? 'ok' : failure_kind}"
  next if ok || detail.to_s.empty?

  puts
  puts detail
  puts
end

if failures.empty?
  puts "Verification complete."
  puts "Phase 10 verification is forward-compatible with the completed Phase 10 state."
  exit 0
end

puts "Verification failed:"
failures.each { |failure| puts "- #{failure}" }
exit 1
