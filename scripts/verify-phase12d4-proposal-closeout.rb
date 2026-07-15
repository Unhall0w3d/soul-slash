#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/skill_studio_service"

failures = []
check = lambda do |description, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{description}"
  failures << description unless condition
end

class Phase12d4Registry
  attr_reader :skills

  def initialize(skills)
    @skills = skills
  end

  def list
    @skills
  end
end

def write_proposal(root, id, skill_id: nil, implementation_complete: false, proposal_gate: nil, beta_gate: nil)
  directory = File.join(root, "Soul/proposals/skills", id)
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "metadata.json"), JSON.generate({ "created_at" => "2026-07-15T12:00:00Z", "provider" => "fixture" }))
  File.write(File.join(directory, "proposal.md"), "# Skill Proposal: #{id}\n\n## Purpose\nFixture stage coverage.\n")
  state = {}
  state["proposal_gate"] = { "status" => proposal_gate } if proposal_gate
  state["beta_gate"] = { "status" => beta_gate } if beta_gate
  File.write(File.join(directory, "studio_state.json"), JSON.generate(state)) unless state.empty?
  return directory unless skill_id

  beta = File.join(directory, "beta")
  FileUtils.mkdir_p(beta)
  manifest = {
    "skill_id" => skill_id,
    "description" => "Fixture Beta",
    "risk" => "read_only",
    "entrypoint" => "skill.rb",
    "implementation_complete" => implementation_complete,
    "required_tests" => [{ "id" => "fixture", "description" => "Fixture test" }]
  }
  File.write(File.join(beta, "beta_manifest.json"), JSON.generate(manifest))
  File.write(File.join(beta, "skill.rb"), "puts 'fixture'\n") if implementation_complete
  directory
end

