#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/dev_worker_service"
require_relative "../lib/soul_core/self_assessment_dev_synthesis_service"
require_relative "../lib/soul_core/self_improvement_service"

errors = []
check = lambda do |description, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{description}"
  errors << description unless condition
end

class DevSynthesisEnvironmentFixture
  attr_accessor :hostname

  def initialize
    @hostname = "fixture-one"
  end

  def assess(include_updates: false)
    {
      "assessment" => "environment",
      "read_only" => true,
      "update_checks_requested" => include_updates,
      "system" => { "hostname" => @hostname, "kernel" => "1.0", "architecture" => "x86_64" },
      "package_managers" => { "managers" => { "pacman" => { "detected" => true } } },
      "recommendations" => []
    }
  end
end

class DevSynthesisResponse
  attr_reader :structured

  def initialize(structured)
    @structured = structured
  end

  def ok? = true
  def to_h = { "provider" => "fixture.dev", "model" => "gpt-oss:20b", "status" => "ok", "structured_output" => true }
end

class DevSynthesisClient
  attr_reader :calls

  def initialize(candidate)
    @candidate = candidate
    @calls = []
  end

  def chat(**arguments)
    @calls << arguments
    DevSynthesisResponse.new(@candidate)
  end
end

def candidate(ref: "/assessment/system/hostname")
  {
    "summary" => "The bounded environment evidence is internally consistent.",
    "observations" => [{ "statement" => "A hostname was collected.", "evidence_ref" => ref }],
    "unknowns" => [{ "question" => "Is the host externally reachable?", "reason" => "Network reachability was not collected." }],
    "suggested_next_surfaces" => ["self_assessment"]
  }
end

puts "Self Assessment Dev Synthesis A1 verification:"
Dir.mktmpdir("soul-assessment-dev") do |root|
  environment = DevSynthesisEnvironmentFixture.new
  clock_value = Time.utc(2026, 8, 1, 12, 0, 0)
  clock = -> { clock_value }
  assessment = SoulCore::SelfImprovementService.new(root: root, clock: clock, environment_assessor: environment)
  client = DevSynthesisClient.new(candidate)
  worker = SoulCore::DevWorkerService.new(root: root, clock: clock, model_client_factory: ->(_timeout) { client })
  service = SoulCore::SelfAssessmentDevSynthesisService.new(root: root, clock: clock, assessment_source: assessment, dev_worker: worker)

  missing = service.preview(scope: "environment")
  check.call("synthesis requires an already-collected assessment", missing["lifecycle_state"] == "awaiting_input" && client.calls.empty?)

  assessment.snapshot
  cached = assessment.latest_assessment(scope: "environment")
  cached.dig("data", "assessment", "system")["hostname"] = "tampered"
  check.call("latest evidence is returned as a defensive copy", assessment.latest_assessment(scope: "environment").dig("data", "assessment", "system", "hostname") == "fixture-one")

  preview = service.preview(scope: "environment")
  check.call("preview binds evidence without invoking the model", preview["ok"] && preview.dig("data", "evidence_sha256").match?(/\A[a-f0-9]{64}\z/) && client.calls.empty?)
  check.call("preview discloses advisory-only boundary", preview.dig("data", "advisory_only") == true && preview.dig("data", "follow_on_execution_authorized") == false)

  environment.hostname = "fixture-two"
  clock_value = Time.utc(2026, 8, 1, 12, 1, 0)
  assessment.snapshot
  changed = service.execute(
    scope: "environment",
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("changed evidence blocks before model invocation", changed["lifecycle_state"] == "awaiting_input" && client.calls.empty?)

  fresh = service.preview(scope: "environment")
  executed = service.execute(
    scope: "environment",
    confirmation: fresh.dig("data", "confirmation_phrase"),
    expected_digest: fresh.dig("data", "expected_digest")
  )
  packet = File.join(root, executed.dig("data", "packet").to_s)
  check.call("confirmed unchanged evidence invokes one bounded Dev request", executed["ok"] && client.calls.length == 1)
  check.call("valid synthesis creates one immutable private review packet", File.file?(File.join(packet, "record.json")) && File.file?(File.join(packet, "REVIEW.md")) && (File.stat(File.join(packet, "record.json")).mode & 0o777) == 0o600)
  check.call("review cannot authorize follow-on execution", executed.dig("data", "review", "follow_on_execution_authorized") == false && executed.dig("data", "human_review_required") == true)
  check.call("review exposes the exact cited scalar beside model prose", executed.dig("data", "review", "candidate", "observations", 0, "evidence_value") == "fixture-two")

  replay = service.execute(
    scope: "environment",
    confirmation: fresh.dig("data", "confirmation_phrase"),
    expected_digest: fresh.dig("data", "expected_digest")
  )
  check.call("identical result replays without replacing its packet", replay.dig("data", "idempotent_replay") == true && Dir.glob(File.join(root, SoulCore::SelfAssessmentDevSynthesisService::ROOT, "assessment_review_*", "record.json")).length == 1)

  bad_client = DevSynthesisClient.new(candidate(ref: "/not/eligible"))
  bad_worker = SoulCore::DevWorkerService.new(root: root, clock: clock, model_client_factory: ->(_timeout) { bad_client })
  bad_service = SoulCore::SelfAssessmentDevSynthesisService.new(root: root, clock: clock, assessment_source: assessment, dev_worker: bad_worker)
  bad_preview = bad_service.preview(scope: "environment")
  bad = bad_service.execute(scope: "environment", confirmation: bad_preview.dig("data", "confirmation_phrase"), expected_digest: bad_preview.dig("data", "expected_digest"))
  check.call("invalid evidence citations fail without a packet", bad["lifecycle_state"] == "failed" && Dir.glob(File.join(root, SoulCore::SelfAssessmentDevSynthesisService::ROOT, ".*.tmp-*")).empty?)

  facade = SoulCore::ApplicationFacade.new(root: root, self_improvement_service: assessment, self_assessment_dev_synthesis_service: service)
  request = {
    "schema_version" => "soul.application.v1", "request_id" => "assessment-dev-list",
    "operation" => "self_improvement.dev_synthesis.list", "parameters" => { "limit" => 5 },
    "context" => { "interface" => "dashboard_test" }
  }
  listed = facade.call(request)
  check.call("application facade exposes bounded review inventory", listed["lifecycle_state"] == "complete" && listed.dig("data", "count") == 1)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes a distinct advisory Dev synthesis gate",
           html.include?('id="preview-assessment-dev"') &&
             html.include?('id="assessment-dev-progress"') &&
             html.include?("cannot change evidence, severity, recommendations, plans, or host state"))
check.call("dashboard binds preview before execute and pre-fills exact authority",
           javascript.index('callSoul("self_improvement.dev_synthesis.preview"') < javascript.index('callSoul("self_improvement.dev_synthesis.execute"') &&
             javascript.include?('prefillApprovalGate("assessment-dev-confirmation", "execute-assessment-dev"'))
dev_javascript = javascript[/async function previewAssessmentDevSynthesis\(\).*?^}/m].to_s +
                 javascript[/async function executeAssessmentDevSynthesis\(\).*?^}/m].to_s +
                 javascript[/async function loadAssessmentDevReviews\(\).*?^}/m].to_s
check.call("dashboard adds no synthesis polling or unsafe HTML rendering",
           !dev_javascript.match?(/setInterval|setTimeout|WebSocket|EventSource|innerHTML/))

abort "Self Assessment Dev Synthesis A1 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Self Assessment Dev Synthesis A1 verification complete."
