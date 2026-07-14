#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 2 verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/conversation_provider_contract.rb
  lib/soul_core/conversation_provider_registry.rb
  lib/soul_core/conversation_provider_probe.rb
  lib/soul_core/conversation_provider_foundation_assessor.rb
  docs/CONVERSATION_PROVIDER_CONTRACT.md
  docs/CONVERSATION_PROVIDER_CONFIGURATION.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE2.md
  docs/MILESTONES.md
  CHANGELOG.md
  scripts/verify-conversation-provider-foundation-phase2.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversation-provider-foundation",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "conversation_provider_foundation" &&
  json["milestone"] == "conversational_soul" &&
  json["phase"] == 2 &&
  json["ok"] == true &&
  json.dig("verification", "provider_registry_complete") == true &&
  json.dig("verification", "request_envelope_validates") == true &&
  json.dig("verification", "invalid_request_rejected") == true &&
  json.dig("verification", "response_envelope_validates") == true &&
  json.dig("verification", "available_probe_works") == true &&
  json.dig("verification", "unavailable_probe_works") == true &&
  json.dig("verification", "timeout_probe_works") == true &&
  json.dig("verification", "credential_values_not_serialized") == true

check("conversation provider foundation assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "conversation-provider-foundation"
)

text_ok =
  status.success? &&
  stdout.include?("Soul Conversation Provider Foundation Assessment") &&
  stdout.include?("Phase: 2") &&
  stdout.include?("Status: ready")

check("conversation provider text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

contract = File.read("docs/CONVERSATION_PROVIDER_CONTRACT.md")
configuration = File.read("docs/CONVERSATION_PROVIDER_CONFIGURATION.md")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")

check("provider contract documents request and response envelopes", contract.include?("## Request envelope") && contract.include?("## Response envelope"), errors)
check("provider configuration documents both local transports", configuration.include?("local.openai_compatible") && configuration.include?("local.ollama"), errors)
check("roadmap marks Phase 1 complete", roadmap.include?("### Phase 1: Architecture and acceptance contract") && roadmap.include?("complete"), errors)
check("roadmap marks Phase 2 complete", roadmap.match?(/### Phase 2: Provider and model capability foundation.*?Status:\s*```text\s*complete/m), errors)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = ["scripts/verify-conversation-provider-foundation-phase2.rb"]
untracked =
  if curation && curation["untracked_review_candidates"].is_a?(Array)
    curation["untracked_review_candidates"]
  else
    []
  end

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  (untracked - allowed).empty?

check("repo curation", curation_ok, errors)

unless curation_ok
  warn stderr
  warn stdout
end

if errors.empty?
  puts "Verification complete."
  puts "Conversational Soul Phase 2 is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
