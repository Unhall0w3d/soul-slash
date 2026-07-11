#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require_relative "../lib/soul_core/phase9_reviewed_memory_controls_assessor"

ROOT = File.expand_path("..", __dir__)

checks = {}
required_files = [
  "lib/soul_core/conversation_memory_store.rb",
  "lib/soul_core/conversation_memory_controls.rb",
  "lib/soul_core/chat_responder.rb",
  "lib/soul_core/conversation_orchestrator.rb",
  "lib/soul_core/conversation_runtime.rb",
  "lib/soul_core/phase9_reviewed_memory_controls_assessor.rb",
  "lib/soul_core/app.rb",
  "docs/LAYERED_CONVERSATION_MEMORY.md",
  "docs/REVIEWED_CONVERSATION_MEMORY_CONTROLS.md",
  "docs/maintenance/CONVERSATIONAL_SOUL_PHASE9_REVIEWED_MEMORY_CONTROLS.md",
  "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
  "CHANGELOG.md",
  "scripts/verify-phase9-reviewed-memory-controls.rb"
]

required_files.each do |relative_path|
  checks[relative_path] = File.exist?(File.join(ROOT, relative_path))
end

required_files.select { |path| path.end_with?(".rb") }.each do |relative_path|
  _stdout, _stderr, status = Open3.capture3("ruby", "-c", File.join(ROOT, relative_path))
  checks["syntax: #{relative_path}"] = status.success?
end

assessor = SoulCore::Phase9ReviewedMemoryControlsAssessor.new(root: ROOT)
report = assessor.assess
checks["Phase 9 reviewed memory controls assessment"] = report["ok"] == true
checks["Phase 9 reviewed memory controls text rendering"] = assessor.render(report).include?("Status: ready")

roadmap = File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"), encoding: "UTF-8")
checks["roadmap keeps Phase 9 in progress"] =
  roadmap.match?(/## Phase 9 — Layered Memory Foundation.*?Status:\s*in progress/m)
checks["roadmap records reviewed memory controls"] =
  roadmap.include?("reviewed conversational proposal, inspection, approval, supersession, and forgetting controls")
checks["roadmap keeps identity after memory"] =
  roadmap.include?("### Phase 10: Identity, interests, and variation")

changelog = File.read(File.join(ROOT, "CHANGELOG.md"), encoding: "UTF-8")
checks["changelog records reviewed memory controls"] =
  changelog.include?("reviewed deterministic conversation memory controls")

controls = File.read(File.join(ROOT, "lib/soul_core/conversation_memory_controls.rb"), encoding: "UTF-8")
checks["candidate approval boundary is explicit"] =
  controls.include?("Approved context: no") &&
  controls.include?("approve memory latest")
checks["destructive-looking controls require confirmation"] =
  controls.include?("Memory deletion requires confirmation") &&
  controls.include?("Memory supersession requires confirmation")
checks["physical purge remains unavailable"] = controls.include?("Physical purge: not performed")

optional_regressions = {
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

  _stdout, _stderr, status = Open3.capture3("ruby", path)
  checks[label] = status.success?
end

puts "Conversational Soul Phase 9 reviewed memory controls verification:"
checks.each do |name, passed|
  puts "- #{name}: #{passed ? 'ok' : 'missing'}"
end

failures = checks.reject { |_name, passed| passed }
if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 9 reviewed memory controls are ready."
  exit 0
end

puts "Verification failed:"
failures.each_key { |name| puts "- #{name}" }
puts JSON.pretty_generate(report) unless report["ok"]
exit 1
