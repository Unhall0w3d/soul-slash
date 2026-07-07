#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "yaml"

errors = []

registry_path = "Soul/skills/registry.yaml"
registry = YAML.safe_load(File.read(registry_path), aliases: true)

registry_text = File.read(registry_path)
%w[
  cloud.providers.list
  cloud.providers.test
  skill.brief.draft
  skill.brief.review
].each do |name|
  errors << "Registry missing #{name}" unless registry_text.include?(name)
end

commands = [
  {
    name: "cloud.providers.list",
    cmd: ["ruby", "bin/soul", "skill", "cloud.providers.list", "--", "--config", "Soul/config/cloud_providers.example.yaml"]
  },
  {
    name: "cloud.providers.test",
    cmd: ["ruby", "bin/soul", "skill", "cloud.providers.test", "--", "--provider", "mistral", "--config", "Soul/config/cloud_providers.example.yaml"]
  },
  {
    name: "skill.brief.draft",
    cmd: ["ruby", "bin/soul", "skill", "skill.brief.draft", "--", "--dry-run", "--idea", "Verify registry integration for skill brief draft"]
  }
]

proposal_dir = "Soul/proposals/skills/verify-registry-skill-brief-review"
FileUtils.rm_rf(proposal_dir)
FileUtils.mkdir_p(proposal_dir)
File.write(File.join(proposal_dir, "proposal.md"), "# Skill Proposal: Registry Review Verify\n\n## Purpose\n\nVerify registry integration.\n")
File.write(File.join(proposal_dir, "metadata.json"), JSON.pretty_generate({ "artifact_type" => "skill_proposal" }) + "\n")
File.write(File.join(proposal_dir, "review_checklist.md"), "# Review Checklist\n\n- [ ] Human reviewed.\n")
File.write(File.join(proposal_dir, "sources.md"), "# Sources\n\nNo external sources.\n")

commands << {
  name: "skill.brief.review",
  cmd: ["ruby", "bin/soul", "skill", "skill.brief.review", "--", "--dry-run", "--proposal", proposal_dir]
}

puts "bin/soul cloud skill integration verification:"

commands.each do |item|
  stdout, stderr, status = Open3.capture3(*item[:cmd])

  if !stderr.to_s.strip.empty?
    warn "#{item[:name]} stderr:"
    warn stderr
  end

  begin
    parsed = JSON.parse(stdout)
  rescue JSON::ParserError
    errors << "#{item[:name]} did not return JSON"
    puts "- #{item[:name]}: missing"
    next
  end

  ok = status.success? && parsed["skill"].to_s == item[:name] && %w[ok warning].include?(parsed["status"].to_s)
  errors << "#{item[:name]} failed via bin/soul" unless ok
  puts "- #{item[:name]}: #{ok ? 'ok' : 'missing'}"
end

FileUtils.rm_rf(proposal_dir)

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
