#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "time"

errors = []

def run_cmd(*cmd)
  Open3.capture3({}, *cmd)
end

puts "workflow session usability verification:"

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
tools = File.exist?("lib/soul_core/workflow_tools.rb") ? File.read("lib/soul_core/workflow_tools.rb") : ""

checks = {
  "app loads workflow_tools" => app.include?('require_relative "workflow_tools"'),
  "workflow status command" => app.include?('when "status"'),
  "workflow list command" => app.include?('when "list"'),
  "workflow clear-complete command" => app.include?('when "clear-complete"'),
  "workflow tools class exists" => tools.include?("class WorkflowTools"),
  "clear requires token" => tools.include?("CLEAR_COMPLETE")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

FileUtils.mkdir_p("Soul/workflows/sessions")
timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
waiting_path = "Soul/workflows/sessions/#{timestamp}-verify.waiting.json"
complete_path = "Soul/workflows/sessions/#{timestamp}-verify.complete.json"

waiting_state = {
  "workflow" => "verify.waiting",
  "status" => "waiting_for_selection",
  "generated_at" => Time.now.iso8601,
  "updated_at" => Time.now.iso8601,
  "original_text" => "verify waiting workflow",
  "parameters" => {},
  "skill_runs" => [],
  "next_expected" => "selection",
  "verification" => { "complete" => false },
  "workflow_path" => waiting_path
}

complete_state = {
  "workflow" => "verify.complete",
  "status" => "complete",
  "generated_at" => Time.now.iso8601,
  "updated_at" => Time.now.iso8601,
  "original_text" => "verify complete workflow",
  "parameters" => {},
  "skill_runs" => [],
  "next_expected" => "reflection_offer",
  "verification" => { "complete" => true },
  "workflow_path" => complete_path
}

File.write(waiting_path, JSON.pretty_generate(waiting_state))
File.write(complete_path, JSON.pretty_generate(complete_state))

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflow", "status", File.basename(waiting_path))
status_ok = status.success? && stdout.include?("Workflow status:") && stdout.include?("verify.waiting") && stdout.include?("respond")
puts "- workflow status renders next action: #{status_ok ? 'ok' : 'missing'}"
errors << "workflow status failed: #{stderr} #{stdout}" unless status_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflow", "list")
list_ok = status.success? && stdout.include?("verify.waiting") && stdout.include?("verify.complete")
puts "- workflow list includes sessions: #{list_ok ? 'ok' : 'missing'}"
errors << "workflow list failed: #{stderr} #{stdout}" unless list_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflow", "clear-complete")
dry_clear_ok = !status.success? && stdout.include?("eligible for cleanup") && File.exist?(complete_path)
puts "- clear-complete dry run preserves files: #{dry_clear_ok ? 'ok' : 'missing'}"
errors << "clear-complete dry run failed: #{stderr} #{stdout}" unless dry_clear_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "workflow", "clear-complete", "--confirm", "CLEAR_COMPLETE")
confirmed_clear_ok = status.success? && stdout.include?("Cleared") && !File.exist?(complete_path) && File.exist?(waiting_path)
puts "- clear-complete confirmed deletes only complete sessions: #{confirmed_clear_ok ? 'ok' : 'missing'}"
errors << "clear-complete confirmed failed: #{stderr} #{stdout}" unless confirmed_clear_ok

File.delete(waiting_path) if File.exist?(waiting_path)
File.delete(complete_path) if File.exist?(complete_path)

docs_ok = File.exist?("docs/workflows/SESSION_USABILITY.md") && File.read("docs/workflows/SESSION_USABILITY.md").include?("clear-complete")
puts "- workflow usability docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "workflow usability docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
