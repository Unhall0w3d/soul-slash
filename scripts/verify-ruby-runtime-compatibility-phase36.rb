
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Ruby runtime compatibility phase 36 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/ruby_runtime_compatibility_assessor.rb",
  "scripts/verify-ruby-runtime-compatibility-phase36.rb",
  "docs/maintenance/PHASE36_RUBY_RUNTIME_COMPATIBILITY.md",
  "docs/RUBY_RUNTIME_COMPATIBILITY.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
app_checks = {
  "app requires Ruby runtime assessor" => app.include?('require_relative "ruby_runtime_compatibility_assessor"'),
  "app exposes ruby-runtime assessment" => app.include?('"ruby-runtime", "runtime-compatibility", "ruby-compatibility"'),
  "app help includes ruby-runtime" => app.include?("ruby bin/soul assess ruby-runtime")
}

app_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "ruby-runtime", "--json")
json = JSON.parse(stdout) rescue nil

json_ok =
  status.success? &&
  json &&
  json["assessment"] == "ruby_runtime_compatibility" &&
  json["ok"] == true &&
  json["status"] == "compatible" &&
  json.dig("runtime", "ruby_version").to_s.length.positive? &&
  json.dig("expected_runtime_strategy", "project_scoped_ruby") == true &&
  json.dig("expected_runtime_strategy", "system_ruby_mutation") == false &&
  json.dig("verification", "no_files_modified") == true &&
  json.dig("verification", "no_gems_installed") == true &&
  json.dig("verification", "no_system_ruby_changes") == true

puts "- JSON ruby-runtime assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON ruby-runtime assessment failed: #{stderr} #{stdout}" unless json_ok

if json
  ruby_version = json.dig("runtime", "ruby_version")
  ruby_file = json.dig("runtime", "ruby_version_file")
  version_status = json["version_status"]
  puts "- active Ruby version: #{ruby_version}"
  puts "- .ruby-version: #{ruby_file || 'not set'}"
  puts "- version status: #{version_status}"
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "ruby-runtime")
text_ok =
  status.success? &&
  stdout.include?("Soul Ruby Runtime Compatibility Assessment") &&
  stdout.include?("Status: compatible") &&
  stdout.include?("Core CLI smoke checks")

puts "- text ruby-runtime assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text ruby-runtime assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "ruby-compatibility", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok =
  status.success? &&
  alias_json &&
  alias_json["assessment"] == "ruby_runtime_compatibility" &&
  alias_json["status"] == "compatible"

puts "- ruby-compatibility alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "ruby-compatibility alias failed: #{stderr} #{stdout}" unless alias_ok

doc_ok =
  File.read("docs/RUBY_RUNTIME_COMPATIBILITY.md").include?("project-scoped Ruby") &&
  File.read("docs/maintenance/PHASE36_RUBY_RUNTIME_COMPATIBILITY.md").include?("Phase 36")
puts "- phase 36 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 36 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-ruby-runtime-compatibility-phase36.rb"]
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
