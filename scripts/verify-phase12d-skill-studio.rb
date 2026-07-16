#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/skill_studio_service"

failures = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless condition
end

Dir.mktmpdir("soul-phase12d-") do |root|
  proposal_id = "20260715T120000Z-example-beta"
  proposal = File.join(root, "Soul/proposals/skills", proposal_id)
  beta = File.join(proposal, "beta")
  FileUtils.mkdir_p(beta)
  File.write(File.join(proposal, "metadata.json"), JSON.pretty_generate({ "artifact_type" => "skill_proposal", "created_at" => "2026-07-15T12:00:00Z", "provider" => "mistral", "model" => "test-model" }))
  File.write(File.join(proposal, "proposal.md"), "# Skill Proposal: Example Beta\n\n## Purpose\nExercise the bounded Beta lifecycle.\n")
  File.write(File.join(proposal, "review_checklist.md"), "- [ ] Human scope review\n")
  manifest = {
    "schema_version" => "soul.beta.v1",
    "skill_id" => "example.beta",
    "description" => "A deterministic test Beta.",
    "risk" => "read_only",
    "entrypoint" => "skill.rb",
    "implementation_complete" => true,
    "timeout_seconds" => 5,
    "lifecycle_states" => %w[complete failed canceled blocked_for_human_review],
    "required_tests" => [{ "id" => "echo", "description" => "Returns structured output", "kind" => "deterministic" }],
    "known_weaknesses" => ["Fixture only"]
  }
  File.write(File.join(beta, "beta_manifest.json"), JSON.pretty_generate(manifest))
  File.write(File.join(beta, "skill.rb"), "# frozen_string_literal: true\nrequire 'json'\nputs JSON.generate({ok: true, args: ARGV})\n")

  service = SoulCore::SkillStudioService.new(root: root, clock: -> { Time.utc(2026, 7, 15, 12, 0, 0) })
  list = service.proposals
  check.call("proposal folder is projected without rewriting", list.dig("data", "records", 0, "proposal_id") == proposal_id && !File.exist?(File.join(proposal, "studio_state.json")))

  preview = service.proposal_approval_preview(proposal_id: proposal_id)
  check.call("Gate 1 preview blocks for human review", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "confirmation_phrase") == SoulCore::SkillStudioService::PROPOSAL_CONFIRMATION)
  rejected = service.approve_proposal(proposal_id: proposal_id, expected_digest: preview.dig("data", "expected_digest"), confirmation: "yes")
  check.call("Gate 1 rejects non-exact confirmation", rejected["lifecycle_state"] == "awaiting_input")
  approved = service.approve_proposal(proposal_id: proposal_id, expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROPOSAL_CONFIRMATION)
  check.call("Gate 1 records exact proposal revision", approved["lifecycle_state"] == "complete" && approved.dig("data", "proposal_gate") == "approved")

  digest = service.send(:beta_digest, beta, manifest)
  File.write(File.join(beta, "test_results.json"), JSON.pretty_generate({ "passed" => true, "tested_at" => "2026-07-15T12:00:00Z", "beta_digest" => digest, "results" => [{ "id" => "echo", "passed" => true }] }))
  beta_list = service.betas
  check.call("Beta inventory is separate and runnable only when implemented", beta_list.dig("data", "records", 0, "beta_id") == "example.beta" && beta_list.dig("data", "records", 0, "runnable") == true && beta_list.dig("data", "production_registry_separate") == true)

  run_preview = service.beta_run_preview(beta_id: "example.beta", args: ["hello"])
  wrong_run = service.run_beta(beta_id: "example.beta", args: ["hello"], expected_digest: run_preview.dig("data", "expected_digest"), confirmation: "RUN")
  check.call("Beta run requires exact human confirmation", wrong_run["lifecycle_state"] == "awaiting_input")
  run = service.run_beta(beta_id: "example.beta", args: ["hello"], expected_digest: run_preview.dig("data", "expected_digest"), confirmation: "RUN_BETA_SKILL example.beta")
  check.call("Beta run terminates and writes bounded diagnostics", run["lifecycle_state"] == "complete" && run.dig("data", "stdout").include?("hello") && File.file?(File.join(root, run.dig("data", "diagnostic_log"))))

  promotion = service.promotion_preview(beta_id: "example.beta")
  check.call("Gate 2 requires current passing evidence", promotion.dig("data", "ready") == true && promotion.dig("data", "blockers") == [])
  promoted = service.approve_beta_for_promotion(beta_id: "example.beta", expected_digest: promotion.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROMOTION_CONFIRMATION)
  check.call("Gate 2 records approval without promotion", promoted["lifecycle_state"] == "complete" && promoted.dig("data", "promotion_performed") == false)

  File.write(File.join(beta, "skill.rb"), "puts 'changed'\n")
  stale = service.approve_beta_for_promotion(beta_id: "example.beta", expected_digest: promotion.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROMOTION_CONFIRMATION)
  check.call("changed Beta invalidates test and approval evidence", stale["lifecycle_state"] == "blocked_for_human_review")
end

operations = SoulCore::ApplicationContract::OPERATIONS.keys
check.call("application contract exposes bounded Studio operations", %w[skill_studio.proposals.list skill_studio.proposals.approval.execute skill_studio.betas.list skill_studio.betas.run.execute skill_studio.betas.promotion.approve].all? { |operation| operations.include?(operation) })

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
stylesheet = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
check.call("dashboard exposes proposals, Beta, production, and two gates", %w[proposal-list beta-list production-skill-list proposal-approval beta-promotion-card].all? { |id| html.include?("id=\"#{id}\"") })
check.call("Skill Studio uses the scalable Soul core and responsive foundry field", html.include?('id="studio-empty" class="studio-empty"><img src="/brand/micro-mark.svg"') && html.include?('id="studio-detail-pane" class="studio-detail is-empty"') && stylesheet.include?(".studio-detail.is-empty { padding:0") && stylesheet.include?("Capability Foundry") && javascript.include?('classList.toggle("is-empty", kind === "empty")'))
check.call("dashboard renders domain content without innerHTML", !javascript.include?("innerHTML"))
check.call("Skill Studio adds no polling or background continuation", !javascript.match?(/setInterval|setTimeout|WebSocket|EventSource/))

if failures.empty?
  puts "Phase 12D Skill Studio verification complete."
  exit 0
end

warn "Phase 12D verification failed: #{failures.join('; ')}"
exit 1
