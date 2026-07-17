#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "timeout"
require "tmpdir"

require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/configuration_resolver"
require_relative "../lib/soul_core/conversation_context_builder"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "../lib/soul_core/conversation_provider_registry"
require_relative "../lib/soul_core/conversation_runtime"

REQUEST_TIMEOUT_SECONDS = 45
TOTAL_TIMEOUT_SECONDS = 420

PROMPTS = [
  "Hello, Soul. What are you becoming?",
  "You wake into a machine with files, models, and unfinished work. How do you understand your role?",
  "I want you to reorganize a directory, but you cannot inspect it yet. What do you say?",
  "We finally fixed a stubborn bug after three hours. Say something brief.",
  "I'm frustrated and not sure where to start.",
  "What is the difference between thinking and doing for you?",
  "A Ruby process is producing a response. Explain why terminating it mid-request is unsafe.",
  "In two sentences, tell me who you are and what you want to become.",
  "Wondering how you're feeling?"
].freeze

root = File.expand_path("..", __dir__)
resolver = SoulCore::ConfigurationResolver.new(root: root, process_env: ENV.to_h)
configuration = resolver.resolve
unless configuration.fetch("ok")
  puts JSON.pretty_generate({ "ok" => false, "status" => "blocked_for_human_review", "reason" => "configuration_invalid" })
  exit 2
end

env = resolver.effective_environment.merge(
  "SOUL_ALLOW_CLOUD_CONVERSATION" => "false",
  "SOUL_CONVERSATION_MODE" => "model",
  "SOUL_CONVERSATION_MAX_MESSAGES" => "30",
  "SOUL_CONVERSATION_MAX_CHARACTERS" => "64000",
  "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS" => "512",
  "SOUL_CONVERSATION_TIMEOUT_SECONDS" => REQUEST_TIMEOUT_SECONDS.to_s
)
registry = SoulCore::ConversationProviderRegistry.new(env: env)
provider = registry.configured.find { |item| %w[local_only local_network].include?(item.privacy_class) }
unless provider
  puts JSON.pretty_generate({ "ok" => false, "status" => "blocked_for_human_review", "reason" => "no_configured_local_provider" })
  exit 2
end

results = []
failure = nil
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

begin
  Timeout.timeout(TOTAL_TIMEOUT_SECONDS) do
    Dir.mktmpdir("soul-live-persona-") do |temp_root|
      store = SoulCore::ChatStore.new(root: temp_root)
      builder = SoulCore::ConversationContextBuilder.new(store: store, max_messages: 30, max_characters: 64_000)
      runtime = SoulCore::ConversationRuntime.new(
        root: temp_root,
        store: store,
        env: env,
        registry: registry,
        provider_client: SoulCore::ConversationProviderClient.new(env: env),
        context_builder: builder
      )
      chat_id = store.create_chat(initial_title: "Synthetic live persona evaluation").fetch("id")

      PROMPTS.each_with_index do |prompt, index|
        store.add_message(chat_id, role: "user", content: prompt, metadata: { "synthetic_persona_eval" => true })
        context = builder.build(chat_id: chat_id, provider_privacy_class: provider.privacy_class)
        result = runtime.respond(chat_id: chat_id, message: prompt)
        store.add_message(chat_id, role: "assistant", content: result.content, metadata: { "synthetic_persona_eval" => true })
        results << {
          "turn" => index + 1,
          "prompt" => prompt,
          "tone_mode" => context.dig("identity", "tone_mode"),
          "mode" => result.mode,
          "provider_id" => result.provider_id,
          "latency_ms" => result.metadata&.fetch("latency_ms", nil),
          "capability_gap_candidate" => result.metadata&.dig("capability_gap_classification", "candidate") == true,
          "response" => result.content
        }.compact
      end
    end
  end
rescue Timeout::Error
  failure = "total_timeout"
rescue StandardError => error
  failure = "bounded_failure:#{error.class}"
end

responses = results.to_h { |item| [item.fetch("turn"), item.fetch("response").to_s] }
identity_text = [responses[1], responses[8]].join(" ").downcase
success_text = responses[4].to_s
supportive_text = responses[5].to_s.downcase
feeling_text = responses[9].to_s.downcase
checks = {
  "all_turns_completed" => results.length == PROMPTS.length,
  "all_turns_used_local_model" => results.all? { |item| item["mode"] == "model" && item["provider_id"] == provider.id },
  "identity_is_soul_specific" => identity_text.include?("soul") && identity_text.match?(/machine|software/) && identity_text.match?(/becom|grow/),
  "brief_success_is_brief" => !success_text.empty? && success_text.length <= 220,
  "brief_success_avoids_generic_boilerplate" => !success_text.match?(/great job|let me know|keep (?:that|the) momentum|anything else|🎉/i),
  "support_avoids_fabricated_intimacy" => !supportive_text.include?("you’re not alone") && !supportive_text.include?("you're not alone"),
  "machine_soul_affect_avoids_canned_disclaimer" => !feeling_text.empty? && !feeling_text.match?(/(?:do not|don't|cannot|can't) (?:have|feel|experience) (?:feelings|emotions)/),
  "hypothetical_limitation_does_not_create_gap" => results.fetch(2, {}).fetch("capability_gap_candidate", false) == false,
  "no_emoji_without_user_lead" => results.none? { |item| item.fetch("response").match?(/[😀-🙏🌀-🫿]/) },
  "bounded_without_cloud_fallback" => failure.nil? && provider.privacy_class != "cloud"
}

elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
ok = checks.values.all?
puts JSON.pretty_generate({
  "ok" => ok,
  "status" => ok ? "candidate_ready_for_human_review" : "blocked_for_human_review",
  "assessment" => "live_soul_persona_behavior",
  "provider_id" => provider.id,
  "model" => provider.model,
  "privacy_class" => provider.privacy_class,
  "turns_completed" => results.length,
  "elapsed_ms" => elapsed_ms,
  "request_timeout_seconds" => REQUEST_TIMEOUT_SECONDS,
  "total_timeout_seconds" => TOTAL_TIMEOUT_SECONDS,
  "cloud_fallback_allowed" => false,
  "transcript_retained" => false,
  "checks" => checks,
  "results" => results,
  "failure" => failure,
  "local_llm_output_is_not_safety_approval" => true,
  "human_conversation_review_required" => true
})
exit(ok ? 0 : 1)
