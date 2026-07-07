#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "time"

proposal_dir = "Soul/proposals/skills/verify-skill-brief-review"
FileUtils.rm_rf(proposal_dir)
FileUtils.mkdir_p(proposal_dir)

File.write(
  File.join(proposal_dir, "metadata.json"),
  JSON.pretty_generate(
    {
      "artifact_type" => "skill_proposal",
      "purpose" => "verify_skill_brief_review",
      "output_mode" => "review_artifact_only",
      "human_review_required" => true
    }
  ) + "\n"
)

File.write(
  File.join(proposal_dir, "proposal.md"),
  <<~MARKDOWN
    # Skill Proposal: Verify Skill Brief Review

    ## Purpose

    Verify that skill.brief.review can create a review artifact.

    ## User-Facing Behavior

    The verifier creates a tiny proposal and runs review in dry-run mode.

    ## Inputs

    - Proposal folder.

    ## Outputs

    - Review artifact.

    ## Required Config

    - None for dry-run.

    ## Lifecycle States

    - complete
    - failed

    ## Safety Boundaries

    - Review only.
    - No direct repo mutation.

    ## Memory Usage

    None.

    ## Logs and Artifacts

    Writes a review folder.

    ## Failure Behavior

    Return failed with evidence.

    ## Acceptance Criteria

    Review folder exists.

    ## Deterministic Tests

    Dry-run verifier.

    ## Local LLM Behavioral Evals

    None.

    ## Reflection Candidates

    None.

    ## Human Review Checklist

    - [ ] Review artifact exists.
  MARKDOWN
)

File.write(File.join(proposal_dir, "review_checklist.md"), "# Review Checklist\n\n- [ ] Human reviewed.\n")
File.write(File.join(proposal_dir, "sources.md"), "# Sources\n\nNo external sources.\n")

cmd = [
  "ruby",
  "Soul/skills/skill/brief/review.rb",
  "--dry-run",
  "--proposal",
  proposal_dir
]

stdout, stderr, status = Open3.capture3(*cmd)

unless stderr.to_s.strip.empty?
  warn stderr
end

begin
  parsed = JSON.parse(stdout)
rescue JSON::ParserError => e
  warn "skill.brief.review did not return valid JSON: #{e.message}"
  warn stdout
  exit 1
end

review_path = parsed["review_path"].to_s

checks = {
  "skill name" => parsed["skill"] == "skill.brief.review",
  "status ok" => parsed["status"] == "ok",
  "outcome complete" => parsed["outcome"] == "complete",
  "review path present" => !review_path.empty?,
  "review path exists" => Dir.exist?(review_path),
  "metadata exists" => File.exist?(File.join(review_path, "metadata.json")),
  "review markdown exists" => File.exist?(File.join(review_path, "review.md")),
  "network not used in dry run" => parsed.dig("verification", "network_used") == false,
  "review artifact only" => parsed.dig("verification", "review_artifact_only") == true,
  "secrets not printed" => parsed.dig("verification", "secrets_printed") == false
}

puts "skill.brief.review verification:"
checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
end

FileUtils.rm_rf(proposal_dir)

if checks.values.all? && status.success?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed."
  exit 1
end
