#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Usability milestone closeout phase 63 verification:"

paths = %w[
  lib/soul_core/app.rb
  lib/soul_core/usability_milestone_closeout_assessor.rb
  scripts/verify-usability-milestone-phase63.rb
  docs/maintenance/PHASE63_USABILITY_MILESTONE_CLOSEOUT.md
  docs/USABILITY_MILESTONE_CLOSEOUT.md
  docs/USABILITY_MANUAL_ACCEPTANCE.md
  docs/USABILITY_RETARGET_BACKLOG.md
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "usability-milestone-closeout", "--json")
json = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? &&
  json &&
  json["phase"] == 63 &&
  json["ok"] == true &&
  json["status"] == "closed" &&
  json.dig("verification", "all_required_assessments_pass") == true &&
  json.dig("verification", "all_required_files_present") == true &&
  json.dig("verification", "all_required_verifiers_present") == true &&
  json.dig("verification", "runtime_approval_path_ignored") == true &&
  json.dig("verification", "backlog_closed") == true &&
  json.dig("verification", "clear_stopping_point_reached") == true

puts "- closeout assessment: #{assessment_ok ? 'ok' : 'missing'}"
errors << "closeout assessment failed: #{stderr} #{stdout}" unless assessment_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "usability-milestone-closeout")
text_ok =
  status.success? &&
  stdout.include?("Soul Usability Milestone Closeout Assessment") &&
  stdout.include?("Status: closed")

puts "- closeout text rendering: #{text_ok ? 'ok' : 'missing'}"
errors << "closeout text rendering failed: #{stderr} #{stdout}" unless text_ok

required_commands = [
  ["ruby", "bin/soul", "chat", "clean up downloads"],
  ["ruby", "bin/soul", "chat", "pending approvals"],
  ["ruby", "bin/soul", "chat", "move approved downloads to trash"]
]

required_commands.each do |command|
  stdout, stderr, status = run_cmd(*command)
  ok = status.success?
  label = command.last
  puts "- smoke check #{label.inspect}: #{ok ? 'ok' : 'missing'}"
  errors << "smoke check failed for #{label}: #{stderr} #{stdout}" unless ok
end

backlog = File.read("docs/USABILITY_RETARGET_BACKLOG.md")
backlog_ok =
  backlog.include?("Status: closed") &&
  backlog.include?("Phase 63") &&
  backlog.include?("Safe local action: complete")

puts "- backlog formally closed: #{backlog_ok ? 'ok' : 'missing'}"
errors << "backlog is not formally closed" unless backlog_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-usability-milestone-phase63.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  (untracked - allowed).empty?

puts "- repo curation clean apart from current phase verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if errors.empty?
  puts "Verification complete."
  puts "Usability retarget backlog is closed."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
