#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/dev_worker_service"
require_relative "../lib/soul_core/self_augmentation_dev_critique_service"

errors = []
check = lambda do |description, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{description}"
  errors << description unless condition
end

class AugmentationProposalSourceFixture
  attr_accessor :objective

  def initialize(proposal_id)
    @proposal_id = proposal_id
    @objective = "Improve a shared orchestration contract while preserving explicit human gates."
  end

  def proposal(proposal_id:)
    return { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => "unknown augmentation proposal", "mutation" => "none" } unless proposal_id == @proposal_id
    {
      "ok" => true, "lifecycle_state" => "complete", "mutation" => "none",
      "data" => {
        "proposal" => {
          "schema_version" => "soul.self_augmentation.proposal.v1",
          "proposal_id" => @proposal_id,
          "created_at" => "2026-08-01T12:00:00Z",
          "objective" => @objective,
          "why_not_skill" => "The change affects shared orchestration and review contracts rather than one bounded capability.",
          "source_digest" => "a" * 64,
          "head" => "b" * 40,
          "suggested_scope" => ["prepare an isolated candidate change", "add deterministic verification"],
          "prohibited_scope" => ["create a worktree from this proposal", "merge or deploy"],
          "implementation_authorized" => false,
          "human_review_required" => true,
          "stage" => "proposal_review",
          "risk_class" => "class_4"
        },
        "read_only" => true
      }
    }
  end
end

class AugmentationCritiqueResponse
  attr_reader :structured
  def initialize(structured) = @structured = structured
  def ok? = true
  def to_h = { "provider" => "fixture.dev", "model" => "gpt-oss:20b", "status" => "ok", "structured_output" => true }
end

class AugmentationCritiqueClient
  attr_reader :calls
  def initialize(candidate) = (@candidate = candidate; @calls = [])
  def chat(**arguments) = (@calls << arguments; AugmentationCritiqueResponse.new(@candidate))
end

def critique_candidate(ref: "/objective")
  {
    "summary" => "The proposal identifies a cross-cutting contract change but needs a more explicit rollback boundary.",
    "strengths" => [{ "statement" => "The objective names a shared orchestration contract.", "evidence_ref" => ref }],
    "concerns" => [{ "dimension" => "rollback", "statement" => "The proposed scope does not yet state a rollback criterion.", "evidence_ref" => "/suggested_scope/0" }],
    "unknowns" => [{ "question" => "Which compatibility behavior must remain unchanged?", "reason" => "The proposal does not name compatibility invariants." }],
    "revision_questions" => ["What exact rollback condition should Gate A1 reviewers require?"]
  }
end

