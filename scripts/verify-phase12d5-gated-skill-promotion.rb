#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/skill_studio_service"

failures = []
class FailingRegistrySkillStudioService < SoulCore::SkillStudioService
  private

  def write_registry_with_new_skill(*)
    raise Errno::EACCES, "fixture registry failure"
  end
end

check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless condition
end

def write_proposal(root, proposal_id)
  directory = File.join(root, "Soul/proposals/skills", proposal_id)
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "metadata.json"), JSON.generate({ "title" => "Fixture skill", "created_at" => "2026-07-15T12:00:00Z" }))
  File.write(File.join(directory, "proposal.md"), "# Skill Proposal: Fixture skill\n\n## Purpose\nReturn a bounded fixture response.\n")
  File.write(File.join(directory, "review_checklist.md"), "- [x] Scope reviewed\n")
  directory
end

def approve_proposal(service, proposal_id)
  preview = service.proposal_approval_preview(proposal_id: proposal_id)
  service.approve_proposal(proposal_id: proposal_id, expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROPOSAL_CONFIRMATION)
end

def implement_beta(service, proposal_directory, skill_id)
  beta = File.join(proposal_directory, "beta")
  manifest_path = File.join(beta, "beta_manifest.json")
  manifest = JSON.parse(File.read(manifest_path))
  manifest.merge!(
    "description" => "A reviewed deterministic fixture skill.",
    "risk" => "read_only",
    "implementation_complete" => true,
    "requires_approval" => false,
    "confirmation_phrase" => "",
    "writes_files" => false,
    "required_tests" => [{ "id" => "fixture-output", "description" => "Returns fixture output", "kind" => "deterministic" }],
    "known_weaknesses" => ["Fixture only"],
    "failure_behavior" => ["Returns failed JSON"]
  )
  File.write(manifest_path, JSON.pretty_generate(manifest))
  source = "# frozen_string_literal: true\nrequire \"json\"\nputs JSON.generate({\"ok\" => true, \"lifecycle_state\" => \"complete\", \"skill\" => #{skill_id.inspect}})\n"
  File.write(File.join(beta, "skill.rb"), source)
  digest = service.send(:beta_digest, beta, manifest)
  File.write(File.join(beta, "test_results.json"), JSON.pretty_generate({ "passed" => true, "tested_at" => "2026-07-15T12:00:00Z", "beta_digest" => digest, "results" => [{ "id" => "fixture-output", "passed" => true }] }))
  [source, digest]
end

puts "Phase 12D.5 gated Beta build and production promotion verification:"

