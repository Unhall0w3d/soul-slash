
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "skill loop completion phase 31 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/skill_loop_completion_assessor.rb",
  "scripts/verify-skill-loop-completion-phase31.rb",
  "docs/maintenance/PHASE31_SKILL_LOOP_COMPLETION.md",
  "docs/SKILL_LOOP_COMPLETION.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires skill loop completion assessor" => app.include?('require_relative "skill_loop_completion_assessor"'),
  "app exposes skill-loop assessment" => app.include?('"skill-loop", "skill-loop-completion", "loop-completion"'),
  "app help includes skill-loop" => app.include?("assess skill-loop")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "skill-loop", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "skill_loop_completion" &&
  json["ok"] == true &&
  json["status"] == "controlled_skill_loop_complete" &&
  json.dig("stop_point", "complete") == true &&
  json.dig("verification", "no_codex_invoked") == true &&
  json.dig("verification", "no_promotion_performed") == true &&
  json.fetch("loop_stages").any? { |stage| stage["id"] == "implementation_review_gate" } &&
  json.fetch("loop_stages").any? { |stage| stage["id"] == "codex_dry_run_review" } &&
  json.fetch("missing_source_files").empty? &&
  json.fetch("missing_docs").empty? &&
  json.fetch("missing_routes").empty?

puts "- JSON skill-loop assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON skill-loop assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "skill-loop")
text_ok =
  status.success? &&
  stdout.include?("Soul Skill Loop Completion Assessment") &&
  stdout.include?("Status: controlled_skill_loop_complete") &&
  stdout.include?("Stop point: Controlled Advisory Skill Loop")

puts "- text skill-loop assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text skill-loop assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "loop-completion", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "skill_loop_completion" &&
  alias_json["status"] == "controlled_skill_loop_complete"

puts "- loop-completion alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "loop-completion alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/SKILL_LOOP_COMPLETION.md").include?("Controlled Advisory Skill Loop") &&
  File.read("docs/maintenance/PHASE31_SKILL_LOOP_COMPLETION.md").include?("clean stop point")
puts "- phase 31 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 31 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-skill-loop-completion-phase31.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
unexpected_untracked = untracked - allowed_untracked

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  curation.dig("counts", "untracked_generated_local").to_i == 0 &&
  unexpected_untracked.empty?

puts "- repo curation remains clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation has unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if (untracked & allowed_untracked).any?
  puts "- current phase verifier pending commit: ok"
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
