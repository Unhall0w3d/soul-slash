#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 6 routing repair verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/host_system_status_collector.rb
  lib/soul_core/conversation_grounding_policy.rb
  lib/soul_core/conversation_tool_catalog.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/phase6_host_routing_repair_assessor.rb
  docs/BOUNDED_HOST_SYSTEM_STATUS.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE6_ROUTING_REPAIR.md
  CHANGELOG.md
  scripts/verify-phase6-host-routing-repair.rb
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
  "phase6-host-routing-repair",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "phase6_host_routing_repair" &&
  json["phase"] == 6 &&
  json["ok"] == true &&
  json.dig("verification", "compound_plural_storage_route_works") == true &&
  json.dig("verification", "plural_referential_followup_works") == true &&
  json.dig("verification", "focused_storage_followup_works") == true &&
  json.dig("verification", "pseudo_filesystems_are_filtered") == true &&
  json.dig("verification", "zram_is_not_presented_as_a_disk") == true &&
  json.dig("verification", "btrfs_subvolume_claims_are_grouped") == true

check("Phase 6 routing repair assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "phase6-host-routing-repair"
)
text_ok =
  status.success? &&
  stdout.include?("Soul Phase 6 Host Routing Repair Assessment") &&
  stdout.include?("Status: ready")

check("Phase 6 routing repair text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

%w[
  bounded-host-system-status
  conversational-orchestrator
  grounded-evidence-lifecycle
].each do |assessment|
  stdout, stderr, status = Open3.capture3(
    "ruby",
    "bin/soul",
    "assess",
    assessment,
    "--json"
  )
  parsed = JSON.parse(stdout) rescue nil
  ok = status.success? && parsed && parsed["ok"] == true
  check("#{assessment} regression", ok, errors)
  unless ok
    warn stderr
    warn stdout
  end
end

runtime = File.read("lib/soul_core/conversation_runtime.rb")
check(
  "runtime uses focused follow-up rendering",
  runtime.include?("@grounding_policy.render_followup"),
  errors
)
check(
  "provider errors retain type and message",
  runtime.include?('return "#{type}: #{message}" unless type.empty? || message.empty?'),
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
allowed = [
  "lib/soul_core/phase6_host_routing_repair_assessor.rb",
  "docs/maintenance/CONVERSATIONAL_SOUL_PHASE6_ROUTING_REPAIR.md",
  "scripts/verify-phase6-host-routing-repair.rb"
]
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
  puts "Conversational Soul Phase 6 routing repair is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
