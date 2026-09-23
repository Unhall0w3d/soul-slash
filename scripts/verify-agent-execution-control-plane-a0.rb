#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
CLI = File.join(ROOT, "scripts", "soul-agent-control-plane")
failures = []

check = lambda do |name, condition|
  puts "- #{name}: #{condition ? 'PASS' : 'FAIL'}"
  failures << name unless condition
end

run = lambda do |*args|
  stdout, stderr, status = Open3.capture3("ruby", CLI, *args, chdir: ROOT)
  [JSON.parse(stdout), stderr, status]
end

write_json = lambda do |path, value|
  File.write(path, JSON.pretty_generate(value))
end

puts "agent execution control plane A0 verification:"

Dir.mktmpdir("soul-agent-control-plane", ROOT) do |dir|
  relative_dir = Pathname.new(dir).relative_path_from(Pathname.new(ROOT)).to_s

  assignment = {
    "schema_version" => "soul.codex.subagent_assignment.v1",
    "assignment_id" => "map-policy-001",
    "role" => "mapper",
    "objective" => "Map the policy execution path.",
    "expected_deliverable" => "Exact evidence with paths and uncertainties.",
    "scope" => { "mode" => "read_only", "paths" => ["AGENTS.md"] },
    "acceptance_commands" => ["rg -n policy AGENTS.md"],
    "authority_limits" => ["Read-only; no external systems."],
    "non_goals" => ["No implementation or promotion."],
    "shared_worktree" => { "preserve_existing_changes" => true },
    "evidence_required" => %w[changed_paths commands results uncertainties scope_deviations]
  }
  assignment_path = File.join(dir, "assignment.json")
  write_json.call(assignment_path, assignment)
  result, = run.call("assignment", File.join(relative_dir, "assignment.json"))
  check.call("valid read-only assignment", result["ok"] && result.dig("data", "role") == "mapper")

  assignment["scope"]["mode"] = "owned_paths"
  write_json.call(assignment_path, assignment)
  result, = run.call("assignment", File.join(relative_dir, "assignment.json"))
  check.call("read-only role cannot claim owned paths", !result["ok"] && result["errors"].any? { |item| item.include?("mapper scope mode") })

  assignment["scope"]["mode"] = "read_only"
  assignment["unexpected"] = true
  write_json.call(assignment_path, assignment)
  result, = run.call("assignment", File.join(relative_dir, "assignment.json"))
  check.call("unknown assignment field fails closed", !result["ok"] && result["errors"].any? { |item| item.include?("unknown fields") })

  receipt = {
    "schema_version" => "soul.skill.lifecycle_receipt.v1",
    "receipt_id" => "skill-run-001",
    "subject" => "example-skill",
    "lifecycle_state" => "complete",
    "started_at" => "2026-09-21T12:00:00Z",
    "ended_at" => "2026-09-21T12:00:01Z",
    "message" => "Bounded run completed.",
    "continuation" => {
      "kind" => "none",
      "processes_remaining" => 0,
      "authorization_reference" => nil,
      "inspect_command" => nil,
      "stop_command" => nil,
      "recovery_notes" => nil
    },
    "evidence_paths" => []
  }
  receipt_path = File.join(dir, "receipt.json")
  write_json.call(receipt_path, receipt)
  result, = run.call("lifecycle", File.join(relative_dir, "receipt.json"))
  check.call("terminal lifecycle without continuation", result["ok"] && result.dig("data", "lifecycle_state") == "complete")

  receipt["continuation"] = {
    "kind" => "approved_persistent",
    "processes_remaining" => 1,
    "authorization_reference" => nil,
    "inspect_command" => "systemctl status example",
    "stop_command" => "systemctl stop example",
    "recovery_notes" => "Disable and remove the approved unit."
  }
  write_json.call(receipt_path, receipt)
  result, = run.call("lifecycle", File.join(relative_dir, "receipt.json"))
  check.call("continuation requires authorization evidence", !result["ok"] && result["errors"].any? { |item| item.include?("authorization_reference") })

  review = <<~MARKDOWN
    # Skill Candidate Review
    ## Skill
    Name: example
    Risk class: Class 2
    ## Candidate status
    candidate_complete
    ## Implementation summary
    Example.
    ## Files changed
    - example
    ## Commands run
    - example
    ## Deterministic test results
    PASS
    ## Local LLM eval results
    Not applicable.
    ## Memory keys
    None.
    ## Lifecycle states touched
    `complete`
    ## Safety and persistence check
    No persistence.
    ## Known weaknesses
    None.
    ## Human review checklist
    - [ ] Review candidate.
  MARKDOWN
  review_path = File.join(dir, "REVIEW.md")
  File.write(review_path, review)
  result, = run.call("review", File.join(relative_dir, "REVIEW.md"))
  check.call("canonical review packet", result["ok"] && result.dig("data", "candidate_status") == "candidate_complete")

  File.write(review_path, review.sub("## Known weaknesses\nNone.\n", ""))
  result, = run.call("review", File.join(relative_dir, "REVIEW.md"))
  check.call("missing review heading fails", !result["ok"] && result["errors"].any? { |item| item.include?("Known weaknesses") })

  result, = run.call("required-checks", "AGENTS.md", ".codex/agents/mapper.toml", "lib/soul_core/example.rb")
  checks = result.dig("data", "checks") || []
  check.call("changed paths resolve deduplicated checks", result["ok"] && checks.uniq == checks && %w[agent_control_plane toml_parse ruby_syntax targeted_behavior review_packet].all? { |item| checks.include?(item) })
  check.call("unmatched persistence checks are not introduced", !checks.include?("persistence_advisory"))

  unit_path = File.join(dir, "example.service")
  File.write(unit_path, "[Service]\nExecStart=/usr/bin/example\n")
  result, = run.call("persistence", File.join(relative_dir, "example.service"))
  findings = result.dig("data", "findings") || []
  check.call("persistence classification is advisory with evidence", result["ok"] && result.dig("data", "advisory") == true && result.dig("data", "authorization_granted") == false && findings.any? { |item| item["kind"] == "systemd_unit_section" })

  outside = File.join(Dir.tmpdir, "soul-agent-control-plane-outside.json")
  write_json.call(outside, assignment)
  result, = run.call("assignment", outside)
  check.call("out-of-repository inputs fail closed", !result["ok"] && result["errors"].any? { |item| item.include?("inside the repository") })
  FileUtils.rm_f(outside)

  symlink_path = File.join(dir, "linked.json")
  File.symlink(assignment_path, symlink_path)
  result, = run.call("assignment", File.join(relative_dir, "linked.json"))
  check.call("symlink inputs fail closed", !result["ok"] && result["errors"].any? { |item| item.include?("non-symlink") })
