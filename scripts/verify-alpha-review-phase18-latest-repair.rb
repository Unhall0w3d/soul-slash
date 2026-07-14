
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []
TEST_PROPOSAL_ROOT = "Soul/runtime/verification/phase18-latest-repair"
TEST_ENV = { "SOUL_IMPROVEMENT_PROPOSALS_ROOT" => TEST_PROPOSAL_ROOT }.freeze

def run_cmd(*cmd)
  Open3.capture3(TEST_ENV, *cmd)
end

puts "alpha review phase 18 latest repair verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/proposal_locator.rb",
  "lib/soul_core/alpha_review.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
locator = File.read("lib/soul_core/proposal_locator.rb")

checks = {
  "app resolves alpha review separately" => app.include?("resolve_alpha_review_proposal_path"),
  "alpha review uses latest_with_alpha" => app.include?("locator.latest_with_alpha"),
  "proposal locator supports latest_with_alpha" => locator.include?("def latest_with_alpha")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf(TEST_PROPOSAL_ROOT)

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "proposals", "--write", "--json")
proposal_report = JSON.parse(stdout) rescue nil
proposal_ok = status.success? && proposal_report && proposal_report["proposal_count"].to_i >= 4
puts "- source proposals generated: #{proposal_ok ? 'ok' : 'missing'}"
errors << "source proposals failed: #{stderr} #{stdout}" unless proposal_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha", "--proposal-rank", "1", "--json")
alpha_report = JSON.parse(stdout) rescue nil
alpha_ok = status.success? && alpha_report && alpha_report["ok"] == true
puts "- rank 1 alpha generated: #{alpha_ok ? 'ok' : 'missing'}"
errors << "rank 1 alpha failed: #{stderr} #{stdout}" unless alpha_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha-review", "--latest", "--json")
review = JSON.parse(stdout) rescue nil
latest_review_ok =
  status.success? &&
  review &&
  review["ok"] == true &&
  review["readiness"] == "review_ready" &&
  review["proposal_path"].include?("-1-add-alpha-skill-generation-pipeline") &&
  review.dig("promotion", "allowed") == false

puts "- latest alpha review selects alpha-ready proposal: #{latest_review_ok ? 'ok' : 'missing'}"
errors << "latest alpha review failed: #{stderr} #{stdout}" unless latest_review_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha", "--latest", "--json")
latest_alpha = JSON.parse(stdout) rescue nil
latest_alpha_ok =
  status.success? &&
  latest_alpha &&
  latest_alpha["ok"] == true &&
  latest_alpha["proposal_path"].include?("-4-add-local-speech-to-text-capability-assessment")

puts "- alpha --latest still selects newest proposal: #{latest_alpha_ok ? 'ok' : 'missing'}"
errors << "alpha --latest changed unexpectedly: #{stderr} #{stdout}" unless latest_alpha_ok

docs_ok = File.exist?("docs/assessments/ALPHA_REVIEW_PHASE18_LATEST_REPAIR.md") &&
          File.read("docs/assessments/ALPHA_REVIEW_PHASE18_LATEST_REPAIR.md").include?("latest alpha-ready")
puts "- repair docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "repair docs missing" unless docs_ok

FileUtils.rm_rf(TEST_PROPOSAL_ROOT)

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
