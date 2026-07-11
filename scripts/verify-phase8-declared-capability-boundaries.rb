#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require_relative "../lib/soul_core/phase8_declared_capability_boundaries_assessor"

ROOT = File.expand_path("..", __dir__)

checks = {}
required_files = [
  "lib/soul_core/conversation_capability_registry.rb",
  "lib/soul_core/phase8_declared_capability_boundaries_assessor.rb",
  "lib/soul_core/conversation_evidence_followup_router.rb",
  "lib/soul_core/conversation_orchestrator.rb",
  "lib/soul_core/conversation_runtime.rb",
  "lib/soul_core/conversation_tool_catalog.rb",
  "lib/soul_core/app.rb",
  "docs/DECLARED_CONVERSATION_CAPABILITIES.md",
  "docs/maintenance/CONVERSATIONAL_SOUL_PHASE8.md",
  "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
  "CHANGELOG.md",
  "scripts/verify-phase8-declared-capability-boundaries.rb"
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

assessor = SoulCore::Phase8DeclaredCapabilityBoundariesAssessor.new(root: ROOT)
report = assessor.assess
checks["Phase 8 declared capability boundaries assessment"] = report["ok"] == true
checks["Phase 8 declared capability boundaries text rendering"] = assessor.render(report).include?("Status: ready")

roadmap = File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"), encoding: "UTF-8")
checks["roadmap marks generic follow-up routing complete"] =
  roadmap.match?(/## Phase 7 — Generic Evidence Follow-up Router.*?Status:\s*complete/m)
checks["roadmap declares Phase 8 capability boundaries"] =
  roadmap.include?("## Phase 8 — Declared Capability Boundaries")
checks["roadmap has one active Phase 8 implementation slice"] =
  roadmap.scan(/^## Phase 8 — Declared Capability Boundaries$/).length == 1
checks["roadmap shifts layered memory after capability boundaries"] =
  roadmap.include?("### Phase 9: Layered memory")

changelog = File.read(File.join(ROOT, "CHANGELOG.md"), encoding: "UTF-8")
checks["changelog records declared capability registry"] =
  changelog.include?("declared conversation capability registry")

optional_regressions = {
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

puts "Conversational Soul Phase 8 declared capability boundaries verification:"
checks.each do |name, passed|
  puts "- #{name}: #{passed ? 'ok' : 'missing'}"
end

failures = checks.reject { |_name, passed| passed }
if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 8 is ready."
  exit 0
end

puts "Verification failed:"
failures.each_key { |name| puts "- #{name}" }
puts JSON.pretty_generate(report) unless report["ok"]
exit 1
