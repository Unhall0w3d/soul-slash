#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/improvement_proposal_generator"
require_relative "../lib/soul_core/improvement_proposal_paths"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 11C readiness verification:"

required = %w[
  .ruby-version
  .github/workflows/ruby-smoke.yml
  lib/soul_core/improvement_proposal_paths.rb
  lib/soul_core/improvement_proposal_generator.rb
  lib/soul_core/proposal_locator.rb
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION_BRIEF.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE11C_READINESS.md
]
required.each { |path| check(path, File.exist?(path), errors) }

root = Dir.pwd
default_root = SoulCore::ImprovementProposalPaths.relative_root(root: root, env: {})
verification_root = SoulCore::ImprovementProposalPaths.relative_root(
  root: root,
  env: { "SOUL_IMPROVEMENT_PROPOSALS_ROOT" => "Soul/runtime/verification/readiness-check" }
)

outside_rejected = begin
  SoulCore::ImprovementProposalPaths.relative_root(
    root: root,
    env: { "SOUL_IMPROVEMENT_PROPOSALS_ROOT" => "../outside" }
  )
  false
rescue ArgumentError
  true
end

project_override_rejected = begin
  SoulCore::ImprovementProposalPaths.relative_root(
    root: root,
    env: { "SOUL_IMPROVEMENT_PROPOSALS_ROOT" => "docs/proposals" }
  )
  false
rescue ArgumentError
  true
end

check("default proposal root is unchanged", default_root == "Soul/improvement/proposals", errors)
check("verification proposal root is allowed", verification_root == "Soul/runtime/verification/readiness-check", errors)
check("outside proposal root is rejected", outside_rejected, errors)
check("non-runtime override is rejected", project_override_rejected, errors)

generator = SoulCore::ImprovementProposalGenerator.new(
  root: root,
  env: { "SOUL_IMPROVEMENT_PROPOSALS_ROOT" => verification_root }
)
report = generator.generate(write_files: false)
check("generator reports isolated root", report["proposal_root"] == File.join(root, verification_root), errors)
check("read-only generator does not create isolated root", !Dir.exist?(verification_root), errors)

isolated_verifiers = %w[
  scripts/verify-improvement-proposals-phase14.rb
  scripts/verify-alpha-skill-generator-phase15.rb
  scripts/verify-alpha-skill-plan-generator-phase16.rb
  scripts/verify-alpha-behavior-scaffold-phase17.rb
  scripts/verify-alpha-review-phase18.rb
  scripts/verify-alpha-review-phase18-latest-repair.rb
  scripts/verify-alpha-promotion-gate-phase19.rb
]

shared_root_deletion_absent = isolated_verifiers.none? do |path|
  File.read(path).include?('FileUtils.rm_rf("Soul/improvement/proposals")')
end
isolated_env_present = isolated_verifiers.all? do |path|
  source = File.read(path)
  source.include?("SOUL_IMPROVEMENT_PROPOSALS_ROOT") && source.include?("Soul/runtime/verification/")
end

check("historical verifiers do not delete shared proposal root", shared_root_deletion_absent, errors)
check("historical verifiers use isolated runtime roots", isolated_env_present, errors)

phase29 = File.read("scripts/verify-alpha-implementation-task-pack-phase29.rb")
phase30 = File.read("scripts/verify-alpha-implementation-review-gate-phase30.rb")
check("Phase 29 fixture is isolated", phase29.include?("Soul/runtime/verification/phase29-test-proposal"), errors)
check("Phase 30 fixture is isolated", phase30.include?("Soul/runtime/verification/phase30-test-proposal"), errors)

ruby_version = File.read(".ruby-version").strip
workflow = File.read(".github/workflows/ruby-smoke.yml")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
brief = File.read("docs/soul/PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION_BRIEF.md")

check("Ruby version matches local runtime", ruby_version == RUBY_VERSION, errors)
check("CI consumes .ruby-version", workflow.include?("ruby/setup-ruby@v1") && !workflow.include?("ruby-version:"), errors)
check("roadmap says Phase 11 is in progress", roadmap.include?("Phase 11 is in progress."), errors)
check("candidate brief does not self-authorize", brief.include?("candidate_for_human_review") && brief.include?("Implementation authorized: no"), errors)
check("candidate brief prohibits overwrite", brief.include?("overwrite or edit an existing file"), errors)
check("candidate brief requires approval token", brief.include?("approval token") && brief.include?("literal `confirm`"), errors)

if errors.empty?
  puts "Verification complete."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
