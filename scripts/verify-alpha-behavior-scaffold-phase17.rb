#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha behavior scaffold phase 17 verification:"

paths = [
  "lib/soul_core/alpha_behavior_scaffold.rb",
  "lib/soul_core/alpha_skill_generator.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

alpha_source = File.read("lib/soul_core/alpha_skill_generator.rb")
checks = {
  "alpha generator requires behavior scaffold" => alpha_source.include?('require_relative "alpha_behavior_scaffold"'),
  "alpha generator writes behavior scaffold" => alpha_source.include?('behavior_scaffold.json'),
  "alpha generator reports behavior scaffold" => alpha_source.include?('"behavior_scaffold_generated" => true')
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
alpha_report = JSON.parse(stdout) rescue nil
alpha_path = alpha_report && alpha_report["alpha_path"]
alpha_ok =
  status.success? &&
  alpha_report &&
  alpha_report["ok"] == true &&
  alpha_report["behavior_scaffold_generated"] == true &&
  alpha_path &&
  File.exist?(File.join(alpha_path, "behavior_scaffold.json"))

puts "- behavior scaffold generated: #{alpha_ok ? 'ok' : 'missing'}"
errors << "behavior scaffold generation failed: #{stderr} #{stdout}" unless alpha_ok

if alpha_ok
  behavior = JSON.parse(File.read(File.join(alpha_path, "behavior_scaffold.json"))) rescue nil
  behavior_ok =
    behavior &&
    behavior["planned_artifacts"].is_a?(Array) &&
    behavior["behavior_steps"].is_a?(Array) &&
    behavior["risks"].is_a?(Array) &&
    behavior["behavior_steps"].any? { |step| step.include?("proposal") || step.include?("alpha") }
  puts "- behavior scaffold content: #{behavior_ok ? 'ok' : 'missing'}"
  errors << "behavior scaffold content invalid" unless behavior_ok

  stdout, stderr, status = Open3.capture3("ruby", "verify-alpha.rb", chdir: alpha_path)
  alpha_verify_ok =
    status.success? &&
    stdout.include?("behavior scaffold shape: ok") &&
    stdout.include?("alpha run boundaries: ok") &&
    stdout.include?("Verification complete.")
  puts "- alpha verifier checks behavior scaffold: #{alpha_verify_ok ? 'ok' : 'missing'}"
  errors << "alpha verifier failed: #{stderr} #{stdout}" unless alpha_verify_ok
end

docs_ok = File.exist?("docs/assessments/ALPHA_BEHAVIOR_SCAFFOLD_PHASE17.md") &&
          File.read("docs/assessments/ALPHA_BEHAVIOR_SCAFFOLD_PHASE17.md").include?("behavior_scaffold.json")
puts "- phase 17 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 17 docs missing" unless docs_ok

FileUtils.rm_rf("Soul/improvement/proposals")

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
