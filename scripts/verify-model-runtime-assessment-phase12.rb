#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "model runtime assessment phase 12 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/model_runtime_assessor.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
checks = {
  "app requires model runtime assessor" => app.include?('require_relative "model_runtime_assessor"'),
  "app exposes assess models" => app.include?('when "models", "model-runtime"'),
  "app supports process flag" => app.include?("--processes")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "models")
text_ok =
  status.success? &&
  stdout.include?("Soul Model Runtime Assessment") &&
  stdout.include?("Endpoints") &&
  stdout.include?("Capability Gaps") &&
  stdout.include?("Recommendations")
puts "- text model assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text assessment failed: #{stderr} #{stdout}" unless text_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "models", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "model_runtime" &&
  json["read_only"] == true &&
  json.dig("verification", "no_models_downloaded") == true &&
  json.dig("endpoints", "llama_cpp_openai").is_a?(Hash) &&
  json.dig("gpu", "nvidia_smi").is_a?(Hash) &&
  json["capability_gaps"].is_a?(Array)
puts "- JSON model assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "models", "--processes", "--json")
json = JSON.parse(stdout) rescue nil
process_ok =
  status.success? &&
  json &&
  json["process_checks_requested"] == true &&
  json["processes"].is_a?(Hash)
puts "- process-aware assessment: #{process_ok ? 'ok' : 'missing'}"
errors << "process assessment failed: #{stderr} #{stdout}" unless process_ok

docs_ok = File.exist?("docs/assessments/MODEL_RUNTIME_ASSESSMENT_PHASE12.md") &&
          File.read("docs/assessments/MODEL_RUNTIME_ASSESSMENT_PHASE12.md").include?("read-only")
puts "- phase 12 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 12 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
