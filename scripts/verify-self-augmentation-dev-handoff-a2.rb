#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/dev_worker_service"
require_relative "../lib/soul_core/self_augmentation_dev_handoff_service"

errors = []
check = lambda do |description, condition|
  puts "#{condition ? "PASS" : "FAIL"}: #{description}"
  errors << description unless condition
end

class ExperimentSourceFixture
  attr_reader :source_payload

  def initialize(source_payload)
    @source_payload = source_payload
  end

  def dev_handoff_source(experiment_id:)
    return {
      "ok" => false,
      "lifecycle_state" => "awaiting_input",
      "reason" => "unknown augmentation experiment",
      "mutation" => "none"
    } unless experiment_id.to_s == @source_payload.fetch("experiment").fetch("experiment_id")

    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "mutation" => "none",
      "data" => @source_payload.merge("read_only" => true)
    }
  end
end

class HandoffWorkerResponse
  def initialize(candidate)
    @candidate = candidate
  end

  def to_h
    { "provider" => "fixture.worker", "status" => "complete", "structured_output" => true }
  end

  def ok? = true
  def structured = @candidate
end

class HandoffWorker
  attr_reader :calls

  def initialize(candidate)
    @candidate = candidate
    @calls = []
  end

  def chat(**arguments)
    @calls << arguments
    HandoffWorkerResponse.new(@candidate)
  end
end

def handoff_candidate
  {
    "summary" => "The candidate stays advisory and documents exact scope alignment.",
    "implementation_objectives" => [
      {
        "statement" => "Preserve the exact post-Gate A1 authority boundary while implementing the approved objective.",
        "evidence_ref" => "/proposal/objective"
      }
    ],
    "file_guidance" => [
      {
        "path" => "lib/candidate.rb",
        "responsibility" => "Own the bounded service behavior described by the exact proposal.",
        "verification_expectation" => "Expose deterministic behavior that the approved verifier can exercise."
      },
      {
        "path" => "scripts/verify-candidate.rb",
        "responsibility" => "Own deterministic acceptance coverage for the bounded service behavior.",
        "verification_expectation" => "Cover valid, invalid, and unchanged-evidence outcomes."
      }
    ],
    "compatibility_checks" => [
      {
        "statement" => "The handoff adds only an advisory summary and review pointers.",
        "evidence_ref" => "/experiment/allowed_files/1"
      }
    ],
    "rollback_considerations" => [
      {
        "consideration" => "Replay with current experiment evidence and refuse if pointers change.",
        "evidence_ref" => "/experiment/allowed_files/0"
      }
    ],
    "unknowns" => [
      {
        "question" => "Which exact integration sequencing should follow this review handoff?",
        "reason" => "Integration sequencing depends on downstream external workflow policy."
      }
    ]
  }
end

