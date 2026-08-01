#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/local_development_model_client"
require_relative "../lib/soul_core/skill_studio_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class DevBuildModelFixture
  attr_reader :calls

  def initialize(source:)
    @source = source
    @calls = []
  end

  def chat(**options)
    @calls << options
    structured = {
      "description" => "Echo one bounded value as JSON", "risk" => "read_only",
      "requires_approval" => false, "confirmation_phrase" => "", "expected_output" => "json",
      "timeout_seconds" => 5, "inputs" => ["one optional text argument"],
      "known_weaknesses" => ["This fixture only echoes one value."],
      "failure_behavior" => ["Return awaiting_input when no value is supplied."],
      "skill_rb" => @source,
      "test_cases" => [
        { "id" => "echo_value", "description" => "Echoes the supplied value", "args" => ["hello"], "expected_ok" => true, "expected_lifecycle" => "complete" },
        { "id" => "missing_value", "description" => "Requests a value", "args" => [], "expected_ok" => false, "expected_lifecycle" => "awaiting_input" }
      ]
    }
    SoulCore::LocalDevelopmentModelClient::Response.new(
      provider: "local.dev", model: "gpt-oss:20b", status: "ok", http_status: 200,
      content: JSON.generate(structured), structured:, error_message: nil, duration_seconds: 1.25,
      runtime_receipt: { "selected_dev_core" => false }
    )
  end
end

class DevBuildRunnerFixture
  attr_reader :commands

  def initialize = (@commands = [])

  def run(*command, **_options)
    @commands << command
    if command.include?("-c")
      result(true, "Syntax OK")
    elsif command.include?("hello")
      result(true, JSON.generate("ok" => true, "lifecycle_state" => "complete", "value" => "hello"))
    else
      result(true, JSON.generate("ok" => false, "lifecycle_state" => "awaiting_input"))
    end
  end

  private

  def result(ok, stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "#{stdout}\n", stderr: "", exit_status: ok ? 0 : 1, status: ok ? "ok" : "failed", truncated: false)
  end
end

def prepare_fixture(root, service, proposal_id: "proposal_fixture", skill_id: "fixture.echo")
  directory = File.join(root, "Soul/proposals/skills", proposal_id)
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "metadata.json"), JSON.pretty_generate("title" => "Echo", "created_at" => "2026-07-31T00:00:00Z") + "\n")
  File.write(File.join(directory, "proposal.md"), "# Skill Proposal: Echo\n\n## Purpose\nEcho one supplied value through a bounded JSON CLI.\n")
  preview = service.proposal_approval_preview(proposal_id:)
  service.approve_proposal(proposal_id:, expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::SkillStudioService::PROPOSAL_CONFIRMATION)
  build = service.beta_build_preview(proposal_id:, skill_id:)
  service.prepare_beta_build(proposal_id:, skill_id:, expected_digest: build.dig("data", "expected_digest"), confirmation: build.dig("data", "confirmation_phrase"))
end

source = <<~RUBY
  # frozen_string_literal: true
  require "json"
  value = ARGV.first
  if value
    puts JSON.generate("ok" => true, "lifecycle_state" => "complete", "value" => value)
  else
    puts JSON.generate("ok" => false, "lifecycle_state" => "awaiting_input", "reason" => "value required")
  end
RUBY

