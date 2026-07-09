
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "repo curation phase 21 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/repo_curation_assessor.rb",
  "scripts/verify-repo-curation-phase21.rb",
  "docs/maintenance/PHASE21_REPO_CURATION.md",
  "docs/REPOSITORY_MAP.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid or missing" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires repo curation assessor" => app.include?('require_relative "repo_curation_assessor"'),
  "app exposes repo-curation assessment" => app.include?('"repo-curation", "repository-curation", "curation"'),
  "app help includes repo curation" => app.include?("assess repo-curation")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "repo_curation" &&
  json.dig("verification", "read_only") == true &&
  json.dig("verification", "no_git_changes_performed") == true &&
  json["counts"].is_a?(Hash) &&
  json["proposed_actions"].is_a?(Array)

puts "- JSON repo curation assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON curation failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation")
text_ok =
  status.success? &&
  stdout.include?("Soul Repo Curation Assessment") &&
  stdout.include?("Tracked overlay notes") &&
  stdout.include?("Proposed actions")
puts "- text repo curation assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text curation failed: #{stderr} #{stdout}" unless text_ok

doc_ok =
  File.read("docs/maintenance/PHASE21_REPO_CURATION.md").include?("read-only") &&
  File.read("docs/REPOSITORY_MAP.md").include?("Local/generated areas")
puts "- phase 21 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 21 docs missing expected content" unless doc_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
