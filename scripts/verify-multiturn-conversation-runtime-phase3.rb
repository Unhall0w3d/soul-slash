#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 3 verification:"

required = %w[
  lib/soul_core/app.rb
  lib/soul_core/application_chat_service.rb
  lib/soul_core/chat_command.rb
  lib/soul_core/conversation_context_builder.rb
  lib/soul_core/conversation_state_store.rb
  lib/soul_core/conversation_provider_client.rb
  lib/soul_core/conversation_runtime.rb
  lib/soul_core/multiturn_conversation_runtime_assessor.rb
  docs/MULTITURN_CONVERSATION_RUNTIME.md
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/maintenance/CONVERSATIONAL_SOUL_PHASE3.md
  docs/MILESTONES.md
  CHANGELOG.md
  scripts/verify-multiturn-conversation-runtime-phase3.rb
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
  "multiturn-conversation-runtime",
  "--json"
)
json = JSON.parse(stdout) rescue nil

assessment_ok =
  status.success? &&
  json &&
  json["assessment"] == "multiturn_conversation_runtime" &&
  json["milestone"] == "conversational_soul" &&
  json["phase"] == 3 &&
  json["ok"] == true &&
  json.dig("verification", "model_backed_turn_works") == true &&
  json.dig("verification", "multiturn_context_continues") == true &&
  json.dig("verification", "deterministic_routes_preserved") == true &&
  json.dig("verification", "provider_failure_falls_back_safely") == true &&
  json.dig("verification", "context_window_is_bounded") == true &&
  json.dig("verification", "runtime_state_is_recorded") == true &&
  json.dig("verification", "runtime_state_is_gitignored") == true &&
  json.dig("verification", "no_external_provider_required") == true

check("multi-turn conversation runtime assessment", assessment_ok, errors)

unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "multiturn-conversation-runtime"
)

text_ok =
  status.success? &&
  stdout.include?("Soul Multi-turn Conversation Runtime Assessment") &&
  stdout.include?("Phase: 3") &&
  stdout.include?("Status: ready")

check("multi-turn conversation text rendering", text_ok, errors)

unless text_ok
  warn stderr
  warn stdout
end

chat_command = File.read("lib/soul_core/chat_command.rb")
application_chat_service = File.read("lib/soul_core/application_chat_service.rb")
runtime = File.read("lib/soul_core/conversation_runtime.rb")
documentation = File.read("docs/MULTITURN_CONVERSATION_RUNTIME.md")
roadmap = File.read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")

check(
  "ChatCommand uses ConversationRuntime through the shared application exchange service",
  chat_command.include?('require_relative "conversation_runtime"') &&
    chat_command.include?("@chat_service.send") &&
    application_chat_service.include?("@runtime.respond"),
  errors
)
check("runtime preserves deterministic responder", runtime.include?('require_relative "chat_responder"') && runtime.include?("deterministic_passthrough"), errors)
check("runtime defaults to local provider preference", runtime.include?('privacy_class == "local_only"'), errors)
check("cloud conversation requires explicit permission", runtime.include?("SOUL_ALLOW_CLOUD_CONVERSATION"), errors)
check("documentation declares Phase 4 boundary", documentation.include?("Full model-guided tool orchestration belongs to Phase 4"), errors)
check("roadmap marks Phase 2 complete", roadmap.include?("### Phase 2: Provider and model capability foundation") && roadmap.include?("complete"), errors)
check("roadmap marks Phase 3 complete", roadmap.match?(/### Phase 3: Multi-turn conversation runtime.*?Status:\s*```text\s*complete/m), errors)

stdout, stderr, status = Open3.capture3(
  "ruby",
  "bin/soul",
  "assess",
  "repo-curation",
  "--json"
)
curation = JSON.parse(stdout) rescue nil
allowed = [
  "scripts/verify-multiturn-conversation-runtime-phase3.rb",
  "scripts/verify-phase12b-in-process-application-api.rb"
]
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
  puts "Conversational Soul Phase 3 is ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
