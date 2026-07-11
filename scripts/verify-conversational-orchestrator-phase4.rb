#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 4 verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/conversation_tool_catalog.rb
  lib/soul_core/conversation_orchestration_contract.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/conversation_state_store.rb
  lib/soul_core/conversational_orchestrator_assessor.rb
  docs/CONVERSATIONAL_ORCHESTRATOR.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE4.md
  docs/MILESTONES.md
  CHANGELOG.md
  scripts/verify-conversational-orchestrator-phase4.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversational-orchestrator",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "conversational_orchestrator" &&
  json["milestone"] == "conversational_soul" &&
  json["phase"] == 4 &&
  json["ok"] == true &&
  json.dig("verification", "single_skill_synthesis_works") == true &&
  json.dig("verification", "unrelated_skill_avoidance_works") == true &&
  json.dig("verification", "approval_controls_remain_deterministic") == true &&
  json.dig("verification", "bounded_skill_chain_works") == true &&
  json.dig("verification", "memory_and_artifact_flags_work") == true &&
  json.dig("verification", "skill_result_survives_provider_failure") == true &&
  json.dig("verification", "orchestration_state_is_recorded") == true &&
  json.dig("verification", "max_tool_steps_is_two") == true &&
  json.dig("verification", "no_external_provider_required") == true

check("conversational orchestrator assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversational-orchestrator"
)

text_ok =
  status.success? &&
  stdout.include?("Soul Conversational Orchestrator Assessment") &&
  stdout.include?("Phase: 4") &&
  stdout.include?("Status: ready")

check("conversational orchestrator text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

orchestrator = File.read("lib/soul_core/conversation_orchestrator.rb")
runtime = File.read("lib/soul_core/conversation_runtime.rb")
documentation = File.read("docs/CONVERSATIONAL_ORCHESTRATOR.md")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
milestones = File.read("docs/MILESTONES.md")
changelog = File.read("CHANGELOG.md")

check("orchestrator hard-limits tool steps", orchestrator.include?("MAX_TOOL_STEPS = 2"), errors)
check("runtime synthesizes deterministic results", runtime.include?("Deterministic skill results are provided below"), errors)
check("runtime preserves deterministic result on synthesis failure", runtime.include?("conversational synthesis is unavailable"), errors)
check("documentation defers durable memory", documentation.include?("Phase 5: layered memory"), errors)
check("roadmap marks Phase 3 complete", roadmap.include?("### Phase 3: Multi-turn conversation runtime") && roadmap.include?("complete"), errors)
check("roadmap marks Phase 4 in progress", roadmap.include?("### Phase 4: Conversational orchestrator") && roadmap.include?("in progress"), errors)
check("milestones select Phase 4", milestones.include?("Current phase:\n\n```text\nPhase 4"), errors)
check("changelog records Phase 4", changelog.include?("Phase 4 conversational orchestrator"), errors)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-conversational-orchestrator-phase4.rb"]
untracked =
  if curation && curation["untracked_review_candidates"].is_a?(Array)
    curation["untracked_review_candidates"]
  else
    []
  end

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  (untracked - allowed).empty?

check("repo curation", curation_ok, errors)

unless curation_ok
  warn stderr
  warn stdout
end

if errors.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 4 is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
