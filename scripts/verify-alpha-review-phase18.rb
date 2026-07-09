
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha review phase 18 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/alpha_review.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires alpha review" => app.include?('require_relative "alpha_review"'),
  "app exposes alpha-review" => app.include?('"alpha-review", "review-alpha"'),
  "app supports latest review" => app.include?("improve alpha-review --latest")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf("Soul/improvement/proposals")

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "proposals", "--write", "--json")
proposal_report = JSON.parse(stdout) rescue nil
proposal_ok = status.success? && proposal_report && proposal_report["proposal_count"].to_i >= 1
puts "- source proposals generated: #{proposal_ok ? 'ok' : 'missing'}"
errors << "source proposals failed: #{stderr} #{stdout}" unless proposal_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha", "--proposal-rank", "1", "--json")
alpha_report = JSON.parse(stdout) rescue nil
alpha_ok = status.success? && alpha_report && alpha_report["ok"] == true
puts "- source alpha generated: #{alpha_ok ? 'ok' : 'missing'}"
errors << "source alpha failed: #{stderr} #{stdout}" unless alpha_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha-review", "--proposal-rank", "1")
text_ok =
  status.success? &&
  stdout.include?("Soul Alpha Review") &&
  stdout.include?("Readiness: review_ready") &&
  stdout.include?("Promotion") &&
  stdout.include?("Allowed: false")
puts "- text alpha review: #{text_ok ? 'ok' : 'missing'}"
errors << "text review failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha-review", "--latest", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "alpha_review" &&
  json["ok"] == true &&
  json["readiness"] == "review_ready" &&
  json.dig("promotion", "allowed") == false &&
  json.dig("verification", "review_only") == true &&
  json.dig("verifier", "passed") == true &&
  json.fetch("blockers").empty?
puts "- JSON alpha review: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON review failed: #{stderr} #{stdout}" unless json_ok

if alpha_report && alpha_report["alpha_path"]
  FileUtils.rm_f(File.join(alpha_report["alpha_path"], "behavior_scaffold.json"))
  stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha-review", "--proposal-rank", "1", "--json")
  blocked = JSON.parse(stdout) rescue nil
  blocked_ok =
    !status.success? &&
    blocked &&
    blocked["ok"] == false &&
    blocked["readiness"] == "blocked" &&
    blocked.fetch("blockers").any? { |item| item.include?("behavior_scaffold.json") }
  puts "- blocked alpha review: #{blocked_ok ? 'ok' : 'missing'}"
  errors << "blocked review failed: #{stderr} #{stdout}" unless blocked_ok
end

docs_ok = File.exist?("docs/assessments/ALPHA_REVIEW_PHASE18.md") &&
          File.read("docs/assessments/ALPHA_REVIEW_PHASE18.md").include?("review-only")
puts "- phase 18 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 18 docs missing" unless docs_ok

FileUtils.rm_rf("Soul/improvement/proposals")

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
