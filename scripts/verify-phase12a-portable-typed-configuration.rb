#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 12A portable typed configuration verification:"

required = %w[
  .env.example
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/soul/PHASE12A_PORTABLE_TYPED_CONFIGURATION_BRIEF.md
  docs/soul/PORTABLE_TYPED_CONFIGURATION.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE12A_PORTABLE_TYPED_CONFIGURATION.md
  lib/soul_core/app.rb
  lib/soul_core/configuration_command.rb
  lib/soul_core/configuration_resolver.rb
  lib/soul_core/configuration_schema.rb
  lib/soul_core/dotenv_reader.rb
  lib/soul_core/phase12a_portable_typed_configuration_assessor.rb
  scripts/verify-phase12a-portable-typed-configuration.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3(
  "ruby", "bin/soul", "assess", "phase12a-portable-typed-configuration", "--json"
)
report = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? && report && report["ok"] == true &&
  report["assessment"] == "phase12a_portable_typed_configuration" &&
  report["phase"] == "12A" &&
  report["risk_class"] == "Class 0: Read-only local or conversational" &&
  report.fetch("verification", {}).length == 18 &&
  report.fetch("verification", {}).values.all?(true) &&
  report.fetch("lifecycle_states", []).sort == %w[awaiting_input blocked_for_human_review canceled complete failed].sort &&
  report["local_llm_eval_required"] == false && report["human_review_required"] == true
check("Phase 12A assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby", "bin/soul", "assess", "phase12a-portable-typed-configuration"
)
text_ok =
  status.success? &&
  stdout.include?("Soul Phase 12A Portable Typed Configuration Assessment") &&
  stdout.include?("Status: candidate_ready") &&
  stdout.include?("Blockers\n- None")
check("Phase 12A assessment text", text_ok, errors)
unless text_ok
  warn stderr
  warn stdout
end

schema = File.read("lib/soul_core/configuration_schema.rb")
resolver = File.read("lib/soul_core/configuration_resolver.rb")
dotenv = File.read("lib/soul_core/dotenv_reader.rb")
command = File.read("lib/soul_core/configuration_command.rb")
app = File.read("lib/soul_core/app.rb")
brief = File.read("docs/soul/PHASE12A_PORTABLE_TYPED_CONFIGURATION_BRIEF.md")
review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE12A_PORTABLE_TYPED_CONFIGURATION.md")

check("approved brief remains explicit", brief.include?("implementation_authorized: yes") && brief.include?("Outcome: approved"), errors)
check("schema cap is explicit", schema.include?("MAX_SETTINGS = 64"), errors)
check("dotenv bounds are explicit", dotenv.include?("MAX_BYTES = 64 * 1024") && dotenv.include?("MAX_LINES = 512"), errors)
check("override and error caps are explicit", resolver.include?("MAX_OVERRIDES = 32") && resolver.include?("MAX_ERRORS = 100"), errors)
check("secret redaction is explicit", resolver.include?("[REDACTED]") && command.include?("[REDACTED]"), errors)
check("Chat consumes typed compatibility environment", app.include?("resolver.effective_environment"), errors)

forbidden = %w[Thread.new TCPServer HTTPServer WEBrick cron systemctl inotify watcher polling]
source = [schema, resolver, dotenv, command].join("\n")
check("no persistent or background source primitives", forbidden.none? { |needle| source.include?(needle) }, errors)

example = File.read(".env.example")
portable_example =
  !example.match?(/(?:API_KEY|TOKEN|SECRET)=\S+/) &&
  !example.match?(/SOUL_(?:LOCAL_OPENAI_MODEL|MODEL_ALIAS|OLLAMA_MODEL)=\S+/) &&
  !example.match?(%r{/(?:home|Users)/})
check("tracked example is portable", portable_example, errors)

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

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase11d-shared-workspace-inbox.rb")
check("Phase 11A through 11D regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 12A portable typed configuration is candidate-ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
