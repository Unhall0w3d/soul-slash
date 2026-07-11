#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 5 verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/conversation_evidence_contract.rb
  lib/soul_core/conversation_evidence_store.rb
  lib/soul_core/conversation_grounding_policy.rb
  lib/soul_core/conversation_tool_catalog.rb
  lib/soul_core/conversation_orchestration_contract.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_state_store.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/conversational_orchestrator_assessor.rb
  lib/soul_core/grounded_evidence_lifecycle_assessor.rb
  docs/GROUNDED_TOOL_EVIDENCE.md
  docs/HOST_ENVIRONMENT_CAPABILITY_GAP.md
  docs/CONVERSATIONAL_ORCHESTRATOR.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE5.md
  docs/MILESTONES.md
  CHANGELOG.md
  scripts/verify-grounded-evidence-lifecycle-phase5.rb
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
  "grounded-evidence-lifecycle",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "grounded_evidence_lifecycle" &&
  json["milestone"] == "conversational_soul" &&
  json["phase"] == 5 &&
  json["ok"] == true &&
  json.dig("verification", "runtime_status_is_scoped_and_persisted") == true &&
  json.dig("verification", "followup_uses_persisted_evidence") == true &&
  json.dig("verification", "host_capability_gap_is_explicit") == true &&
  json.dig("verification", "unsupported_environment_claims_are_blocked") == true &&
  json.dig("verification", "evidence_is_available_to_context") == true &&
  json.dig("verification", "grounding_state_is_recorded") == true &&
  json.dig("verification", "evidence_runtime_path_is_gitignored") == true &&
  json.dig("verification", "no_external_provider_required") == true

check("grounded evidence lifecycle assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "grounded-evidence-lifecycle"
)

text_ok =
  status.success? &&
  stdout.include?("Soul Grounded Evidence Lifecycle Assessment") &&
  stdout.include?("Phase: 5") &&
  stdout.include?("Status: ready")

check("grounded evidence text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversational-orchestrator",
  "--json"
)
phase4 = JSON.parse(stdout) rescue nil
phase4_ok =
  status.success? &&
  phase4 &&
  phase4["ok"] == true &&
  phase4.dig("verification", "single_skill_synthesis_works") == true &&
  phase4.dig("verification", "runtime_status_is_scoped_evidence") == true

check("Phase 4 orchestration regression", phase4_ok, errors)

unless phase4_ok
  warn stderr
  warn stdout
end

runtime = File.read("lib/soul_core/conversation_runtime.rb")
catalog = File.read("lib/soul_core/conversation_tool_catalog.rb")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
milestones = File.read("docs/MILESTONES.md")
grounding = File.read("docs/GROUNDED_TOOL_EVIDENCE.md")

check("runtime persists evidence", runtime.include?("@evidence_store.append"), errors)
check("runtime rejects unsupported synthesis", runtime.include?("grounding_fallback"), errors)
check("system status disables synthesis", catalog.include?('id: "system.status"') && catalog.include?("synthesis_allowed: false"), errors)
check("grounding docs distinguish not_collected", grounding.include?("`not_collected` means unknown"), errors)
check("roadmap has eleven phase headings", roadmap.scan(/^### Phase \d+:/).length == 11, errors)
check("roadmap marks Phase 5 in progress", roadmap.include?("### Phase 5: Grounded evidence lifecycle") && roadmap.include?("in progress"), errors)
check("roadmap reserves Phase 6 host assessment", roadmap.include?("### Phase 6: Bounded host environment assessment"), errors)
check("milestones select Phase 5", milestones.include?("Current phase:\n\n```text\nPhase 5"), errors)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-grounded-evidence-lifecycle-phase5.rb"]
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
  puts "Conversational Soul Phase 5 is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