puts "Self Augmentation Dev Critique A1 verification:"
Dir.mktmpdir("soul-augmentation-dev") do |root|
  proposal_id = "aug_1111111111111111"
  FileUtils.mkdir_p(File.join(root, "Soul", "augmentation", "proposals", proposal_id), mode: 0o700)
  clock = -> { Time.utc(2026, 8, 1, 12, 0, 0) }
  source = AugmentationProposalSourceFixture.new(proposal_id)
  client = AugmentationCritiqueClient.new(critique_candidate)
  worker = SoulCore::DevWorkerService.new(root: root, clock: clock, model_client_factory: ->(_timeout) { client })
  service = SoulCore::SelfAugmentationDevCritiqueService.new(root: root, clock: clock, proposal_source: source, dev_worker: worker)

  missing = service.preview(proposal_id: "aug_2222222222222222")
  check.call("critique requires an existing immutable proposal", missing["lifecycle_state"] == "awaiting_input" && client.calls.empty?)

  preview = service.preview(proposal_id: proposal_id)
  check.call("preview binds exact proposal evidence without invoking the model", preview["ok"] && preview.dig("data", "proposal_sha256").match?(/\A[a-f0-9]{64}\z/) && client.calls.empty?)
  check.call("preview discloses every non-authority boundary", preview.dig("data", "advisory_only") && preview.dig("data", "gate_a1_authorized") == false && preview.dig("data", "worktree_creation_authorized") == false && preview.dig("data", "follow_on_execution_authorized") == false)

  source.objective = "Improve a changed shared orchestration contract while preserving explicit human gates."
  changed = service.execute(proposal_id: proposal_id, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  check.call("changed proposal evidence blocks before model invocation", changed["lifecycle_state"] == "awaiting_input" && client.calls.empty?)

  fresh = service.preview(proposal_id: proposal_id)
  executed = service.execute(proposal_id: proposal_id, confirmation: fresh.dig("data", "confirmation_phrase"), expected_digest: fresh.dig("data", "expected_digest"))
  packet = File.join(root, executed.dig("data", "packet").to_s)
  check.call("confirmed unchanged proposal invokes one bounded Dev request", executed["ok"] && client.calls.length == 1)
  check.call("valid critique creates one immutable owner-private packet", File.file?(File.join(packet, "record.json")) && File.file?(File.join(packet, "REVIEW.md")) && (File.stat(File.join(packet, "record.json")).mode & 0o777) == 0o600)
  check.call("critique cannot approve Gate A1 or create a worktree", executed.dig("data", "critique", "gate_a1_authorized") == false && executed.dig("data", "critique", "worktree_creation_authorized") == false && executed.dig("data", "follow_on_execution_authorized") == false)
  check.call("review exposes the exact cited proposal scalar beside model prose", executed.dig("data", "critique", "candidate", "strengths", 0, "evidence_value") == source.objective)
  check.call("critique path remains proposal-local and contains no worktree", executed.dig("data", "packet").start_with?("Soul/augmentation/proposals/#{proposal_id}/dev_critiques/") && !Dir.exist?(File.join(root, "Soul", "augmentation", "worktrees")))

  replay = service.execute(proposal_id: proposal_id, confirmation: fresh.dig("data", "confirmation_phrase"), expected_digest: fresh.dig("data", "expected_digest"))
  check.call("identical result replays without replacing its packet", replay.dig("data", "idempotent_replay") == true && Dir.glob(File.join(root, "Soul", "augmentation", "proposals", proposal_id, "dev_critiques", "augmentation_critique_*", "record.json")).length == 1)

  bad_proposal_id = "aug_3333333333333333"
  FileUtils.mkdir_p(File.join(root, "Soul", "augmentation", "proposals", bad_proposal_id), mode: 0o700)
  bad_source = AugmentationProposalSourceFixture.new(bad_proposal_id)
  bad_client = AugmentationCritiqueClient.new(critique_candidate(ref: "/not/eligible"))
  bad_worker = SoulCore::DevWorkerService.new(root: root, clock: clock, model_client_factory: ->(_timeout) { bad_client })
  bad_service = SoulCore::SelfAugmentationDevCritiqueService.new(root: root, clock: clock, proposal_source: bad_source, dev_worker: bad_worker)
  bad_preview = bad_service.preview(proposal_id: bad_proposal_id)
  bad = bad_service.execute(proposal_id: bad_proposal_id, confirmation: bad_preview.dig("data", "confirmation_phrase"), expected_digest: bad_preview.dig("data", "expected_digest"))
  check.call("invalid citations fail without writing a critique packet", bad["lifecycle_state"] == "failed" && Dir.glob(File.join(root, "Soul", "augmentation", "proposals", bad_proposal_id, "dev_critiques", "augmentation_critique_*")).empty?)

  facade = SoulCore::ApplicationFacade.new(root: root, self_augmentation_dev_critique_service: service)
  request = {
    "schema_version" => "soul.application.v1", "request_id" => "augmentation-dev-list",
    "operation" => "self_augmentation.dev_critique.list", "parameters" => { "limit" => 5 },
    "context" => { "interface" => "dashboard_test" }
  }
  listed = facade.call(request)
  check.call("application facade exposes bounded critique inventory", listed["lifecycle_state"] == "complete" && listed.dig("data", "count") == 1)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes a distinct advisory proposal critique gate", html.include?('id="preview-augmentation-dev-critique"') && html.include?('id="augmentation-dev-critique-progress"') && html.include?("Critique cannot approve Gate A1 or create a worktree"))
check.call("dashboard binds preview before execute and pre-fills click authority", javascript.index('callSoul("self_augmentation.dev_critique.preview"') < javascript.index('callSoul("self_augmentation.dev_critique.execute"') && javascript.include?('prefillApprovalGate("augmentation-dev-critique-confirmation", "execute-augmentation-dev-critique"'))
dev_javascript = javascript[/function renderAugmentationDevCritiques\(records\).*?^}/m].to_s + javascript[/async function loadAugmentationDevCritiques\(\).*?^}/m].to_s + javascript[/async function previewAugmentationDevCritique\(\).*?^}/m].to_s + javascript[/async function executeAugmentationDevCritique\(\).*?^}/m].to_s
check.call("dashboard uses safe rendering and adds no critique polling", !dev_javascript.match?(/setInterval|setTimeout|WebSocket|EventSource|innerHTML/))

abort "Self Augmentation Dev Critique A1 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Self Augmentation Dev Critique A1 verification complete."
