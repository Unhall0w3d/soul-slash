#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

failures = []
check = lambda do |name, passed|
  puts "#{passed ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless passed
end

puts "Conversational Soul Phase 13A integrated acceptance verification:"

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "conversational-soul-acceptance", "--json")
report = JSON.parse(stdout) rescue nil
check.call("assessment command exits successfully", status.success?)
check.call("assessment reports candidate-ready Phase 13A", report && report["ok"] == true && report["phase"] == "13A" && report["lifecycle_state"] == "complete")
check.call("all ten acceptance scenarios pass", report && report["scenario_count"] == 10 && report.fetch("scenarios", {}).length == 10 && report.fetch("scenarios", {}).values.all?(true))
check.call("twenty exchanges cross the shared application path", report && report.dig("details", "turn_count") == 20 && report.dig("details", "stored_message_count") == 40)
check.call("assessment uses no external provider", report && report.dig("details", "external_provider_used") == false)
check.call("human review remains required", report && report["human_review_required"] == true)
warn stderr unless status.success?

source = File.read("lib/soul_core/conversational_soul_acceptance_assessor.rb")
check.call("temporary root bounds deterministic state", source.include?('Dir.mktmpdir("soul-phase13a-")'))
check.call("skill mutation requires both wrong and exact confirmations", source.include?("wrong_gate1") && source.include?("wrong_production") && source.include?("PROMOTE_BETA_SKILL"))
check.call("bounded turn limit is explicit", source.include?("TURN_LIMIT = 20"))
check.call("assessor adds no background primitive", %w[setInterval setTimeout Thread.new fork daemon cron].none? { |needle| source.include?(needle) })

%w[
  scripts/verify-phase12b-in-process-application-api.rb
  scripts/verify-conversational-orchestrator-phase4.rb
  scripts/verify-phase12d5-gated-skill-promotion.rb
].each do |script|
  _out, regression_error, regression_status = Open3.capture3("ruby", script)
  check.call("regression #{File.basename(script)}", regression_status.success?)
  warn regression_error unless regression_status.success?
end

if failures.empty?
  puts "Phase 13A integrated acceptance verification complete."
  exit 0
end

warn "Phase 13A verification failed: #{failures.join('; ')}"
exit 1
