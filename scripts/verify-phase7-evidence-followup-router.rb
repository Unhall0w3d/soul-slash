#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require_relative "../lib/soul_core/phase7_evidence_followup_router_assessor"

ROOT = File.expand_path("..", __dir__)

checks = {}
required_files = [
  "lib/soul_core/conversation_evidence_followup_router.rb",
  "lib/soul_core/phase7_evidence_followup_router_assessor.rb",
  "lib/soul_core/conversation_orchestrator.rb",
  "lib/soul_core/conversation_runtime.rb",
  "lib/soul_core/app.rb",
  "docs/EVIDENCE_FOLLOWUP_ROUTING.md",
  "docs/maintenance/CONVERSATIONAL_SOUL_PHASE7.md",
  "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
  "CHANGELOG.md",
  "scripts/verify-phase7-evidence-followup-router.rb"
]

required_files.each do |relative_path|
  checks[relative_path] = File.exist?(File.join(ROOT, relative_path))
end

ruby_files = required_files.select { |path| path.end_with?(".rb") }
ruby_files.each do |relative_path|
  _stdout, _stderr, status = Open3.capture3(
    "ruby",
    "-c",
    File.join(ROOT, relative_path)
  )
  checks["syntax: #{relative_path}"] = status.success?
end

assessor = SoulCore::Phase7EvidenceFollowupRouterAssessor.new(root: ROOT)
report = assessor.assess
checks["Phase 7 evidence follow-up router assessment"] = report["ok"] == true
checks["Phase 7 evidence follow-up router text rendering"] = assessor.render(report).include?("Status: ready")

roadmap = File.read(File.join(ROOT, "docs/CONVERSATIONAL_SOUL_ROADMAP.md"), encoding: "UTF-8")
checks["roadmap declares Phase 7"] = roadmap.include?("Phase 7 — Generic Evidence Follow-up Router")

changelog = File.read(File.join(ROOT, "CHANGELOG.md"), encoding: "UTF-8")
checks["changelog records Phase 7 router"] = changelog.include?("generic deterministic evidence follow-up router")

optional_regressions = {
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

puts "Conversational Soul Phase 7 evidence follow-up router verification:"
checks.each do |name, passed|
  puts "- #{name}: #{passed ? 'ok' : 'missing'}"
end

failures = checks.reject { |_name, passed| passed }
if failures.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 7 is ready."
  exit 0
end

puts "Verification failed:"
failures.each_key { |name| puts "- #{name}" }
puts JSON.pretty_generate(report) unless report["ok"]
exit 1
