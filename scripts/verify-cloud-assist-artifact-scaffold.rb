#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../lib/soul_core/cloud_assist_artifact"

errors = []

artifact = SoulCore::CloudAssistArtifact.create(
  kind: "cloud_assist",
  purpose: "verify artifact scaffold",
  metadata: {
    provider: "local",
    model: "none",
    secrets_included: false,
    private_repo_content_included: false
  },
  files: {
    "provider_response.md" => "# Provider Response\n\nVerification fixture.\n"
  }
)

proposal = SoulCore::CloudAssistArtifact.create(
  kind: "skill_proposal",
  purpose: "verify skill proposal scaffold",
  metadata: {
    provider: "local",
    model: "none",
    secrets_included: false,
    private_repo_content_included: false
  },
  files: {
    "proposal.md" => "# Skill Proposal\n\nVerification fixture.\n",
    "review_checklist.md" => "# Review Checklist\n\n- [ ] Human reviewed.\n"
  }
)

[artifact, proposal].each do |item|
  errors << "Missing artifact path: #{item.path}" unless Dir.exist?(item.path)
  errors << "Missing metadata.json in #{item.path}" unless File.exist?(File.join(item.path, "metadata.json"))

  metadata = JSON.parse(File.read(File.join(item.path, "metadata.json")))
  errors << "metadata output_mode missing in #{item.path}" unless metadata["output_mode"] == "review_artifact_only"
  errors << "metadata human_review_required missing in #{item.path}" unless metadata["human_review_required"] == true
end

puts "Cloud assist artifact scaffold verification:"
puts "- cloud artifact path: #{Dir.exist?(artifact.path) ? 'ok' : 'missing'}"
puts "- skill proposal path: #{Dir.exist?(proposal.path) ? 'ok' : 'missing'}"
puts "- cloud metadata: #{File.exist?(File.join(artifact.path, 'metadata.json')) ? 'ok' : 'missing'}"
puts "- proposal metadata: #{File.exist?(File.join(proposal.path, 'metadata.json')) ? 'ok' : 'missing'}"

# Clean generated verification fixtures so the verifier does not leave runtime
# junk around. Generated folders are ignored, but leaving less junk is still a
# wholesome novelty.
FileUtils.rm_rf(artifact.path)
FileUtils.rm_rf(proposal.path)

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
