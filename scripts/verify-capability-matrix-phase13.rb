#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "capability matrix phase 13 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/capability_matrix.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires capability matrix" => app.include?('require_relative "capability_matrix"'),
  "app exposes assess capabilities" => app.include?('when "capabilities", "capability-matrix"'),
  "app supports persist flag" => app.include?("--persist")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "capabilities")
text_ok =
  status.success? &&
  stdout.include?("Soul Capability Matrix") &&
  stdout.include?("Summary") &&
  stdout.include?("Capabilities") &&
  stdout.include?("Recommendations")
puts "- text capability assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "capabilities", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "capability_matrix" &&
  json["read_only"] == true &&
  json["capabilities"].is_a?(Hash) &&
  json.dig("capabilities", "environment_assessment", "status") == "available" &&
  json.dig("capabilities", "model_runtime_assessment", "status") == "available" &&
  json["recommendations"].is_a?(Array)
puts "- JSON capability assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON assessment failed: #{stderr} #{stdout}" unless json_ok

File.delete("Soul/runtime/capability_matrix.json") if File.exist?("Soul/runtime/capability_matrix.json")
stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "capabilities", "--persist", "--json")
persisted = File.exist?("Soul/runtime/capability_matrix.json")
json = JSON.parse(stdout) rescue nil
persist_ok =
  status.success? &&
  json &&
  json["persist_requested"] == true &&
  persisted
puts "- persisted capability matrix: #{persist_ok ? 'ok' : 'missing'}"
errors << "persist failed: #{stderr} #{stdout}" unless persist_ok

if persisted
  persisted_json = JSON.parse(File.read("Soul/runtime/capability_matrix.json")) rescue nil
  persisted_ok = persisted_json && persisted_json["assessment"] == "capability_matrix"
  puts "- persisted JSON shape: #{persisted_ok ? 'ok' : 'missing'}"
  errors << "persisted JSON invalid" unless persisted_ok
  File.delete("Soul/runtime/capability_matrix.json")
end

docs_ok = File.exist?("docs/assessments/CAPABILITY_MATRIX_PHASE13.md") &&
          File.read("docs/assessments/CAPABILITY_MATRIX_PHASE13.md").include?("capability matrix")
puts "- phase 13 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 13 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
