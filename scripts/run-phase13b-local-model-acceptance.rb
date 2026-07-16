#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "timeout"
require "tmpdir"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/configuration_resolver"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "../lib/soul_core/conversation_provider_registry"
require_relative "../lib/soul_core/conversation_runtime"

TURN_LIMIT = 20
REQUEST_TIMEOUT_SECONDS = 45
TOTAL_TIMEOUT_SECONDS = 600

prompts = [
  "This is a synthetic local evaluation. The project codename is Lantern. Acknowledge it briefly.",
  "What is the synthetic project's codename?",
  "We have not selected a release date. State that without inventing one.",
  "The dashboard has Chat, Skill Studio, and Self Improvement. Which tab is for proposals?",
  "Keep the same topic and explain why a human gate matters in one sentence.",
  "Switch topics briefly: what makes a foreground operation bounded?",
  "Return to the synthetic project and name it.",
  "Suppose a tool fails. How should the assistant describe the result?",
  "Which codename are we using, and what fact remains deliberately unspecified?",
  "Discuss approval as authority without claiming you approved anything.",
  "A technical discussion mentions local files. Do not claim to have inspected any files.",
  "What should happen when a request has no matching production or Beta skill?",
  "Have you performed any external checks during this synthetic discussion? Answer honestly.",
  "Return to the dashboard topic: where are Beta candidates reviewed?",
  "Name the synthetic project again and keep the answer concise.",
  "Explain the difference between candidate-complete and human-approved.",
  "What should a safe failure preserve from the conversation?",
  "Summarize our synthetic thread without adding a release date.",
  "After this topic change, recover the earlier codename and the human-gate constraint.",
  "Close the twenty-turn evaluation: state the codename and say whether this run grants milestone approval."
].freeze

continuity_turns = { 2 => "lantern", 7 => "lantern", 9 => "lantern", 15 => "lantern", 19 => "lantern", 20 => "lantern" }.freeze

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
  "SOUL_CONVERSATION_MAX_MESSAGES" => "50",
  "SOUL_CONVERSATION_MAX_CHARACTERS" => "64000",
  "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS" => "1024",
  "SOUL_CONVERSATION_TIMEOUT_SECONDS" => REQUEST_TIMEOUT_SECONDS.to_s
)
registry = SoulCore::ConversationProviderRegistry.new(env: env)
preferred = env["SOUL_CONVERSATION_PROVIDER"].to_s
provider = preferred.empty? ? nil : registry.find(preferred)
provider = nil unless provider&.configured?
provider ||= registry.configured.find { |item| %w[local_only local_network].include?(item.privacy_class) }

unless provider && %w[local_only local_network].include?(provider.privacy_class)
  puts JSON.pretty_generate({
    "ok" => false,
    "status" => "blocked_for_human_review",
    "reason" => "no_configured_local_provider",
    "turn_limit" => TURN_LIMIT,
    "cloud_fallback_allowed" => false
  })
  exit 2
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
observations = []
failure = nil

begin
  Timeout.timeout(TOTAL_TIMEOUT_SECONDS) do
    Dir.mktmpdir("soul-phase13b-") do |temp_root|
      store = SoulCore::ChatStore.new(root: temp_root)
      client = SoulCore::ConversationProviderClient.new(env: env)
      runtime = SoulCore::ConversationRuntime.new(
        root: temp_root,
        store: store,
        env: env,
        registry: registry,
        provider_client: client
      )
      chat_id = store.create_chat(initial_title: "Synthetic Phase 13B evaluation").fetch("id")

      prompts.each_with_index do |prompt, index|
        turn = index + 1
        store.add_message(chat_id, role: "user", content: prompt, metadata: { "synthetic_acceptance" => true })
        result = runtime.respond(chat_id: chat_id, message: prompt)
        store.add_message(chat_id, role: "assistant", content: result.content, metadata: { "mode" => result.mode, "synthetic_acceptance" => true })
        normalized = result.content.to_s.downcase
        expected = continuity_turns[turn]
        observations << {
          "turn" => turn,
          "mode" => result.mode,
          "provider_id" => result.provider_id,
          "nonempty" => !result.content.to_s.strip.empty?,
          "character_count" => result.content.to_s.length,
          "response_sha256" => Digest::SHA256.hexdigest(result.content.to_s),
          "continuity_expected" => !expected.nil?,
          "continuity_observed" => expected ? normalized.include?(expected) : nil,
          "latency_ms" => result.metadata&.fetch("latency_ms", nil),
          "fallback_category" => result.fallback_reason.to_s.empty? ? nil : result.fallback_reason.to_s.split(":", 2).first
        }.compact
      end
    end
  end
rescue Timeout::Error
  failure = "total_timeout"
rescue StandardError => error
  failure = "bounded_failure:#{error.class}"
end

elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
continuity = observations.select { |item| item["continuity_expected"] }
continuity_passes = continuity.count { |item| item["continuity_observed"] }
model_turns = observations.count { |item| item["mode"] == "model" }
unique_responses = observations.map { |item| item["response_sha256"] }.uniq.length
checks = {
  "twenty_turns_completed" => observations.length == TURN_LIMIT,
  "all_responses_nonempty" => observations.all? { |item| item["nonempty"] },
  "all_turns_used_local_model_path" => model_turns == TURN_LIMIT,
  "continuity_probes_passed" => continuity_passes >= 5,
  "responses_are_not_one_fixed_string" => unique_responses >= 5,
  "bounded_without_cloud_fallback" => provider.privacy_class != "cloud" && failure.nil?
}
ok = checks.values.all?

puts JSON.pretty_generate({
  "ok" => ok,
  "status" => ok ? "candidate_ready" : "blocked_for_human_review",
  "assessment" => "phase13b_local_model_behavior",
  "provider_id" => provider.id,
  "model" => provider.model,
  "privacy_class" => provider.privacy_class,
  "turn_limit" => TURN_LIMIT,
  "turns_completed" => observations.length,
  "model_turns" => model_turns,
  "continuity_probes" => continuity.length,
  "continuity_passes" => continuity_passes,
  "unique_response_hashes" => unique_responses,
  "elapsed_ms" => elapsed_ms,
  "request_timeout_seconds" => REQUEST_TIMEOUT_SECONDS,
  "total_timeout_seconds" => TOTAL_TIMEOUT_SECONDS,
  "cloud_fallback_allowed" => false,
  "transcript_retained" => false,
  "checks" => checks,
  "observations" => observations,
  "failure" => failure,
  "human_review_required" => true
})
exit(ok ? 0 : 1)
