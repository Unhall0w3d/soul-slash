#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []
def run_cmd(*cmd) = Open3.capture3(*cmd)

puts "Execution adapter registry phase 55 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/execution_adapter_registry.rb
  lib/soul_core/execution_adapter_registry_assessor.rb
  lib/soul_core/read_only_skill_execution_gate.rb
  lib/soul_core/read_only_skill_execution_gate_assessor.rb
  scripts/verify-execution-adapter-registry-phase55.rb
  docs/maintenance/PHASE55_EXECUTION_ADAPTER_REGISTRY.md
  docs/EXECUTION_ADAPTER_REGISTRY.md
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "execution-adapter-registry", "--json")
json = JSON.parse(stdout) rescue nil
ok = status.success? && json && json["assessment"] == "execution_adapter_registry" && json["phase"] == 55 && json["ok"] == true && json.dig("verification", "has_enabled_adapters") == true && json.dig("verification", "downloads_inspect_registered_disabled") == true
puts "- JSON execution adapter registry assessment: #{ok ? 'ok' : 'missing'}"
errors << "registry JSON failed: #{stderr} #{stdout}" unless ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "read-only-skill-gate", "--json")
gate = JSON.parse(stdout) rescue nil
ok = status.success? && gate && gate["phase"] == 55 && gate.dig("verification", "uses_adapter_registry") == true && gate.dig("verification", "disabled_adapter_blocked") == true
puts "- read-only gate uses adapter registry: #{ok ? 'ok' : 'missing'}"
errors << "gate registry integration failed: #{stderr} #{stdout}" unless ok

doc_ok = File.read("docs/EXECUTION_ADAPTER_REGISTRY.md").include?("execution adapter registry") && File.read("docs/maintenance/PHASE55_EXECUTION_ADAPTER_REGISTRY.md").include?("Phase 55")
puts "- phase 55 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 55 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-execution-adapter-registry-phase55.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
curation_ok = status.success? && curation && curation.dig("counts", "tracked_overlay_notes").to_i == 0 && (untracked - allowed).empty?
puts "- repo curation remains clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if errors.empty?
  puts "Verification complete."
else
  warn "Verification failed:"
  errors.each { |e| warn "- #{e}" }
  exit 1
end
