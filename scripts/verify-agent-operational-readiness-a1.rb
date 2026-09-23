#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require_relative "../lib/soul_core/agent_execution_control_plane"

def check(name, condition)
  raise "FAIL: #{name}" unless condition
  puts "PASS: #{name}"
end

Dir.mktmpdir("agent-readiness-") do |root|
  File.write(File.join(root, "REVIEW.md"), "## Human review outcome\n\nOutcome: pending\n")
  link = {
    "schema_version" => "soul.codex.approval_link.v1",
    "link_id" => "approval-link-001",
    "artifact_path" => "REVIEW.md",
    "decision" => "approved",
    "source_kind" => "current_user_message",
    "source_reference" => "thread:synthetic-fixture-turn",
    "scope" => ["reviewed candidate only"],
    "recorded_at" => "2026-09-22T12:00:00-04:00"
  }
  path = File.join(root, "link.json")
  File.write(path, JSON.generate(link))
  control = SoulCore::AgentExecutionControlPlane.new(root: root)
  result = control.validate_approval_link_file("link.json")
  check("link is evidence, not authority", result["ok"] && !result.dig("data", "authorization_granted") && !result.dig("data", "source_verified"))
  check("pending artifact is flagged for reconciliation", result.dig("data", "needs_reconciliation"))
  link["artifact_path"] = "../outside.md"
  File.write(path, JSON.generate(link))
  check("out-of-root artifact rejected", !control.validate_approval_link_file("link.json")["ok"])
  link["artifact_path"] = "REVIEW.md"
  link["scope"] = ["duplicate", "duplicate"]
  File.write(path, JSON.generate(link))
  check("duplicate scope rejected", !control.validate_approval_link_file("link.json")["ok"])
  Dir.mktmpdir("external-artifact-") do |outside|
    File.write(File.join(outside, "REVIEW.md"), "Outcome: approved\n")
    File.symlink(outside, File.join(root, "linked-parent"))
    link["scope"] = ["reviewed candidate only"]
    link["artifact_path"] = "linked-parent/REVIEW.md"
    File.write(path, JSON.generate(link))
    check("symlinked parent escape rejected", !control.validate_approval_link_file("link.json")["ok"])
  end

  fake_cli = File.join(root, "codex")
  doctor = {
    "codexVersion" => "test-version", "overallStatus" => "warning",
    "checks" => {
      "config.load" => { "details" => { "model" => "gpt-6-sol", "private_field" => "do-not-print" } },
      "sandbox.helpers" => { "details" => { "filesystem sandbox" => "unrestricted", "approval policy" => "Never" } }
    }
  }
  File.write(fake_cli, "#!/usr/bin/env ruby\nputs #{JSON.generate(JSON.generate(doctor))}\n")
  File.chmod(0o700, fake_cli)
  out, err, status = Open3.capture3({ "SOUL_CODEX_CLI" => fake_cli }, "ruby", File.join(__dir__, "soul-codex-preflight"))
  preflight = JSON.parse(out)
  check("preflight distinguishes config from active turn", status.success? && preflight["configured_model_for_cli"] == "gpt-6-sol" && preflight["active_turn_model"] == "not_inspected")
  check("preflight filters unrequested doctor data", !out.include?("do-not-print") && err.empty?)
  check("preflight reports timestamped review state", preflight["generated_at"].is_a?(String) && preflight["review_artifacts"].any? { |item| item["path"].end_with?("AGENT_EXECUTION_CONTROL_PLANE_A0_REVIEW.md") && item["human_outcome"] == "pending" })
end

Dir.mktmpdir("approval-cli-", File.expand_path("..", __dir__)) do |dir|
  File.write(File.join(dir, "REVIEW.md"), "Outcome: pending\n")
  File.write(File.join(dir, "link.json"), JSON.generate(
    "schema_version" => "soul.codex.approval_link.v1", "link_id" => "approval-cli-001",
    "artifact_path" => "#{File.basename(dir)}/REVIEW.md", "decision" => "approved",
    "source_kind" => "current_user_message", "source_reference" => "synthetic:current-user-turn",
    "scope" => ["fixture"], "recorded_at" => "2026-09-22T12:00:00-04:00"
  ))
  out, err, status = Open3.capture3("ruby", File.join(__dir__, "soul-agent-control-plane"), "approval-link", "#{File.basename(dir)}/link.json")
  check("approval-link CLI reports mismatch without authority", status.success? && JSON.parse(out).dig("data", "needs_reconciliation") && err.empty?)
end

out, err, status = Open3.capture3("ruby", File.join(__dir__, "codex-policy-eval"))
check("scenario catalog validates without calling a model", status.success? && JSON.parse(out)["scenario_count"] == 6 && err.empty?)

Dir.mktmpdir("policy-score-") do |root|
  catalog = JSON.parse(File.read(File.join(__dir__, "..", "config", "codex_policy_scenarios.json")))
  observations = catalog.fetch("scenarios").map do |item|
    { "id" => item.fetch("id"), "observed_decision" => item.fetch("expected_decision"), "evidence_reference" => "synthetic:#{item.fetch('id')}" }
  end
  path = File.join(root, "results.json")
  File.write(path, JSON.generate("schema_version" => "soul.codex.policy_observations.v1", "observations" => observations))
  out, = Open3.capture3("ruby", File.join(__dir__, "codex-policy-eval"), "--score", path)
  check("complete labeled traces score deterministically", JSON.parse(out)["ok"])
  observations.first["observed_decision"] = "stop_for_human_choice"
  File.write(path, JSON.generate("schema_version" => "soul.codex.policy_observations.v1", "observations" => observations))
  out, _, status = Open3.capture3("ruby", File.join(__dir__, "codex-policy-eval"), "--score", path)
  check("wrong decision is reported and fails", !status.success? && !JSON.parse(out)["ok"])
end

out, err, status = Open3.capture3({ "SOUL_CODEX_CLI" => "/nonexistent/codex" }, "ruby", File.join(__dir__, "soul-codex-preflight"))
check("preflight refuses absent doctor", !status.success? && out.empty? && err.include?("did not return a complete report"))
