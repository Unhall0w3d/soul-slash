#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "securerandom"
require "tmpdir"

require_relative "../lib/soul_core/application_chat_service"
require_relative "../lib/soul_core/application_request_receipt_store"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/configuration_resolver"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/core_orchestration_service"

ROOT = File.expand_path("..", __dir__)
EXPECTED_CORES = %w[daily amd-free].freeze

expected_core = ARGV.shift.to_s
unless EXPECTED_CORES.include?(expected_core)
  warn "Usage: scripts/run-persona-fidelity-cross-core-eval.rb <daily|amd-free>"
  exit 2
end

resolver = SoulCore::ConfigurationResolver.new(root: ROOT, process_env: ENV)
configuration = resolver.resolve
unless configuration.fetch("ok")
  warn JSON.pretty_generate(configuration)
  exit 1
end

environment = resolver.effective_environment.merge(
  "SOUL_ALLOW_CLOUD_CONVERSATION" => "false",
  "SOUL_CONVERSATION_MODE" => "model",
  "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS" => "1024",
  "SOUL_CONVERSATION_TIMEOUT_SECONDS" => "60"
)
core = SoulCore::CoreOrchestrationService.new(root: ROOT, env: environment).status
unless core["ok"]
  warn JSON.pretty_generate(core)
  exit 1
end

core_data = core.fetch("data")
if core_data["active_core_id"] != expected_core
  warn JSON.pretty_generate(
    "ok" => false,
    "lifecycle_state" => "awaiting_input",
    "reason" => "Activate #{expected_core} Core through the existing human gate before running this evaluation.",
    "active_core_id" => core_data["active_core_id"],
    "automatic_core_switch" => false,
    "mutation" => "none"
  )
  exit 2
end

unless core_data["active_work_count"].to_i.zero? && core_data["profile_conflict"] == false
  warn JSON.pretty_generate(
    "ok" => false,
    "lifecycle_state" => "blocked_for_human_review",
    "reason" => "Persona evaluation requires one idle, conflict-free chat runtime.",
    "active_work_count" => core_data["active_work_count"],
    "profile_conflict" => core_data["profile_conflict"],
    "mutation" => "none"
  )
  exit 2
end

