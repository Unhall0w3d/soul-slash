#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 6 verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/host_system_status_collector.rb
  lib/soul_core/bounded_host_system_status_assessor.rb
  lib/soul_core/conversation_evidence_contract.rb
  lib/soul_core/conversation_tool_catalog.rb
  lib/soul_core/conversation_orchestrator.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/conversational_orchestrator_assessor.rb
  lib/soul_core/grounded_evidence_lifecycle_assessor.rb
  docs/BOUNDED_HOST_SYSTEM_STATUS.md
  docs/HOST_ENVIRONMENT_CAPABILITY_GAP.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE6.md
  docs/MILESTONES.md
  CHANGELOG.md
  scripts/verify-bounded-host-system-status-phase6.rb
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
  "bounded-host-system-status",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "bounded_host_system_status" &&
  json["milestone"] == "conversational_soul" &&
  json["phase"] == 6 &&
  json["ok"] == true &&
  json.dig("verification", "fixture_parsing_works") == true &&
  json.dig("verification", "actual_collector_shape_works") == true &&
  json.dig("verification", "structured_evidence_works") == true &&
  json.dig("verification", "read_only") == true &&
  json.dig("verification", "model_synthesis_disabled") == true &&
  json.dig("verification", "btrfs_fixture_detected") == true &&
  json.dig("verification", "twelve_percent_fixture_detected") == true &&
  json.dig("verification", "no_fake_raid_fixture") == true

check("bounded host system status assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "bounded-host-system-status"
)

text_ok =
  status.success? &&
  stdout.include?("Soul Bounded Host System Status Assessment") &&
  stdout.include?("Phase: 6") &&
  stdout.include?("Status: ready")

check("bounded host system status text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

[
  ["conversational-orchestrator", "Phase 4 orchestration regression"],
  ["grounded-evidence-lifecycle", "Phase 5 grounding regression"]
].each do |assessment, label|
  stdout, stderr, status = Open3.capture3(
    "ruby",
    "bin/soul",
    "assess",
    assessment,
    "--json"
  )
  parsed = JSON.parse(stdout) rescue nil
  ok = status.success? && parsed && parsed["ok"] == true
  check(label, ok, errors)
  unless ok
    warn stderr
    warn stdout
  end
end

collector = File.read("lib/soul_core/host_system_status_collector.rb")
catalog = File.read("lib/soul_core/conversation_tool_catalog.rb")
runtime = File.read("lib/soul_core/conversation_runtime.rb")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")

check("collector avoids shell interpolation", collector.include?("Open3.capture3(*command)"), errors)
check("collector declares read-only verification", collector.include?('"read_only" => true'), errors)
check("host skill is registered", catalog.include?('id: "host.system_status"'), errors)
check("host synthesis is disabled", catalog.include?('id: "host.system_status"') && catalog.include?("synthesis_allowed: false"), errors)
check("runtime uses structured host collector", runtime.include?("@host_status_collector.collect"), errors)
check("roadmap marks Phase 5 complete", roadmap.include?("### Phase 5: Grounded evidence lifecycle") && roadmap.include?("complete"), errors)
check("roadmap marks Phase 6 complete", roadmap.match?(/### Phase 6: Bounded host environment assessment.*?Status:\s*```text\s*complete/m), errors)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-bounded-host-system-status-phase6.rb"]
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
  puts "Conversational Soul Phase 6 is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
