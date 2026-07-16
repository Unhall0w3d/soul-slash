#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

MILESTONE_VERIFIERS = %w[
  scripts/verify-conversational-architecture-phase1.rb
  scripts/verify-conversation-provider-foundation-phase2.rb
  scripts/verify-multiturn-conversation-runtime-phase3.rb
  scripts/verify-conversational-orchestrator-phase4.rb
  scripts/verify-grounded-evidence-lifecycle-phase5.rb
  scripts/verify-bounded-host-system-status-phase6.rb
  scripts/verify-phase7-evidence-followup-router.rb
  scripts/verify-phase8-declared-capability-boundaries.rb
  scripts/verify-phase9-layered-memory-foundation.rb
  scripts/verify-phase9-reviewed-memory-controls.rb
  scripts/verify-phase9-memory-reflection-and-export-closeout.rb
  scripts/verify-phase10-identity-style-foundation.rb
  scripts/verify-phase10-recent-style-awareness.rb
  scripts/verify-phase10-inspectable-interests-closeout.rb
  scripts/verify-phase11-artifact-metadata-attachment.rb
  scripts/verify-phase11-bounded-artifact-inspection.rb
  scripts/verify-phase11c-bounded-artifact-creation.rb
  scripts/verify-phase11d-shared-workspace-inbox.rb
  scripts/verify-phase12a-portable-typed-configuration.rb
  scripts/verify-phase12b-in-process-application-api.rb
  scripts/verify-phase12c-foreground-dashboard.rb
  scripts/verify-dashboard-authentication-phase12c1.rb
  scripts/verify-phase12d-skill-studio.rb
  scripts/verify-phase12d2-capability-gap-intake.rb
  scripts/verify-phase12d3-self-improvement-dashboard.rb
  scripts/verify-phase12d4-proposal-closeout.rb
  scripts/verify-phase12d5-gated-skill-promotion.rb
  scripts/verify-phase12e-unified-review-center.rb
  scripts/verify-conversation-list-clearing-skill.rb
  scripts/verify-conversation-delete-and-forget-skill.rb
  scripts/verify-protected-lan-systemd-deployment.rb
  scripts/verify-phase13a-integrated-acceptance.rb
  scripts/verify-phase13b-local-model-dashboard-acceptance.rb
].freeze

failures = []
check = lambda do |name, passed|
  puts "#{passed ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless passed
end

puts "Conversational Soul Phase 13C milestone closeout verification:"

MILESTONE_VERIFIERS.each do |script|
  stdout, stderr, status = Open3.capture3("ruby", script)
  name = File.basename(script)
  check.call(name, status.success?)
  next if status.success?

  warn stdout.lines.last(20).join
  warn stderr.lines.last(20).join
end

readme = File.read("README.md")
milestones = File.read("docs/MILESTONES.md")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
current = File.read("docs/CURRENT_STATE.md")
acceptance = File.read("docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md")
changelog = File.read("CHANGELOG.md")
review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE13_CLOSEOUT.md")

check.call("README records owner-approved completion", readme.include?("Phase 13A–C") && readme.include?("owner approved Conversational Soul"))
check.call("milestone records owner-approved completion", milestones.match?(/### Conversational Soul.*?Status:\s*```text\s*complete/m) && milestones.include?("Owner approval recorded"))
check.call("roadmap records the clean stopping point", roadmap.include?("Phase 13 is the clear stopping point") && roadmap.include?("No release or tag"))
check.call("current state records deterministic and local-model evidence", current.include?("all ten deterministic integrated scenarios") && current.include?("20/20 model turns"))
check.call("acceptance records human authority and approval", acceptance.include?("Human review remains the authority") && acceptance.include?("owner approved"))
check.call("changelog records approved Phase 13 closeout", changelog.include?("owner-approved Phase 13 closeout"))
check.call("review artifact contains required sections", %w[
  Implementation Files Commands Deterministic Local Memory Lifecycle Risk Safety Known Human
].all? { |word| review.include?(word) })

curation_stdout, curation_stderr, curation_status = Open3.capture3("ruby", "bin/soul", "assess", "repository-curation", "--json")
curation = JSON.parse(curation_stdout) rescue nil
check.call("repository curation assessment", curation_status.success? && curation && curation["untracked_review_candidates"] == [])
warn curation_stderr unless curation_status.success?

if failures.empty?
  puts "Phase 13C closeout verification complete."
  exit 0
end

warn "Phase 13C verification failed: #{failures.join('; ')}"
exit 1
