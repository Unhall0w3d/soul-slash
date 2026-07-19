#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 1 verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/conversational_architecture_assessor.rb
  docs/CONVERSATIONAL_SOUL_ARCHITECTURE.md
  docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE1.md
  docs/MILESTONES.md
  CHANGELOG.md
  scripts/verify-conversational-architecture-phase1.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversational-architecture",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "conversational_architecture" &&
  json["milestone"] == "conversational_soul" &&
  json["phase"] == 1 &&
  json["ok"] == true &&
  json.dig("verification", "required_documents_present") == true &&
  json.dig("verification", "architecture_contract_complete") == true &&
  json.dig("verification", "acceptance_contract_complete") == true &&
  json.dig("verification", "anti_patterns_documented") == true &&
  json.dig("verification", "current_phase_roadmap") == true &&
  json.dig("verification", "phase_thirteen_stopping_point") == true &&
  json.dig("verification", "deterministic_action_boundary_preserved") == true &&
  json.dig("verification", "codex_boundary_preserved") == true

check("conversational architecture assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversational-architecture"
)

text_ok =
  status.success? &&
  stdout.include?("Soul Conversational Architecture Assessment") &&
  stdout.include?("Phase: 1") &&
  stdout.include?("Status: ready")

check("conversational architecture text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
acceptance = File.read("docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md")
architecture = File.read("docs/CONVERSATIONAL_SOUL_ARCHITECTURE.md")
milestones = File.read("docs/MILESTONES.md")
changelog = File.read("CHANGELOG.md")

current_sequence = (1..13).all? { |phase| roadmap.match?(/^\#{2,3} Phase #{phase}(?::|\s|\s—)/) }
check("roadmap covers the current Phase 1 through Phase 13 sequence", current_sequence && roadmap.include?("Phase 13 is the clear stopping point"), errors)
check("acceptance includes twenty-turn continuity", acceptance.include?("at least twenty turns"), errors)
check("architecture preserves action safety", architecture.include?("plan -> approval -> execute -> verify -> record"), errors)
check("milestone has a valid lifecycle status", milestones.match?(/### Conversational Soul.*?Status:\s*(?:\*\*)?(?:in progress|complete)/mi), errors)
check("changelog records Phase 1", changelog.include?("Conversational Soul") && changelog.include?("Phase 1"), errors)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-conversational-architecture-phase1.rb"]
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
  puts "Conversational Soul Phase 1 is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