puts "Phase 12D.4 proposal lifecycle and production closeout verification:"
Dir.mktmpdir("soul-phase12d4-") do |root|
  production_path = File.join(root, "Soul/skills/production.skill.rb")
  FileUtils.mkdir_p(File.dirname(production_path))
  File.write(production_path, "puts 'production'\n")
  diagnostic_path = File.join(root, "Soul/logs/beta_skills/production.skill.jsonl")
  FileUtils.mkdir_p(File.dirname(diagnostic_path))
  File.write(diagnostic_path, "{\"ok\":true}\n")
  registry = Phase12d4Registry.new("production.skill" => { "path" => "Soul/skills/production.skill.rb", "risk" => "read_only" })

  write_proposal(root, "stage-awaiting")
  write_proposal(root, "stage-approved", proposal_gate: "approved")
  write_proposal(root, "stage-build", skill_id: "build.skill", implementation_complete: false, proposal_gate: "approved")
  write_proposal(root, "stage-testing", skill_id: "testing.skill", implementation_complete: true, proposal_gate: "approved")
  ready_directory = write_proposal(root, "stage-ready", skill_id: "ready.skill", implementation_complete: true, proposal_gate: "approved")
  write_proposal(root, "stage-promoted", skill_id: "promoted.skill", implementation_complete: true, proposal_gate: "approved", beta_gate: "approved_for_promotion")
  production_directory = write_proposal(root, "stage-production", skill_id: "production.skill", implementation_complete: true, proposal_gate: "approved", beta_gate: "approved_for_promotion")

  service = SoulCore::SkillStudioService.new(root: root, production_registry: registry, clock: -> { Time.utc(2026, 7, 15, 12, 0, 0) })
  ready_beta = File.join(ready_directory, "beta")
  ready_manifest = JSON.parse(File.read(File.join(ready_beta, "beta_manifest.json")))
  ready_digest = service.send(:beta_digest, ready_beta, ready_manifest)
  File.write(File.join(ready_beta, "test_results.json"), JSON.generate({ "passed" => true, "beta_digest" => ready_digest, "results" => [{ "id" => "fixture", "passed" => true }] }))

  stages = service.proposals.dig("data", "records").to_h { |record| [record["proposal_id"], record] }
  check.call("all canonical proposal stages are derived deterministically",
    stages.dig("stage-awaiting", "stage") == "awaiting_proposal_review" &&
    stages.dig("stage-approved", "stage") == "approved_for_beta_build" &&
    stages.dig("stage-build", "stage") == "beta_build" &&
    stages.dig("stage-testing", "stage") == "beta_testing" &&
    stages.dig("stage-ready", "stage") == "ready_for_promotion_review" &&
    stages.dig("stage-promoted", "stage") == "approved_for_promotion" &&
    stages.dig("stage-production", "stage") == "production")
  check.call("production linkage uses the exact Beta and registry skill ID",
    stages.dig("stage-production", "linked_skill_id") == "production.skill" &&
    stages.dig("stage-production", "linked_skill_maturity") == "production" &&
    stages.dig("stage-production", "closable") == true &&
    stages.dig("stage-testing", "closable") == false)

  beta_close = service.proposal_close_preview(proposal_id: "stage-testing")
  check.call("Beta-only proposal cannot enter closeout", beta_close["lifecycle_state"] == "blocked_for_human_review" && File.directory?(File.join(root, "Soul/proposals/skills/stage-testing")))

  preview = service.proposal_close_preview(proposal_id: "stage-production")
  check.call("production closeout preview binds exact revision", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "confirmation_phrase") == SoulCore::SkillStudioService::CLOSE_CONFIRMATION && preview.dig("data", "expected_digest").to_s.length == 64)
  wrong = service.close_production_proposal(proposal_id: "stage-production", expected_digest: preview.dig("data", "expected_digest"), confirmation: "close")
  check.call("wrong confirmation cannot delete proposal", wrong["lifecycle_state"] == "awaiting_input" && File.directory?(production_directory))

  File.open(File.join(production_directory, "proposal.md"), "a") { |file| file.puts("changed after preview") }
  stale = service.close_production_proposal(proposal_id: "stage-production", expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::CLOSE_CONFIRMATION)
  check.call("stale closeout digest blocks deletion", stale["lifecycle_state"] == "blocked_for_human_review" && File.directory?(production_directory))

  current = service.proposal_close_preview(proposal_id: "stage-production")
  closed = service.close_production_proposal(proposal_id: "stage-production", expected_digest: current.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::CLOSE_CONFIRMATION)
  check.call("confirmed production closeout deletes only proposal packet", closed["lifecycle_state"] == "complete" && closed.dig("data", "proposal_deleted") == true && !File.exist?(production_directory))
  check.call("production skill, registry, and shared diagnostic survive closeout", File.file?(production_path) && registry.list.key?("production.skill") && File.file?(diagnostic_path))
end

operations = SoulCore::ApplicationContract::OPERATIONS
check.call("application contract allowlists preview and execute separately", operations["skill_studio.proposals.close.preview"] == ["proposal_id"] && operations["skill_studio.proposals.close.execute"] == %w[proposal_id confirmation expected_digest])

root = File.expand_path("..", __dir__)
html = File.read(File.join(root, "assets/dashboard/index.html"))
javascript = File.read(File.join(root, "assets/dashboard/dashboard.js"))
check.call("Skill Studio shows stage, link, and production-only closeout controls", %w[view-linked-skill proposal-close-card preview-proposal-close proposal-close-confirmation execute-proposal-close].all? { |id| html.include?("id=\"#{id}\"") } && javascript.include?("record.stage") && javascript.include?("record.linked_skill_id"))
check.call("dashboard closeout preserves preview before execute", javascript.index('callSoul("skill_studio.proposals.close.preview"') < javascript.index('callSoul("skill_studio.proposals.close.execute"') && javascript.include?("CLOSE_PRODUCTION_PROPOSAL"))
check.call("closeout adds no polling or unsafe HTML rendering", !javascript.match?(/setInterval|setTimeout|WebSocket|EventSource|innerHTML/))

abort "Phase 12D.4 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Phase 12D.4 proposal lifecycle and production closeout verification complete."
