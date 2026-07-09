#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "alpha skill generator phase 15 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/alpha_skill_generator.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires alpha skill generator" => app.include?('require_relative "alpha_skill_generator"'),
  "app exposes improve alpha" => app.include?('when "alpha"'),
  "app accepts proposal option" => app.include?('option_value("--proposal")')
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.rm_rf("Soul/improvement/proposals")
stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "proposals", "--write", "--json")
proposal_report = JSON.parse(stdout) rescue nil
proposal_path = proposal_report && proposal_report.fetch("proposals", []).first && proposal_report.fetch("proposals").first["path"]

proposal_ok = status.success? && proposal_path && Dir.exist?(proposal_path)
puts "- source proposal generated: #{proposal_ok ? 'ok' : 'missing'}"
errors << "source proposal generation failed: #{stderr} #{stdout}" unless proposal_ok

if proposal_ok
  stdout, stderr, status = run_cmd("ruby", "bin/soul", "improve", "alpha", "--proposal", proposal_path, "--json")
  alpha_report = JSON.parse(stdout) rescue nil
  alpha_path = alpha_report && alpha_report["alpha_path"]

  alpha_ok =
    status.success? &&
    alpha_report &&
    alpha_report["ok"] == true &&
    alpha_report["registered"] == false &&
    alpha_report["production_modified"] == false &&
    alpha_path &&
    File.exist?(File.join(alpha_path, "README.md")) &&
    File.exist?(File.join(alpha_path, "skill.rb")) &&
    File.exist?(File.join(alpha_path, "verify-alpha.rb")) &&
    File.exist?(File.join(alpha_path, "test_cases.json")) &&
    File.exist?(File.join(alpha_path, "promotion_checklist.md")) &&
    File.exist?(File.join(alpha_path, "alpha_manifest.json"))

  puts "- alpha artifacts generated: #{alpha_ok ? 'ok' : 'missing'}"
  errors << "alpha generation failed: #{stderr} #{stdout}" unless alpha_ok

  if alpha_ok
    stdout, stderr, status = Open3.capture3("ruby", "verify-alpha.rb", chdir: alpha_path)
    verifier_ok = status.success? && stdout.include?("Verification complete.")
    puts "- alpha verifier passes: #{verifier_ok ? 'ok' : 'missing'}"
    errors << "alpha verifier failed: #{stderr} #{stdout}" unless verifier_ok

    manifest = JSON.parse(File.read(File.join(alpha_path, "alpha_manifest.json"))) rescue nil
    manifest_ok =
      manifest &&
      manifest["registered"] == false &&
      manifest["production_modified"] == false &&
      manifest["requires_human_review"] == true
    puts "- alpha manifest boundaries: #{manifest_ok ? 'ok' : 'missing'}"
    errors << "alpha manifest boundaries failed" unless manifest_ok
  end
end

docs_ok = File.exist?("docs/assessments/ALPHA_SKILL_GENERATOR_PHASE15.md") &&
          File.read("docs/assessments/ALPHA_SKILL_GENERATOR_PHASE15.md").include?("proposal-local")
puts "- phase 15 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 15 docs missing" unless docs_ok

FileUtils.rm_rf("Soul/improvement/proposals")

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
