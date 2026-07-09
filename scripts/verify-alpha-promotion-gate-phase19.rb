
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha promotion gate phase 19 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/alpha_promotion_gate.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires promotion gate" => app.include?('require_relative "alpha_promotion_gate"'),
  "app exposes promotion-gate" => app.include?('"promotion-gate", "alpha-promotion-gate", "promotion-check"'),
  "app help includes promotion gate" => app.include?("improve promotion-gate --latest")
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

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "promotion-gate", "--proposal-rank", "1")
text_ok =
  !status.success? &&
  stdout.include?("Soul Alpha Promotion Gate") &&
  stdout.include?("Gate status: blocked") &&
  stdout.include?("Promotion allowed: false") &&
  stdout.include?("Alpha behavior is scaffold-only")
puts "- text promotion gate: #{text_ok ? 'ok' : 'missing'}"
errors << "text promotion gate failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "promotion-gate", "--latest", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  !status.success? &&
  json &&
  json["assessment"] == "alpha_promotion_gate" &&
  json["gate_status"] == "blocked" &&
  json["promotion_allowed"] == false &&
  json.dig("verification", "gate_only") == true &&
  json.dig("verification", "no_promotion_performed") == true &&
  json.fetch("blockers").any? { |item| item.include?("scaffold") } &&
  json.fetch("checklist_open_items").any?
puts "- JSON promotion gate: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON promotion gate failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "promotion-check", "--proposal-rank", "1", "--json")
alias_json = JSON.parse(stdout) rescue nil
alias_ok = !status.success? && alias_json && alias_json["assessment"] == "alpha_promotion_gate"
puts "- promotion-check alias: #{alias_ok ? 'ok' : 'missing'}"
errors << "promotion-check alias failed: #{stderr} #{stdout}" unless alias_ok

docs_ok = File.exist?("docs/assessments/ALPHA_PROMOTION_GATE_PHASE19.md") &&
          File.read("docs/assessments/ALPHA_PROMOTION_GATE_PHASE19.md").include?("Promotion is not implemented")
puts "- phase 19 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 19 docs missing" unless docs_ok

FileUtils.rm_rf("Soul/improvement/proposals")

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