Dir.mktmpdir("soul-phase12d5-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), YAML.dump({ "skills" => { "existing.skill" => { "path" => "Soul/skills/existing.rb", "risk" => "read_only" } } }))
  unrelated = File.join(root, "unrelated.txt")
  File.write(unrelated, "preserve exactly\n")
  proposal_id = "fixture-proposal"
  skill_id = "fixture.generated_skill"
  proposal = write_proposal(root, proposal_id)
  service = SoulCore::SkillStudioService.new(root: root, clock: -> { Time.utc(2026, 7, 15, 12, 0, 0) })

  unapproved = service.beta_build_preview(proposal_id: proposal_id, skill_id: skill_id)
  malformed = service.beta_build_preview(proposal_id: proposal_id, skill_id: "Bad Skill")
  check.call("Beta preparation requires Gate 1 and a canonical skill ID", unapproved["lifecycle_state"] == "blocked_for_human_review" && malformed["lifecycle_state"] == "awaiting_input")

  approve_proposal(service, proposal_id)
  preview = service.beta_build_preview(proposal_id: proposal_id, skill_id: skill_id)
  wrong = service.prepare_beta_build(proposal_id: proposal_id, skill_id: skill_id, expected_digest: preview.dig("data", "expected_digest"), confirmation: "PREPARE")
  check.call("Beta preparation requires exact preview confirmation", wrong["lifecycle_state"] == "awaiting_input" && !File.exist?(File.join(proposal, "beta")))

  proposal_markdown = File.read(File.join(proposal, "proposal.md"))
  File.write(File.join(proposal, "proposal.md"), "#{proposal_markdown}\nChanged after preview.\n")
  stale_build = service.prepare_beta_build(proposal_id: proposal_id, skill_id: skill_id, expected_digest: preview.dig("data", "expected_digest"), confirmation: "PREPARE_BETA_BUILD #{skill_id}")
  File.write(File.join(proposal, "proposal.md"), proposal_markdown)
  preview = service.beta_build_preview(proposal_id: proposal_id, skill_id: skill_id)
  check.call("stale proposal revision blocks before Beta workspace creation", stale_build["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(File.join(proposal, "beta")))

  prepared = service.prepare_beta_build(proposal_id: proposal_id, skill_id: skill_id, expected_digest: preview.dig("data", "expected_digest"), confirmation: "PREPARE_BETA_BUILD #{skill_id}")
  beta_manifest = JSON.parse(File.read(File.join(proposal, "beta/beta_manifest.json")))
  check.call("Gate 1 prepares only an honest proposal-local Beta workspace",
    prepared["lifecycle_state"] == "complete" && beta_manifest["implementation_complete"] == false &&
    prepared.dig("data", "codex_invoked") == false && prepared.dig("data", "production_modified") == false &&
    !File.exist?(File.join(root, "Soul/skills/generated")))

  repeated = service.beta_build_preview(proposal_id: proposal_id, skill_id: skill_id)
  check.call("existing Beta workspace is never replaced", repeated["lifecycle_state"] == "blocked_for_human_review")

  source, beta_digest = implement_beta(service, proposal, skill_id)
  before_gate2 = service.production_promotion_preview(beta_id: skill_id)
  check.call("production promotion requires Gate 2 for the exact Beta digest", before_gate2["lifecycle_state"] == "blocked_for_human_review" && before_gate2.dig("data", "reason").include?("Gate 2"))

  gate2_preview = service.promotion_preview(beta_id: skill_id)
  gate2 = service.approve_beta_for_promotion(beta_id: skill_id, expected_digest: gate2_preview.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROMOTION_CONFIRMATION)
  production_preview = service.production_promotion_preview(beta_id: skill_id)
  check.call("production preview discloses exact source target registry and rollback", gate2["lifecycle_state"] == "complete" && production_preview["lifecycle_state"] == "blocked_for_human_review" && production_preview.dig("data", "source_sha256") == Digest::SHA256.hexdigest(source) && production_preview.dig("data", "rollback").length == 2)

  wrong_promotion = service.promote_beta_to_production(beta_id: skill_id, expected_digest: production_preview.dig("data", "expected_digest"), confirmation: "PROMOTE")
  target = File.join(root, "Soul/skills/generated", skill_id)
  check.call("wrong production confirmation performs no mutation", wrong_promotion["lifecycle_state"] == "awaiting_input" && !File.exist?(target))

  registry_path = File.join(root, "Soul/skills/registry.yaml")
  registry_before_stale = File.read(registry_path)
  File.write(registry_path, "#{registry_before_stale}\n")
  stale_promotion = service.promote_beta_to_production(beta_id: skill_id, expected_digest: production_preview.dig("data", "expected_digest"), confirmation: "PROMOTE_BETA_SKILL #{skill_id}")
  production_preview = service.production_promotion_preview(beta_id: skill_id)
  check.call("stale registry revision blocks before production mutation", stale_promotion["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(target))

  promoted = service.promote_beta_to_production(beta_id: skill_id, expected_digest: production_preview.dig("data", "expected_digest"), confirmation: "PROMOTE_BETA_SKILL #{skill_id}")
  registry = YAML.safe_load(File.read(registry_path))
  production_source = File.binread(File.join(target, "skill.rb"))
  receipt = JSON.parse(File.read(File.join(target, "PROMOTION.json")))
  check.call("verified promotion copies exact bytes and atomically registers one skill",
    promoted["lifecycle_state"] == "complete" && production_source == source &&
    registry.dig("skills", skill_id, "path") == "Soul/skills/generated/#{skill_id}/skill.rb" &&
    receipt["source_sha256"] == receipt["target_sha256"] && File.read(unrelated) == "preserve exactly\n")
  check.call("existing production and repeated promotion remain protected", registry.dig("skills", "existing.skill", "path") == "Soul/skills/existing.rb" && service.production_promotion_preview(beta_id: skill_id)["lifecycle_state"] == "blocked_for_human_review")

  failure_proposal_id = "registry-failure-proposal"
  failure_skill_id = "fixture.registry_failure"
  failure_proposal = write_proposal(root, failure_proposal_id)
  approve_proposal(service, failure_proposal_id)
  failure_build_preview = service.beta_build_preview(proposal_id: failure_proposal_id, skill_id: failure_skill_id)
  service.prepare_beta_build(proposal_id: failure_proposal_id, skill_id: failure_skill_id, expected_digest: failure_build_preview.dig("data", "expected_digest"), confirmation: "PREPARE_BETA_BUILD #{failure_skill_id}")
  implement_beta(service, failure_proposal, failure_skill_id)
  failure_gate2_preview = service.promotion_preview(beta_id: failure_skill_id)
  service.approve_beta_for_promotion(beta_id: failure_skill_id, expected_digest: failure_gate2_preview.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROMOTION_CONFIRMATION)
  failing_service = FailingRegistrySkillStudioService.new(root: root, clock: -> { Time.utc(2026, 7, 15, 12, 0, 0) })
  failure_preview = failing_service.production_promotion_preview(beta_id: failure_skill_id)
  registry_before_failure = File.binread(registry_path)
  failed_promotion = failing_service.promote_beta_to_production(beta_id: failure_skill_id, expected_digest: failure_preview.dig("data", "expected_digest"), confirmation: "PROMOTE_BETA_SKILL #{failure_skill_id}")
  failure_target = File.join(root, "Soul/skills/generated", failure_skill_id)
  check.call("registry publication failure removes only the unpublished target", failed_promotion["lifecycle_state"] == "failed" && !File.exist?(failure_target) && File.binread(registry_path) == registry_before_failure && File.file?(File.join(target, "skill.rb")))

  operations = SoulCore::ApplicationContract::OPERATIONS.keys rescue []
  check.call("application contract exposes separate preview and execute operations", %w[skill_studio.proposals.beta_build.preview skill_studio.proposals.beta_build.execute skill_studio.betas.production.preview skill_studio.betas.production.execute].all? { |operation| operations.include?(operation) })
end

source = File.read(File.expand_path("../lib/soul_core/skill_studio_service.rb", __dir__))
check.call("runtime adds no model invocation or background continuation", %w[CloudLlmClient CodexClient setInterval setTimeout daemon(].none? { |needle| source.include?(needle) })
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes separate Beta preparation and production promotion previews", %w[beta-build-card preview-beta-build execute-beta-build production-promotion-card preview-production-promotion execute-production-promotion].all? { |id| html.include?("id=\"#{id}\"") } && javascript.include?('skill_studio.proposals.beta_build.preview') && javascript.include?('skill_studio.betas.production.preview') && javascript.index('skill_studio.betas.production.preview') < javascript.index('skill_studio.betas.production.execute'))
check.call("dashboard remains timer-free and uses safe DOM rendering", %w[setInterval setTimeout WebSocket EventSource innerHTML].none? { |needle| javascript.include?(needle) })

if failures.empty?
  puts "Phase 12D.5 verification complete."
  exit 0
end

warn "Phase 12D.5 verification failed: #{failures.join('; ')}"
exit 1
