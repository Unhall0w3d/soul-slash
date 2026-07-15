#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 12B in-process application API verification:"

required = %w[
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/PHASE12B_IN_PROCESS_APPLICATION_API_BRIEF.md
  docs/soul/IN_PROCESS_APPLICATION_API.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE12B_IN_PROCESS_APPLICATION_API.md
  lib/soul_core/app.rb
  lib/soul_core/application_contract.rb
  lib/soul_core/application_request_receipt_store.rb
  lib/soul_core/application_chat_service.rb
  lib/soul_core/application_facade.rb
  lib/soul_core/chat_store.rb
  lib/soul_core/chat_command.rb
  lib/soul_core/phase12b_in_process_application_api_assessor.rb
  scripts/verify-phase12b-in-process-application-api.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "phase12b-in-process-application-api", "--json")
report = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? && report && report["ok"] == true &&
  report["assessment"] == "phase12b_in_process_application_api" && report["phase"] == "12B" &&
  report["risk_class"] == "Class 2: Local state write, non-destructive" &&
  report.fetch("verification", {}).length == 20 && report.fetch("verification", {}).values.all?(true) &&
  report.fetch("lifecycle_states", []).sort == %w[awaiting_input blocked_for_human_review canceled complete failed].sort &&
  report["human_review_required"] == true
check("Phase 12B assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "phase12b-in-process-application-api")
text_ok = status.success? && stdout.include?("Soul Phase 12B In-Process Application API Assessment") && stdout.include?("Status: candidate_ready") && stdout.include?("Blockers\n- None")
check("Phase 12B assessment text", text_ok, errors)
unless text_ok
  warn stderr
  warn stdout
end

contract = File.read("lib/soul_core/application_contract.rb")
receipts = File.read("lib/soul_core/application_request_receipt_store.rb")
chat_service = File.read("lib/soul_core/application_chat_service.rb")
facade = File.read("lib/soul_core/application_facade.rb")
chat_command = File.read("lib/soul_core/chat_command.rb")
brief = File.read("docs/soul/PHASE12B_IN_PROCESS_APPLICATION_API_BRIEF.md")
review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE12B_IN_PROCESS_APPLICATION_API.md")

check("approved brief remains explicit", brief.include?("implementation_authorized: yes") && brief.include?("Outcome: approved"), errors)
check("version and input bounds are explicit", contract.include?('SCHEMA_VERSION = "soul.application.v1"') && contract.include?("MAX_REQUEST_BYTES") && contract.include?("MAX_DEPTH"), errors)
check("operation dispatch is allowlisted", contract.include?("OPERATIONS = {") && %w[public_send const_get eval(].none? { |needle| facade.include?(needle) }, errors)
check("receipt store is private append-only state", receipts.include?("File::LOCK_EX") && receipts.include?("0o600") && !receipts.include?("File::TRUNC"), errors)
check("receipt caps are explicit", receipts.include?("MAX_EVENTS = 5_000") && receipts.include?("MAX_BYTES = 2 * 1024 * 1024"), errors)
check("CLI and facade share Chat exchange service", chat_command.include?("@chat_service.send") && chat_service.include?("@runtime.respond"), errors)
check("manual status is an explicit operation", contract.include?('"system_status.refresh"') && facade.include?("status_collector.collect"), errors)
check("approval projection is non-authorizing", facade.include?('"authorization_value_exposed" => false') && %w[approval_store.revoke approval_store.mark_used].none? { |needle| facade.include?(needle) }, errors)

forbidden = %w[TCPServer HTTPServer WEBrick Rack::Handler Sinatra Thread.new systemctl inotify cron polling]
source = [contract, receipts, chat_service, facade].join("\n")
check("no transport listener or background primitive", forbidden.none? { |needle| source.include?(needle) }, errors)

review_sections = [
  "## Implementation summary",
  "## Files changed",
  "## Commands run",
  "## Deterministic test results",
  "## Local LLM eval results",
  "## Memory keys",
  "## Lifecycle states touched",
  "## Risk classification",
  "## Safety and persistence check",
  "## Known weaknesses",
  "## Human review checklist",
  "## Human review outcome"
]
check("review artifact contains required sections", review_sections.all? { |heading| review.include?(heading) }, errors)

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-multiturn-conversation-runtime-phase3.rb")
check("Phase 3 shared Chat path regression", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase12a-portable-typed-configuration.rb")
check("Phase 11A through Phase 12A regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 12B in-process application API is candidate-ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
