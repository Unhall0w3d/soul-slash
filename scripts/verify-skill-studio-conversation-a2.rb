#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/chat_responder"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/skill_studio_chat_controls"

class FakeStudio
  def proposals(limit:)
    raise "unbounded proposal limit" unless limit == SoulCore::SkillStudioChatControls::MAX_RECORDS

    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "mutation" => "none",
      "data" => {
        "records" => [{
          "proposal_id" => "20260801T000000Z-example",
          "title" => "Example Skill",
          "stage" => "awaiting_proposal_review",
          "proposal_gate" => "awaiting_review",
          "beta_gate" => "not_ready",
          "beta_present" => false,
          "linked_skill_id" => nil,
          "production_registered" => false,
          "human_review_required" => true
        }]
      }
    }
  end

  def betas(limit:)
    raise "unbounded Beta limit" unless limit == SoulCore::SkillStudioChatControls::MAX_RECORDS

    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "mutation" => "none",
      "data" => {
        "records" => [{
          "beta_id" => "example.skill",
          "description" => "One bounded example.",
          "maturity" => "beta",
          "runnable" => true,
          "risk" => "read_only",
          "test_status" => "passed",
          "beta_gate" => "awaiting_promotion_review"
        }]
      }
    }
  end
end

class FakeRegistry
  def list
    {
      "example.skill" => {
        "status" => "available",
        "risk" => "read_only"
      }
    }
  end
end

checks = {}
controls = SoulCore::SkillStudioChatControls.new(studio: FakeStudio.new, registry: FakeRegistry.new)
orchestrator = SoulCore::ConversationOrchestrator.new
plan = ->(message) { orchestrator.plan(message: message, provider_available: true) }

checks["explicit_inventory_request_routes_deterministically"] =
  controls.match?("Show the Skill Studio inventory.") &&
  plan.call("Show the Skill Studio inventory.").kind == "deterministic_passthrough" &&
  plan.call("Show the Skill Studio inventory.").flags["skill_studio_control"] == true

checks["ordinary_skill_discussion_remains_conversation"] =
  !controls.match?("I have been thinking about the skills in Skill Studio.") &&
  !controls.match?("Approve the proposal for our next planning meeting.") &&
  plan.call("I have been thinking about the skills in Skill Studio.").kind == "direct_model"

overview = controls.respond("Show the Skill Studio inventory.")
checks["overview_reports_all_three_inventories_without_mutation"] =
  overview.include?("Proposals: 1") &&
  overview.include?("Beta skills: 1") &&
  overview.include?("Production skills: 1") &&
  overview.include?("awaiting_proposal_review=1") &&
  overview.include?("Lifecycle: complete. Mutation: none.")

proposals = controls.respond("List Skill Studio proposals.")
checks["proposal_list_reports_exact_stage_and_id"] =
  proposals.include?("Example Skill") &&
  proposals.include?("20260801T000000Z-example") &&
  proposals.include?("Proposal gate: awaiting_review") &&
  proposals.include?("Beta present: false")

proposal = controls.respond("Inspect Skill Studio proposal Example Skill.")
checks["exact_proposal_title_returns_bounded_detail"] =
  proposal.include?("Title: Example Skill") &&
  proposal.include?("Human review required: true") &&
  !proposal.include?("proposal_digest")

betas = controls.respond("List Skill Studio Beta skills.")
checks["beta_list_reports_test_and_run_state"] =
  betas.include?("example.skill") &&
  betas.include?("Runnable: true") &&
  betas.include?("Test state: passed")

production = controls.respond("List Skill Studio production skills.")
checks["production_list_is_registry_only"] =
  production.include?("example.skill — available; read_only") &&
  production.include?("listing it invokes nothing")

blocked = controls.respond("Promote Beta skill example.skill.")
checks["mutating_request_stops_at_existing_human_gate"] =
  controls.match?("Promote Beta skill example.skill.") &&
  controls.match?("Approve the Skill Studio proposal Example Skill.") &&
  controls.match?("Run Beta skill example.skill.") &&
  plan.call("Approve the Skill Studio proposal Example Skill.").kind == "deterministic_passthrough" &&
  plan.call("Approve the Skill Studio proposal Example Skill.").flags["skill_studio_control"] == true &&
  controls.respond("Run Beta skill example.skill.").include?("Skill Studio action remains protected") &&
  blocked.include?("Skill Studio action remains protected") &&
  blocked.include?("Lifecycle: blocked_for_human_review. Mutation: none.")

missing = controls.respond("Inspect Skill Studio proposal Missing Proposal.")
checks["unknown_exact_target_asks_for_current_identifier"] =
  missing.include?("Skill Studio item was not found") &&
  missing.include?("Lifecycle: awaiting_input. Mutation: none.")

real_response = SoulCore::ChatResponder.new(root: File.expand_path("..", __dir__)).respond("Show the Skill Studio inventory.")
checks["chat_responder_uses_live_skill_studio_projection"] =
  real_response.include?("Skill Studio inventory") &&
  real_response.include?("Lifecycle: complete. Mutation: none.")

failed = checks.reject { |_name, passed| passed }
puts checks.map { |name, passed| "#{passed ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} Skill Studio conversational checks failed") unless failed.empty?
puts "PASS #{checks.length} Skill Studio conversational checks"
