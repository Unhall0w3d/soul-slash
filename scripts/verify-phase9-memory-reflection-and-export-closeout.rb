#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require_relative "../lib/soul_core/phase9_memory_reflection_and_export_closeout_assessor"

ROOT = File.expand_path("..", __dir__)
SKIP_NESTED_REGRESSIONS = ENV["SOUL_SKIP_NESTED_REGRESSIONS"] == "1"

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

required_files = [
  "lib/soul_core/conversation_memory_store.rb",
  "lib/soul_core/conversation_memory_controls.rb",
  "lib/soul_core/conversation_memory_reflection_bridge.rb",
  "lib/soul_core/conversation_memory_snapshot.rb",
  "lib/soul_core/conversation_memory_maintenance_controls.rb",
  "lib/soul_core/chat_responder.rb",
  "lib/soul_core/conversation_orchestrator.rb",
  "lib/soul_core/phase9_memory_reflection_and_export_closeout_assessor.rb",
  "lib/soul_core/app.rb",
  "docs/LAYERED_CONVERSATION_MEMORY.md",
  "docs/MEMORY_REFLECTION_BRIDGE_AND_EXPORT.md",
  "docs/maintenance/CONVERSATIONAL_SOUL_PHASE9_MEMORY_CLOSEOUT.md",
  "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
  "CHANGELOG.md",
  ".gitignore",
  "scripts/verify-phase9-memory-reflection-and-export-closeout.rb"
]

required_files.each do |relative_path|
  exists = File.exist?(File.join(ROOT, relative_path))
  record(results, failures, relative_path, exists, "missing required file", failure_kind: "missing")
end

required_files.select { |path| path.end_with?(".rb") }.each do |relative_path|
  stdout, stderr, status = capture("ruby", "-c", relative_path)
  record(results, failures, "syntax: #{relative_path}", status.success?, [stdout, stderr].join.strip)
end

assessor = SoulCore::Phase9MemoryReflectionAndExportCloseoutAssessor.new(root: ROOT)
report = assessor.assess
record(results, failures, "Phase 9 memory closeout assessment", report["ok"] == true, JSON.pretty_generate(report))
record(
  results,
  failures,
  "Phase 9 memory closeout text rendering",
  assessor.render(report).include?("Status: ready"),
  assessor.render(report)
)

roadmap = File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"), encoding: "UTF-8")
record(
  results,
  failures,
  "roadmap marks Phase 9 complete",
  roadmap.match?(/## Phase 9 — Layered Memory Foundation.*?Status:\s*complete/m)
)
record(
  results,
  failures,
  "roadmap keeps identity after memory",
  roadmap.include?("### Phase 10: Identity, interests, and variation")
)
record(
  results,
  failures,
  "roadmap records replay-verifiable export",
  roadmap.include?("replay-verifiable memory snapshot export")
)

changelog = File.read(File.join(ROOT, "CHANGELOG.md"), encoding: "UTF-8")
record(
  results,
  failures,
  "changelog records Phase 9 closeout",
  changelog.include?("approved-reflection candidate import") &&
    changelog.include?("replay-verifiable memory snapshots")
)

gitignore = File.read(File.join(ROOT, ".gitignore"), encoding: "UTF-8")
record(
  results,
  failures,
  "local memory exports are ignored",
  gitignore.lines.map(&:chomp).include?("Soul/memory/exports/*.json")
)

bridge = File.read(File.join(ROOT, "lib/soul_core/conversation_memory_reflection_bridge.rb"), encoding: "UTF-8")
record(
  results,
  failures,
  "reflection and memory approvals remain separate",
  bridge.include?("auto_approved") &&
    bridge.include?("approved_reflection") &&
    !bridge.include?("@store.approve")
)
record(
  results,
  failures,
  "reflection imports declare stable provenance",
  bridge.include?("reflection_import_key") && bridge.include?("Digest::SHA256")
)

snapshot = File.read(File.join(ROOT, "lib/soul_core/conversation_memory_snapshot.rb"), encoding: "UTF-8")
record(
  results,
  failures,
  "snapshot verification replays events",
  snapshot.include?("replay_matches_records") && snapshot.include?("Digest::SHA256")
)
record(
  results,
  failures,
  "physical purge remains unavailable",
  snapshot.include?('"physical_purge_supported" => false')
)

later_phase_complete = roadmap.match?(
  /### Phase 10: Identity, interests, and variation.*?Status:\s*```text\s*complete\s*```/m
)
skip_nested_regressions = SKIP_NESTED_REGRESSIONS || later_phase_complete

unless skip_nested_regressions
  optional_regressions = {
    "Phase 9 reviewed memory controls regression" => "scripts/verify-phase9-reviewed-memory-controls.rb",
    "Phase 9 layered memory foundation regression" => "scripts/verify-phase9-layered-memory-foundation.rb",
    "Phase 8 capability boundaries regression" => "scripts/verify-phase8-declared-capability-boundaries.rb",
    "Phase 7 follow-up router regression" => "scripts/verify-phase7-evidence-followup-router.rb",
    "Phase 6 routing repair regression" => "scripts/verify-phase6-host-routing-repair.rb",
    "Phase 6 bounded host regression" => "scripts/verify-bounded-host-system-status-phase6.rb",
    "Phase 5 grounding regression" => "scripts/verify-grounded-evidence-lifecycle-phase5.rb",
    "Phase 4 orchestration regression" => "scripts/verify-conversational-orchestrator-phase4.rb"
  }

  optional_regressions.each do |label, relative_path|
    path = File.join(ROOT, relative_path)
    next unless File.exist?(path)

    stdout, stderr, status = capture_regression(relative_path)
    record(results, failures, label, status.success?, [stdout, stderr].join.strip)
  end
end

puts "Conversational Soul Phase 9 memory reflection and export closeout verification:"
results.each do |label, ok, detail, failure_kind|
  puts "- #{label}: #{ok ? 'ok' : failure_kind}"
  next if ok || detail.to_s.empty?

  puts
  puts detail
  puts
end

if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 9 is complete."
  exit 0
end

puts "Verification failed:"
failures.each { |failure| puts "- #{failure}" }
exit 1