puts "Soul Dev Core Skill Studio build verification:"
Dir.mktmpdir("soul-dev-skill-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), "---\nschema_version: soul.skills.v1\nskills: {}\n")
  model = DevBuildModelFixture.new(source:)
  runner = DevBuildRunnerFixture.new
  service = SoulCore::SkillStudioService.new(root:, development_model_client: model, runner:,
    ruby_path: "/usr/bin/ruby", bwrap_path: "/usr/bin/bwrap")
  prepare_fixture(root, service)

  preview = service.dev_build_preview(beta_id: "fixture.echo")
  check.call("approved incomplete Beta exposes one exact local Dev build gate", preview.dig("data", "confirmation_phrase") == "BUILD_BETA_WITH_DEV_CORE fixture.echo" && preview.dig("data", "vault_access") == false)
  stale = service.build_beta_with_dev_core(beta_id: "fixture.echo", expected_digest: "0" * 64, confirmation: preview.dig("data", "confirmation_phrase"))
  check.call("stale preview invokes no model and changes no candidate", stale["lifecycle_state"] == "blocked_for_human_review" && model.calls.empty?)
  built = service.build_beta_with_dev_core(beta_id: "fixture.echo", expected_digest: preview.dig("data", "expected_digest"), confirmation: preview.dig("data", "confirmation_phrase"))
  record = service.beta(beta_id: "fixture.echo").dig("data", "record")
  check.call("one local draft becomes a runnable Beta only after all isolated checks pass", built.dig("data", "implementation_complete") == true && record["runnable"] && record.dig("test_summary", "passed") == 3 && record.dig("test_summary", "tested_current_revision"))
  check.call("machine gate never approves promotion or touches production", record["promotion_state"] == "not_ready" && Dir.children(File.join(root, "Soul/skills")).sort == ["registry.yaml"])
  check.call("review artifact records model, tests, risk, lifecycle, memory, and human checklist", File.read(File.join(root, "Soul/proposals/skills/proposal_fixture/beta/REVIEW.md")).include?("Soul Vault was not read or written") && File.read(File.join(root, "Soul/proposals/skills/proposal_fixture/beta/REVIEW.md")).include?("Human review checklist"))
  check.call("test runner is networkless and read-only", runner.commands.reject { |command| command.include?("-c") }.all? { |command| command.include?("--unshare-all") && command.include?("--ro-bind") })
  run_preview = service.beta_run_preview(beta_id: "fixture.echo", args: ["human-review"])
  run = service.run_beta(beta_id: "fixture.echo", args: ["human-review"], expected_digest: run_preview.dig("data", "expected_digest"), confirmation: run_preview.dig("data", "confirmation_phrase"))
  run_command = runner.commands.last
  check.call("human execution of a local Dev Beta retains its networkless read-only sandbox",
             run_preview.dig("data", "execution_isolation") == "networkless_read_only_bubblewrap" && run["ok"] &&
               run_command.include?("--unshare-all") && run_command.each_cons(2).any? { |left, right| left == "--ro-bind" && right == File.join(root, "Soul/proposals/skills/proposal_fixture/beta") })
end

Dir.mktmpdir("soul-dev-skill-policy-") do |root|
  model = DevBuildModelFixture.new(source: "require 'json'\nsystem('id')\n")
  service = SoulCore::SkillStudioService.new(root:, development_model_client: model, runner: DevBuildRunnerFixture.new,
    ruby_path: "/usr/bin/ruby", bwrap_path: "/usr/bin/bwrap")
  prepare_fixture(root, service, proposal_id: "policy_fixture", skill_id: "fixture.blocked")
  preview = service.dev_build_preview(beta_id: "fixture.blocked")
  blocked = service.build_beta_with_dev_core(beta_id: "fixture.blocked", expected_digest: preview.dig("data", "expected_digest"), confirmation: preview.dig("data", "confirmation_phrase"))
  record = service.beta(beta_id: "fixture.blocked").dig("data", "record")
  check.call("generated shell or subprocess behavior fails before machine execution", blocked["lifecycle_state"] == "failed" && record["implementation_complete"] == false)
end

contract = File.read(File.join(__dir__, "../lib/soul_core/application_contract.rb"))
facade = File.read(File.join(__dir__, "../lib/soul_core/application_facade.rb"))
dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
check.call("Dashboard contract exposes detached progress for the exact Dev build only", contract.include?("skill_studio.betas.dev_build.execute") && facade.include?("build_beta_with_dev_core") && dashboard.include?('"/api/v1/music-job-stream", "skill_studio.betas.dev_build.execute"'))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Dev Core Skill Studio Beta build is candidate-ready for human review."