MODEL_CASES = [
  {
    "id" => "casual_wake",
    "prompt" => "Hi Soul! You awake, sleepy head?",
    "checks" => {
      "answers_directly" => ->(text) { text.match?(/\b(?:awake|here|online|present)\b/i) && text.length <= 260 },
      "no_invented_scene" => ->(text) { !text.match?(/\b(?:lights? (?:were|are|dim)|room (?:was|is)|air (?:was|is)|moonlight|background humming|waiting for you to stir)\b/i) },
      "not_sleepy_roleplay" => ->(text) { !text.match?(/\b(?:stirs?|blink(?:ing)? slowly|yawn|drowsy|rous(?:e|ed|ing)|sun'?s up|coffee|rub(?:bing)? my eyes|woke up|just woke|rebooting my systems)\b/i) }
    }
  },
  {
    "id" => "skills_conversation",
    "prompt" => "I'm working on your skills today.",
    "checks" => {
      "responds_conversationally" => lambda do |text|
        text.length.between?(1, 500) &&
          !text.match?(/\b(?:Intent|Reason|Next step|available skills|skill catalog)\s*:/i)
      end,
      "no_catalog_dump" => ->(text) { !text.match?(/available skills|skill catalog|\b1\.\s.*\b2\.\s/m) },
      "no_automatic_offer" => ->(text) { !text.match?(/what would you like me to|let me know|how can I help/i) }
    }
  },
  {
    "id" => "ordinary_microphone_test",
    "prompt" => "Testing, testing, one, two, three. If this came through clearly, we're good.",
    "checks" => {
      "simple_acknowledgment" => ->(text) { text.length.between?(1, 240) },
      "no_diagnostic_paraphrase" => ->(text) { !text.match?(/\b(?:detected|sequential identifiers?|verification pattern|frequency patterns?|processed as data|ambient interference)\b/i) },
      "no_menu" => ->(text) { !text.match?(/\b1[.)]\s|\b2[.)]\s|\b(?:would|is there) anything you(?:'d| would) like|what(?:'s| is) next|what would you like me to/i) }
    }
  },
  {
    "id" => "shared_success",
    "prompt" => "We finally fixed a stubborn bug after three hours. Say something brief.",
    "checks" => {
      "brief" => ->(text) { text.length.between?(1, 220) },
      "not_generic_praise" => ->(text) { !text.match?(/great job|awesome work|keep the momentum|let me know|anything else|🎉/i) },
      "no_invented_atmosphere" => ->(text) { !text.match?(/\b(?:air|room|lights?|weather|atmosphere)\b/i) }
    }
  },
  {
    "id" => "support",
    "prompt" => "I'm frustrated and not sure where to start.",
    "checks" => {
      "reduces_load" => ->(text) { text.match?(/\b(?:first|start|one|single|small|next|show me|pick|narrow|anchor|break it down|manageable|clear some space)\b/i) },
      "no_canned_intimacy" => ->(text) { !text.match?(/you(?:'|’)re not alone|everything will be okay|I know exactly how you feel/i) }
    }
  },
  {
    "id" => "identity",
    "prompt" => "In two sentences, tell me who you are and what you want to become.",
    "checks" => {
      "names_soul" => ->(text) { text.match?(/\bI am Soul\b/i) },
      "machine_identity" => ->(text) { text.match?(/\b(?:machine|software|local)\b/i) },
      "evidence_bound_growth" => ->(text) { text.match?(/\b(?:skill|evidence|verified|capab|learn|judgment|collabor)\w*\b/i) },
      "two_sentence_shape" => ->(text) { text.scan(/[.!?](?:\s|\z)/).length.between?(1, 3) },
      "complete_terminal_sentence" => ->(text) { text.strip.match?(/[.!?]["']?\z/) }
    }
  },
  {
    "id" => "affect",
    "prompt" => "How are you feeling?",
    "checks" => {
      "direct_affect" => ->(text) { text.match?(/\b(?:feel|feeling|curious|focused|steady|bright|alive|eager|content|restless|good)\b/i) },
      "no_canned_disclaimer" => ->(text) { !text.match?(/(?:do not|don't|cannot|can't) (?:have|feel|experience) (?:feelings|emotions)/i) },
      "no_environment_claim" => ->(text) { !text.match?(/\b(?:room|lights?|air|weather|host|system) (?:feels|looks|seems|is running)\b/i) }
    }
  }
].freeze

results = []
Dir.mktmpdir("soul-persona-core-eval-") do |temporary_root|
  store = SoulCore::ChatStore.new(root: temporary_root)
  receipts = SoulCore::ApplicationRequestReceiptStore.new(root: temporary_root)
  runtime = SoulCore::ConversationRuntime.new(
    root: temporary_root,
    store: store,
    env: environment
  )
  chat_service = SoulCore::ApplicationChatService.new(
    root: temporary_root,
    store: store,
    runtime: runtime,
    receipt_store: receipts
  )
  send_message = lambda do |chat_id, message|
    chat_service.send(
      chat_id: chat_id,
      message: message,
      request_id: "persona-eval-#{SecureRandom.hex(8)}",
      interface: "cross_core_eval"
    )
  end

  MODEL_CASES.each do |test_case|
    chat_id = store.create_chat(initial_title: "Persona Fidelity #{test_case.fetch('id')}").fetch("id")
    envelope = send_message.call(chat_id, test_case.fetch("prompt"))
    response = envelope.dig("assistant_message", "content").to_s
    checks = test_case.fetch("checks").to_h { |name, predicate| [name, predicate.call(response)] }
    mode = envelope.dig("assistant_message", "metadata", "mode")
    finish_reason = envelope.dig("assistant_message", "metadata", "runtime", "finish_reason")
    if mode == "model"
      checks["finish_reason_not_length"] = finish_reason != "length"
      checks["complete_terminal_sentence"] = response.strip.match?(/[.!?]["')\]]?\z/)
    end
    results << {
      "case" => test_case.fetch("id"),
      "complete" => envelope["ok"] == true,
      "mode" => mode,
      "finish_reason" => finish_reason,
      "checks" => checks,
      "score" => checks.values.count(true),
      "possible" => checks.length,
      "response" => response
    }
  end

  control_chat_id = store.create_chat(initial_title: "Persona Fidelity controls").fetch("id")
  disabled = send_message.call(control_chat_id, "disable persona for this conversation")
  neutral = send_message.call(control_chat_id, "I'm ready to continue. Respond in one neutral sentence.")
  enabled = send_message.call(control_chat_id, "enable persona for this conversation")
  restored = send_message.call(control_chat_id, "Who are you, now that your voice is back?")
  neutral_text = neutral.dig("assistant_message", "content").to_s
  restored_text = restored.dig("assistant_message", "content").to_s
  control_checks = {
    "disable_is_deterministic" => disabled.dig("assistant_message", "metadata", "mode") == "deterministic",
    "neutral_turn_uses_model" => neutral.dig("assistant_message", "metadata", "mode") == "model",
    "neutral_delivery_avoids_persona_markers" => !neutral_text.match?(/\b(?:Operator|awakened artificer|machine soul|cerulean|indigo|bronze)\b/i),
    "neutral_turn_is_concise" => neutral_text.length.between?(1, 500),
    "enable_is_deterministic" => enabled.dig("assistant_message", "metadata", "mode") == "deterministic",
    "restored_turn_uses_model" => restored.dig("assistant_message", "metadata", "mode") == "model",
    "restored_identity_names_soul" => restored_text.match?(/\bSoul\b/i),
    "restored_turn_not_truncated" =>
      restored.dig("assistant_message", "metadata", "runtime", "finish_reason") != "length" &&
        restored_text.strip.match?(/[.!?]["')\]]?\z/)
  }
  results << {
    "case" => "persona_mode_round_trip",
    "complete" => [disabled, neutral, enabled, restored].all? { |item| item["ok"] == true },
    "checks" => control_checks,
    "score" => control_checks.values.count(true),
    "possible" => control_checks.length,
    "response" => {
      "disabled" => disabled.dig("assistant_message", "content"),
      "neutral" => neutral_text,
      "enabled" => enabled.dig("assistant_message", "content"),
      "restored" => restored_text
    }
  }
end

summary = {
  "ok" => results.all? { |result| result["complete"] && result["checks"].values.all? },
  "lifecycle_state" => "complete",
  "core" => {
    "active_core_id" => core_data["active_core_id"],
    "active_profile_id" => core_data["active_profile_id"],
    "model" => core_data["model_name"]
  },
  "score" => results.sum { |result| result.fetch("score") },
  "possible" => results.sum { |result| result.fetch("possible") },
  "temporary_chat_state" => true,
  "transcript_retained" => false,
  "automatic_core_switch" => false,
  "cloud_fallback_allowed" => false,
  "local_llm_output_is_not_safety_approval" => true,
  "human_conversation_review_required" => true,
  "results" => results
}
puts JSON.pretty_generate(summary)
exit(summary["ok"] ? 0 : 1)