puts "Self Augmentation Dev Handoff A2 verification:"
Dir.mktmpdir("soul-augmentation-dev-handoff-a2-") do |root|
  experiment_id = "exp_" + "1" * 16
  clock = -> { Time.utc(2026, 8, 1, 12, 0, 0) }
  experiment = {
    "schema_version" => "soul.self_augmentation.experiment.v1",
    "experiment_id" => experiment_id,
    "proposal_id" => "aug_" + "a" * 16,
    "created_at" => clock.call.iso8601,
    "base_commit" => "a" * 40,
    "allowed_files" => ["lib/candidate.rb", "scripts/verify-candidate.rb"]
  }

  proposal = {
    "schema_version" => "soul.self_augmentation.proposal.v1",
    "proposal_id" => experiment.fetch("proposal_id"),
    "head" => experiment.fetch("base_commit"),
    "objective" => "Add one bounded candidate service with deterministic verification.",
    "why_not_skill" => "The shared orchestration contract must change."
  }
  original_handoff = "# Self Augmentation Experiment Handoff\n\nExperiment: `#{experiment_id}`\n"
  source_payload = {
    "experiment" => experiment,
    "proposal" => proposal,
    "original_handoff" => original_handoff,
    "original_handoff_path" => "Soul/augmentation/experiments/#{experiment_id}/CODEX_HANDOFF.md"
  }
  source = ExperimentSourceFixture.new(source_payload)
  worker = HandoffWorker.new(handoff_candidate)
  dev_worker = SoulCore::DevWorkerService.new(root: root, clock: clock, model_client_factory: ->(_timeout) { worker })
  service = SoulCore::SelfAugmentationDevHandoffService.new(root: root, clock: clock, experiment_source: source, dev_worker: dev_worker)
  FileUtils.mkdir_p(File.join(root, "Soul", "augmentation", "experiments", experiment_id))

  missing = service.preview(experiment_id: "exp_" + "f" * 16)
  check.call("missing experiment preview stays blocked for review", missing["lifecycle_state"] == "awaiting_input" && worker.calls.empty?)

  preview = service.preview(experiment_id: experiment_id)
  check.call("preview exposes exact read-only handoff contract", preview["ok"] && preview.dig("data", "read_only") == true && preview.dig("data", "proposal_sha256")&.match?(/\A[a-f0-9]{64}\z/) && preview.dig("data", "original_handoff_sha256")&.match?(/\A[a-f0-9]{64}\z/) && preview.dig("data", "confirmation_phrase")&.start_with?("RUN_SOUL_DEV_WORKER"))
  check.call("preview does not invoke the dev worker", worker.calls.empty?)

  stale = service.execute(
    experiment_id: experiment_id,
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("fresh preview then execute creates exactly one handoff packet", stale["lifecycle_state"] == "complete" && stale.dig("data", "idempotent_replay") == false)

  packet = File.join(root, stale.dig("data", "packet").to_s)
  check.call("handoff packet is written with evidence projection artifacts", File.file?(File.join(packet, "record.json")) && File.file?(File.join(packet, "REVIEW.md")))
  check.call("handoff packet records remain advisory and refuse execution authorizations", stale.dig("data", "handoff", "gate_a1_authorized") == false && stale.dig("data", "handoff", "worktree_creation_authorized") == false && stale.dig("data", "handoff", "follow_on_execution_authorized") == false)
  check.call("handoff packet and artifacts are owner-private", (File.stat(packet).mode & 0o777) == 0o700 && %w[record.json REVIEW.md].all? { |name| (File.stat(File.join(packet, name)).mode & 0o777) == 0o600 })
  check.call("source proposal and original handoff remain unchanged", source.source_payload.fetch("proposal") == proposal && source.source_payload.fetch("original_handoff") == original_handoff)
  check.call("replay with same evidence is idempotent", service.execute(experiment_id: experiment_id, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest")).dig("data", "idempotent_replay") == true)
  check.call("inventory includes recorded handoff packets", service.inventory(limit: 10).dig("data", "count") == 1)

  mutated_preview = service.preview(experiment_id: experiment_id)
  source.source_payload.fetch("experiment")["allowed_files"] << "extra.rb"
  calls_before_changed = worker.calls.length
  changed = service.execute(
    experiment_id: experiment_id,
    confirmation: mutated_preview.dig("data", "confirmation_phrase"),
    expected_digest: mutated_preview.dig("data", "expected_digest")
  )
  check.call("evidence drift refuses after preview before model invocation", changed["lifecycle_state"] == "awaiting_input" && worker.calls.length == calls_before_changed)
  source.source_payload.fetch("experiment")["allowed_files"] = ["lib/candidate.rb", "scripts/verify-candidate.rb"]
  check.call("wrong confirmation is rejected before model invocation", service.execute(experiment_id: experiment_id, confirmation: "WRONG", expected_digest: preview.dig("data", "expected_digest"))["lifecycle_state"] == "awaiting_input")

  invalid_candidate = handoff_candidate.merge("summary" => "```ruby\nputs 'not advisory'\n```")
  invalid_worker = HandoffWorker.new(invalid_candidate)
  invalid_dev_worker = SoulCore::DevWorkerService.new(root: root, clock: clock, model_client_factory: ->(_timeout) { invalid_worker })
  invalid_service = SoulCore::SelfAugmentationDevHandoffService.new(root: root, clock: clock, experiment_source: source, dev_worker: invalid_dev_worker)
  invalid_preview = invalid_service.preview(experiment_id: experiment_id)
  packet_count_before = Dir.glob(File.join(root, "Soul", "augmentation", "experiments", experiment_id, "dev_handoffs", "augmentation_handoff_*" )).length
  invalid_result = invalid_service.execute(experiment_id: experiment_id, confirmation: invalid_preview.dig("data", "confirmation_phrase"), expected_digest: invalid_preview.dig("data", "expected_digest"))
  packet_count_after = Dir.glob(File.join(root, "Soul", "augmentation", "experiments", experiment_id, "dev_handoffs", "augmentation_handoff_*" )).length
  check.call("code-fenced or command-like output fails before packet persistence", invalid_result["lifecycle_state"] == "failed" && packet_count_after == packet_count_before)

  facade = SoulCore::ApplicationFacade.new(root: root, self_augmentation_dev_handoff_service: service)
  facade_request = {
    "schema_version" => "soul.application.v1",
    "request_id" => "augment-dev-handoff-check",
    "operation" => "self_augmentation.dev_handoff.list",
    "parameters" => { "limit" => 5 },
    "context" => { "interface" => "dashboard_test" }
  }
  facade_list = facade.call(facade_request)
  check.call("application facade routes new dev handoff list operation", facade_list["lifecycle_state"] == "complete" && facade_list.dig("data", "count") == 1)

  facade_preview_request = {
    "schema_version" => "soul.application.v1",
    "request_id" => "augment-dev-handoff-preview",
    "operation" => "self_augmentation.dev_handoff.preview",
    "parameters" => { "experiment_id" => experiment_id },
    "context" => { "interface" => "dashboard_test" }
  }
  facade_preview = facade.call(facade_preview_request)
  check.call("application facade routes dev handoff preview", facade_preview["lifecycle_state"] == "complete" && facade_preview.dig("data", "experiment_id") == experiment_id)

  operations = SoulCore::ApplicationContract::OPERATIONS
  check.call("contract allowlists new dev-handoff operations", %w[self_augmentation.dev_handoff.list self_augmentation.dev_handoff.preview self_augmentation.dev_handoff.execute].all? { |operation| operations.key?(operation) })
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes explicit post-Gate A1 Dev handoff controls", %w[preview-augmentation-dev-handoff execute-augmentation-dev-handoff augmentation-dev-handoff-progress augmentation-dev-handoffs].all? { |id| html.include?(%Q{id="#{id}"}) })
handoff_javascript = javascript[/function renderAugmentationDevHandoffs\(records\).*?function previewAugmentationDevCritique\(/m].to_s
check.call("dashboard binds preview before execution and adds no polling", handoff_javascript.include?('self_augmentation.dev_handoff.preview') && handoff_javascript.include?('self_augmentation.dev_handoff.execute') && handoff_javascript.index('self_augmentation.dev_handoff.preview') < handoff_javascript.index('self_augmentation.dev_handoff.execute') && !handoff_javascript.match?(/setInterval|WebSocket|EventSource/))

abort "Self Augmentation Dev Handoff A2 verification failed: #{errors.join(", ")}" unless errors.empty?
puts "Self Augmentation Dev Handoff A2 verification complete."
