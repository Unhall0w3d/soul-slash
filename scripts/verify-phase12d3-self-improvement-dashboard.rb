#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/self_improvement_service"

errors = []
check = lambda do |description, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{description}"
  errors << description unless condition
end

class FixtureEnvironment
  attr_reader :calls
  def initialize
    @calls = []
  end
  def assess(include_updates: false)
    @calls << include_updates
    {
      "assessment" => "environment", "read_only" => true, "update_checks_requested" => include_updates,
      "system" => { "os_pretty_name" => "Fixture Linux", "kernel" => "1.0", "architecture" => "x86_64", "hostname" => "fixture" },
      "package_managers" => { "managers" => { "pacman" => { "detected" => true, "updates" => include_updates ? { "count" => 2 } : nil } } },
      "runtimes" => { "runtimes" => { "ruby" => { "detected" => true, "version" => "ruby fixture" } } },
      "soul_project" => { "git" => { "dirty" => false } },
      "recommendations" => []
    }
  end
end

class FixtureModel
  def assess(include_processes: false)
    raise "process checks must remain disabled" if include_processes
    { "assessment" => "model_runtime", "read_only" => true, "endpoints" => {}, "recommendations" => [] }
  end
end

class SlowFixtureModel
  def assess(include_processes: false)
    raise "process checks must remain disabled" if include_processes
    sleep 0.2
    { "assessment" => "model_runtime" }
  end
end

class FixtureCapabilities
  def assess(persist: false)
    raise "capability refresh must not persist" if persist
    { "assessment" => "capability_matrix", "read_only" => true, "summary" => { "available" => 5, "partial" => 1, "missing" => 2, "blocked" => 0 }, "recommendations" => [] }
  end
end

class FixtureProposalGenerator
  attr_reader :writes
  def initialize
    @writes = 0
  end
  def generate(write_files: false)
    @writes += 1 if write_files
    {
      "proposal_count" => 1,
      "written_count" => write_files ? 1 : 0,
      "source_summary" => { "available" => 5, "partial" => 1, "missing" => 2, "blocked" => 0 },
      "proposals" => [{ "id" => "fixture", "rank" => 1, "title" => "Fixture proposal", "priority" => "medium", "summary" => "Fixture", "status" => "draft", "requires_human_approval" => true, "implementation_allowed" => false }]
    }
  end
end

puts "Phase 12D.3 Self Improvement dashboard verification:"
Dir.mktmpdir("soul-self-improvement") do |root|
  environment = FixtureEnvironment.new
  generator = FixtureProposalGenerator.new
  service = SoulCore::SelfImprovementService.new(
    root: root,
    environment_assessor: environment,
    model_assessor: FixtureModel.new,
    capability_matrix: FixtureCapabilities.new,
    proposal_generator: generator
  )

  snapshot = service.snapshot
  check.call("automatic snapshot is read-only and skips update checks", snapshot.dig("data", "automatic") == true && snapshot.dig("data", "read_only") == true && environment.calls == [false])

  updates = service.refresh(scope: "updates")
  check.call("update checks require an explicit bounded scope", updates.dig("data", "assessment", "update_checks_requested") == true && environment.calls == [false, true])
  check.call("unknown assessment scope awaits input", service.refresh(scope: "everything")["lifecycle_state"] == "awaiting_input")
  check.call("model assessment disables process inventory", service.refresh(scope: "models").dig("data", "read_only") == true)
  check.call("capability assessment is non-persisting", service.refresh(scope: "capabilities").dig("data", "assessment", "summary", "available") == 5)

  timed_service = SoulCore::SelfImprovementService.new(root: root, model_assessor: SlowFixtureModel.new, assessment_timeout_seconds: 0.02)
  timed_result = timed_service.refresh(scope: "models")
  check.call("overlong assessment terminates with failed lifecycle", timed_result["lifecycle_state"] == "failed" && timed_result["reason"].include?("foreground limit"))

  preview = service.proposal_preview
  blocked = service.generate_proposals(confirmation: "wrong", expected_digest: preview.dig("data", "expected_digest"))
  check.call("proposal write blocks without exact human confirmation", blocked["lifecycle_state"] == "blocked_for_human_review" && generator.writes.zero?)
  executed = service.generate_proposals(confirmation: SoulCore::SelfImprovementService::CONFIRMATION, expected_digest: preview.dig("data", "expected_digest"))
  check.call("confirmed unchanged preview writes advisory packets only", executed["lifecycle_state"] == "complete" && executed.dig("data", "written_count") == 1 && executed.dig("data", "implementation_started") == false && generator.writes == 1)

  facade = SoulCore::ApplicationFacade.new(root: root, self_improvement_service: service)
  request = { "schema_version" => "soul.application.v1", "request_id" => "self-improvement-fixture", "operation" => "application.bootstrap", "parameters" => {}, "context" => { "interface" => "dashboard_test" } }
  bootstrap = facade.call(request)
check.call("application exposes Self Assessment as the third tab", bootstrap.dig("data", "product_tabs") == ["Chat", "Skill Studio", "Self Assessment"] && bootstrap.dig("data", "self_improvement", "host_mutation_available") == false)

  generator_root = File.join(root, "generator")
  Dir.mkdir(generator_root)
  actual_generator = SoulCore::ImprovementProposalGenerator.new(root: generator_root)
  first_write = actual_generator.generate(write_files: true)
  second_write = actual_generator.generate(write_files: true)
  check.call("identical improvement candidates are not duplicated", first_write["written_count"].positive? && second_write["written_count"].zero?)
end

runner = SoulCore::BoundedCommandRunner.new
timeout = runner.run("ruby", "-e", "sleep 2", timeout_seconds: 0.05, max_output_bytes: 1024)
check.call("assessment command runner terminates timed-out foreground work", timeout.status == "timeout")

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes the third ARIA tab and assessment scopes", html.include?('id="improvement-tab"') && html.include?('id="improvement-panel"') && %w[environment updates models capabilities].all? { |scope| html.include?("data-assessment-scope=\"#{scope}\"") })
check.call("dashboard requires preview and exact proposal confirmation", javascript.index('callSoul("self_improvement.proposals.preview"') < javascript.index('callSoul("self_improvement.proposals.execute"') && javascript.include?("confirmation_phrase") && html.include?("GENERATE_SELF_IMPROVEMENT_PROPOSALS"))
check.call("dashboard adds no polling or unsafe HTML rendering", !javascript.match?(/setInterval|setTimeout|WebSocket|EventSource|innerHTML/))
check.call("dashboard bounds manual assessment requests and clears running state on failure", javascript.include?("AbortSignal.timeout(35_000)") && javascript.include?('`${scope} · failed`'))
check.call("host mutation remains visibly separated and approval-gated", html.include?("Host changes require separate approval") && html.include?("separately reviewed executors") && html.include?("Self Assessment only inspects"))

abort "Phase 12D.3 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Phase 12D.3 Self Improvement dashboard verification complete."
