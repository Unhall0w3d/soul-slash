#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha skill plan generator phase 16 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/proposal_locator.rb",
  "lib/soul_core/alpha_skill_plan_generator.rb",
  "lib/soul_core/alpha_skill_generator.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires proposal locator" => app.include?('require_relative "proposal_locator"'),
  "app requires alpha skill plan generator" => app.include?('require_relative "alpha_skill_plan_generator"'),
  "app supports --latest" => app.include?("--latest"),
  "app supports --proposal-rank" => app.include?("--proposal-rank")
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
errors << "source proposal generation failed: #{stderr} #{stdout}" unless proposal_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha", "--proposal-rank", "1", "--json")
rank_report = JSON.parse(stdout) rescue nil
rank_alpha_path = rank_report && rank_report["alpha_path"]
rank_ok =
  status.success? &&
  rank_report &&
  rank_report["ok"] == true &&
  rank_report["implementation_plan_generated"] == true &&
  rank_alpha_path &&
  File.exist?(File.join(rank_alpha_path, "implementation_plan.md"))
puts "- alpha by proposal rank: #{rank_ok ? 'ok' : 'missing'}"
errors << "alpha by rank failed: #{stderr} #{stdout}" unless rank_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha", "--latest", "--json")
latest_report = JSON.parse(stdout) rescue nil
latest_alpha_path = latest_report && latest_report["alpha_path"]
latest_ok =
  status.success? &&
  latest_report &&
  latest_report["ok"] == true &&
  latest_report["implementation_plan_generated"] == true &&
  latest_alpha_path &&
  File.exist?(File.join(latest_alpha_path, "implementation_plan.md"))
puts "- alpha by latest proposal: #{latest_ok ? 'ok' : 'missing'}"
errors << "alpha by latest failed: #{stderr} #{stdout}" unless latest_ok

if latest_ok
  stdout, stderr, status = Open3.capture3("ruby", "verify-alpha.rb", chdir: latest_alpha_path)
  alpha_verify_ok = status.success? && stdout.include?("implementation plan shape: ok") && stdout.include?("Verification complete.")
  puts "- alpha verifier checks implementation plan: #{alpha_verify_ok ? 'ok' : 'missing'}"
  errors << "alpha verifier failed: #{stderr} #{stdout}" unless alpha_verify_ok
end

docs_ok = File.exist?("docs/assessments/ALPHA_SKILL_PLAN_GENERATOR_PHASE16.md") &&
          File.read("docs/assessments/ALPHA_SKILL_PLAN_GENERATOR_PHASE16.md").include?("implementation_plan.md")
puts "- phase 16 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 16 docs missing" unless docs_ok

FileUtils.rm_rf("Soul/improvement/proposals")

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