end

schema_paths = %w[
  docs/soul/schemas/codex_subagent_assignment.schema.json
  docs/soul/schemas/skill_lifecycle_receipt.schema.json
  config/codex_required_checks.json
]
schema_paths.each do |path|
  parsed = JSON.parse(File.read(File.join(ROOT, path)))
  check.call("#{path} parses", parsed.is_a?(Hash))
end

toml_paths = %w[mapper implementer reviewer].map { |name| File.join(ROOT, ".codex", "agents", "#{name}.toml") }
python = <<~PYTHON
  import pathlib, sys, tomllib
  for value in sys.argv[1:]:
      tomllib.loads(pathlib.Path(value).read_text())
PYTHON
_stdout, _stderr, toml_status = Open3.capture3("python", "-c", python, *toml_paths)
check.call("custom agent TOMLs parse", toml_status.success?)

roles = toml_paths.to_h { |path| [File.basename(path, ".toml"), File.read(path)] }
check.call("mapper and reviewer are read-only", roles.fetch("mapper").include?('sandbox_mode = "read-only"') && roles.fetch("reviewer").include?('sandbox_mode = "read-only"'))
check.call("implementer is workspace-write", roles.fetch("implementer").include?('sandbox_mode = "workspace-write"'))
check.call("role files do not pin models", roles.values.none? { |text| text.match?(/^model(?:_reasoning_effort)?\s*=/) })

if failures.empty?
  puts "Verification complete: all checks passed."
  exit 0
end

warn "Verification failed: #{failures.join(', ')}"
exit 1
