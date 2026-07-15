#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Post-usability repository hygiene verification:"

required = %w[
  README.md
  CHANGELOG.md
  MANIFEST.txt
  docs/ARCHITECTURE.md
  docs/INTERACTION_ARCHITECTURE.md
  docs/MILESTONES.md
  docs/maintenance/POST_USABILITY_REPOSITORY_HYGIENE.md
  scripts/verify-post-usability-repository-hygiene.rb
]

required.each do |path|
  check(path, File.exist?(path), errors)
end

readme = File.read("README.md")
architecture = File.read("docs/ARCHITECTURE.md")
interaction = File.read("docs/INTERACTION_ARCHITECTURE.md")
milestones = File.read("docs/MILESTONES.md")
changelog = File.read("CHANGELOG.md")
manifest = File.read("MANIFEST.txt")
maintenance = File.read("docs/maintenance/POST_USABILITY_REPOSITORY_HYGIENE.md")

check(
  "README selects Conversational Soul",
  readme.include?("Conversational Soul") &&
    readme.include?("Safe local action: complete"),
  errors
)

check(
  "README removes stale near-term Downloads backlog",
  !readme.include?("strengthen Downloads cleanup and restore regression testing") &&
    !readme.include?("improve workflow/session listing and pruning"),
  errors
)

check(
  "architecture includes conversation, artifact, and policy layers",
  architecture.include?("## Conversation layer") &&
    architecture.include?("## Artifact layer") &&
    architecture.include?("## Policy and audit layer"),
  errors
)

check(
  "interaction architecture states current implementation posture",
  interaction.include?("## Current implementation posture") &&
    interaction.include?("persistent model-backed multi-turn conversation") &&
    interaction.include?("Humor is optional"),
  errors
)

check(
  "milestones track the current phase sequence",
  milestones.include?("Conversational Soul") &&
    milestones.include?("Phase 1") &&
    milestones.include?("Phase 12D.3") &&
    milestones.include?("Phase 13"),
  errors
)

check(
  "changelog reflects current milestone progress",
  changelog.include?("Conversational Soul") &&
    changelog.include?("Phase 12D.3") &&
    changelog.include?("Phase 12E"),
  errors
)

check(
  "manifest is repository-oriented",
  manifest.start_with?("Soul/ Repository Manifest") &&
    !manifest.include?("Soul Codex Overlay v0.1.0"),
  errors
)

check(
  "maintenance baseline is recorded",
  maintenance.include?("commit: 2132b36"),
  errors
)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-post-usability-repository-hygiene.rb"]
untracked =
  if curation && curation["untracked_review_candidates"].is_a?(Array)
    curation["untracked_review_candidates"]
  else
    []
  end

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  (untracked - allowed).empty?

check("repo curation", curation_ok, errors)

unless curation_ok
  warn stderr
  warn stdout
end

if errors.empty?
  puts "Verification complete."
  puts "Repository documentation is aligned through Conversational Soul Phase 12D.3."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
