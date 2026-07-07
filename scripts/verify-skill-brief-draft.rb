#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

cmd = [
  "ruby",
  "Soul/skills/skill/brief/draft.rb",
  "--dry-run",
  "--idea",
  "Create a bounded example skill proposal verifier"
]

stdout, stderr, status = Open3.capture3(*cmd)

unless stderr.to_s.strip.empty?
  warn stderr
end

begin
  parsed = JSON.parse(stdout)
rescue JSON::ParserError => e
  warn "skill.brief.draft did not return valid JSON: #{e.message}"
  warn stdout
  exit 1
end

path = parsed["proposal_path"].to_s

checks = {
  "skill name" => parsed["skill"] == "skill.brief.draft",
  "status ok" => parsed["status"] == "ok",
  "outcome complete" => parsed["outcome"] == "complete",
  "proposal path present" => !path.empty?,
  "proposal exists" => Dir.exist?(path),
  "metadata exists" => File.exist?(File.join(path, "metadata.json")),
  "proposal markdown exists" => File.exist?(File.join(path, "proposal.md")),
  "network not used in dry run" => parsed.dig("verification", "network_used") == false,
  "review artifact only" => parsed.dig("verification", "review_artifact_only") == true,
  "secrets not printed" => parsed.dig("verification", "secrets_printed") == false
}

puts "skill.brief.draft verification:"
checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
end

if checks.values.all? && status.success?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed."
  exit 1
end
