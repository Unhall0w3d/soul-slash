#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []
TEST_PROPOSAL_ROOT = "Soul/runtime/verification/phase14-improvement-proposals"
TEST_ENV = { "SOUL_IMPROVEMENT_PROPOSALS_ROOT" => TEST_PROPOSAL_ROOT }.freeze

def run_cmd(*cmd)
  Open3.capture3(TEST_ENV, *cmd)
end

puts "improvement proposals phase 14 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/capability_matrix.rb",
  "lib/soul_core/improvement_proposal_generator.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires improvement proposal generator" => app.include?('require_relative "improvement_proposal_generator"'),
  "app exposes improve command" => app.include?('when "improve"'),
  "app exposes improve proposals" => app.include?('when "proposals"')
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "capabilities", "--json")
matrix = JSON.parse(stdout) rescue nil
matrix_ok =
  status.success? &&
  matrix &&
  matrix.dig("sources", "skills", "status") == "ok" &&
  matrix.dig("sources", "workflows", "status") == "ok" &&
  matrix.dig("capabilities", "youtube_playback", "status") == "available"
puts "- capability matrix source repair: #{matrix_ok ? 'ok' : 'missing'}"
errors << "capability matrix source repair failed: #{stderr} #{stdout}" unless matrix_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "proposals")
text_ok =
  status.success? &&
  stdout.include?("Soul Improvement Proposals") &&
  stdout.include?("Add model capability registry and task routing policy") &&
  !stdout.include?("Add alpha skill generation pipeline") &&
  stdout.include?("No proposal files were written")
puts "- text improvement proposals: #{text_ok ? 'ok' : 'missing'}"
errors << "text proposals failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "proposals", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "improvement_proposals" &&
  json["read_only"] == true &&
  json["write_requested"] == false &&
  json["proposal_count"].to_i >= 1 &&
  json.dig("verification", "no_code_modified") == true
puts "- JSON improvement proposals: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON proposals failed: #{stderr} #{stdout}" unless json_ok

FileUtils.rm_rf(TEST_PROPOSAL_ROOT)
stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "proposals", "--write", "--json")
written_json = JSON.parse(stdout) rescue nil
proposal_dirs = Dir.glob(File.join(TEST_PROPOSAL_ROOT, "*")).select { |path| File.directory?(path) }
write_ok =
  status.success? &&
  written_json &&
  written_json["write_requested"] == true &&
  proposal_dirs.any? &&
  proposal_dirs.all? { |dir| File.exist?(File.join(dir, "proposal.md")) && File.exist?(File.join(dir, "metadata.json")) && File.exist?(File.join(dir, "source_capability_matrix.json")) }
puts "- write improvement proposals: #{write_ok ? 'ok' : 'missing'}"
errors << "write proposals failed: #{stderr} #{stdout}" unless write_ok

FileUtils.rm_rf(TEST_PROPOSAL_ROOT)

docs_ok = File.exist?("docs/assessments/IMPROVEMENT_PROPOSALS_PHASE14.md") &&
          File.read("docs/assessments/IMPROVEMENT_PROPOSALS_PHASE14.md").include?("human approval")
puts "- phase 14 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 14 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
