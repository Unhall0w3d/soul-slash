#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require_relative "../lib/soul_core/phase9_layered_memory_foundation_assessor"

ROOT = File.expand_path("..", __dir__)

checks = {}
required_files = [
  "lib/soul_core/conversation_memory_store.rb",
  "lib/soul_core/chat_store.rb",
  "lib/soul_core/conversation_context_builder.rb",
  "lib/soul_core/phase9_layered_memory_foundation_assessor.rb",
  "lib/soul_core/app.rb",
  "docs/LAYERED_CONVERSATION_MEMORY.md",
  "docs/maintenance/CONVERSATIONAL_SOUL_PHASE9.md",
  "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
  "CHANGELOG.md",
  ".gitignore",
  "scripts/verify-phase9-layered-memory-foundation.rb"
]

required_files.each do |relative_path|
  checks[relative_path] = File.exist?(File.join(ROOT, relative_path))
end

required_files.select { |path| path.end_with?(".rb") }.each do |relative_path|
  _stdout, _stderr, status = Open3.capture3(
    "ruby",
    "-c",
    File.join(ROOT, relative_path)
  )
  checks["syntax: #{relative_path}"] = status.success?
end

assessor = SoulCore::Phase9LayeredMemoryFoundationAssessor.new(root: ROOT)
report = assessor.assess
checks["Phase 9 layered memory foundation assessment"] = report["ok"] == true
checks["Phase 9 layered memory foundation text rendering"] =
  assessor.render(report).include?("Status: ready")

roadmap = File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"), encoding: "UTF-8")
checks["roadmap marks Phase 8 complete"] =
  roadmap.match?(/## Phase 8 — Declared Capability Boundaries.*?Status:\s*complete/m)
checks["roadmap declares Phase 9 layered memory foundation"] =
  roadmap.include?("## Phase 9 — Layered Memory Foundation")
checks["roadmap has one Phase 9 implementation slice"] =
  roadmap.scan(/^## Phase 9 — Layered Memory Foundation$/).length == 1
checks["roadmap keeps identity after memory"] =
  roadmap.include?("### Phase 10: Identity, interests, and variation")

changelog = File.read(File.join(ROOT, "CHANGELOG.md"), encoding: "UTF-8")
checks["changelog records layered memory foundation"] =
  changelog.include?("append-only layered conversation memory foundation")

gitignore = File.read(File.join(ROOT, ".gitignore"), encoding: "UTF-8")
checks["local memory ledger is ignored"] =
  gitignore.lines.map(&:chomp).include?("Soul/memory/conversation_memory.jsonl")

context_builder = File.read(
  File.join(ROOT, "lib/soul_core/conversation_context_builder.rb"),
  encoding: "UTF-8"
)
checks["context builder injects only approved memory section"] =
  context_builder.include?("Approved memory context") &&
  context_builder.include?("Candidate, superseded, and deleted")

optional_regressions = {
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

  _stdout, _stderr, status = Open3.capture3("ruby", path)
  checks[label] = status.success?
end

puts "Conversational Soul Phase 9 layered memory foundation verification:"
checks.each do |name, passed|
  puts "- #{name}: #{passed ? 'ok' : 'missing'}"
end

failures = checks.reject { |_name, passed| passed }
if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 9 layered memory foundation is ready."
  exit 0
end

puts "Verification failed:"
failures.each_key { |name| puts "- #{name}" }
puts JSON.pretty_generate(report) unless report["ok"]
exit 1
