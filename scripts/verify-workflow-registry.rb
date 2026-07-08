#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3({}, *cmd)
end

puts "workflow registry verification:"

app_path = "lib/soul_core/app.rb"
registry_path = "lib/soul_core/workflow_registry.rb"
app = File.exist?(app_path) ? File.read(app_path) : ""
registry = File.exist?(registry_path) ? File.read(registry_path) : ""

checks = {
  "app syntax valid" => system("ruby", "-c", app_path, out: File::NULL, err: File::NULL),
  "registry syntax valid" => system("ruby", "-c", registry_path, out: File::NULL, err: File::NULL),
  "app loads workflow registry" => app.include?('require_relative "workflow_registry"'),
  "workflows command uses registry" => app.include?("WorkflowRegistry.new"),
  "registry class exists" => registry.include?("class WorkflowRegistry"),
  "downloads cleanup registered" => registry.include?('intent: "downloads.cleanup"'),
  "weather registered" => registry.include?('intent: "weather.report"'),
  "youtube play registered" => registry.include?('intent: "youtube.play"')
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflows")
human_ok =
  status.success? &&
  stdout.include?("Registered workflows:") &&
  stdout.include?("downloads.cleanup") &&
  stdout.include?("weather.report") &&
  stdout.include?("youtube.play") &&
  stdout.include?("confirmation required")
puts "- workflows human output: #{human_ok ? 'ok' : 'missing'}"
errors << "workflows human output failed: #{stderr} #{stdout}" unless human_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflows", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["workflow_count"].to_i >= 4 &&
  json.fetch("workflows", []).any? { |workflow| workflow["intent"] == "youtube.play" } &&
  json.dig("verification", "read_only") == true
puts "- workflows JSON output: #{json_ok ? 'ok' : 'missing'}"
errors << "workflows JSON output failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflow", "list")
sessions_ok = status.success? || stdout.include?("No workflow sessions found.") || stderr.empty?
puts "- workflow session commands still callable: #{sessions_ok ? 'ok' : 'missing'}"
errors << "workflow list command failed after registry patch: #{stderr} #{stdout}" unless sessions_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
