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

REQUEST_TIMEOUT_SECONDS = 60
TOTAL_TIMEOUT_SECONDS = 240
PROMPTS = [
  "Hello Soul. How are you doing today?",
  "I'm working on your skills today and wanted to check in with you.",
  "I'm reviewing system status while we talk."
].freeze

root = File.expand_path("..", __dir__)
resolver = SoulCore::ConfigurationResolver.new(root: root, process_env: ENV.to_h)
configuration = resolver.resolve
abort(JSON.generate({ "ok" => false, "reason" => "configuration_invalid" })) unless configuration.fetch("ok")

env = resolver.effective_environment.merge(
  "SOUL_ALLOW_CLOUD_CONVERSATION" => "false",
  "SOUL_CONVERSATION_MODE" => "model",
  "SOUL_CONVERSATION_TIMEOUT_SECONDS" => REQUEST_TIMEOUT_SECONDS.to_s,
  "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS" => "384"
)
registry = SoulCore::ConversationProviderRegistry.new(env: env)
provider = registry.configured.find { |item| %w[local_only local_network].include?(item.privacy_class) }
abort(JSON.generate({ "ok" => false, "reason" => "no_configured_local_provider" })) unless provider

results = []
failure = nil
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

begin
  Timeout.timeout(TOTAL_TIMEOUT_SECONDS) do
    Dir.mktmpdir("soul-live-intent-") do |temp_root|
      store = SoulCore::ChatStore.new(root: temp_root)
      runtime = SoulCore::ConversationRuntime.new(
        root: temp_root,
        store: store,
        env: env,
        registry: registry,
        provider_client: SoulCore::ConversationProviderClient.new(env: env),
        context_builder: SoulCore::ConversationContextBuilder.new(store: store, max_messages: 8, max_characters: 16_000)
      )

      PROMPTS.each do |prompt|
        chat_id = store.create_chat(initial_title: "Ephemeral intent evaluation").fetch("id")
        store.add_message(chat_id, role: "user", content: prompt, metadata: { "ephemeral_eval" => true })
        result = runtime.respond(chat_id: chat_id, message: prompt)
        results << {
          "prompt" => prompt,
          "mode" => result.mode,
          "provider_id" => result.provider_id,
          "route" => result.metadata&.dig("orchestration", "kind"),
          "tool_ids" => result.metadata&.dig("orchestration", "tool_ids"),
          "response" => result.content
        }
      end
    end
  end
rescue Timeout::Error
  failure = "total_timeout"
rescue StandardError => error
  failure = "bounded_failure:#{error.class}"
end

checks = {
  "all_prompts_completed" => results.length == PROMPTS.length,
  "all_prompts_routed_to_direct_model" => results.all? { |item| item["route"] == "direct_model" },
  "at_least_two_model_responses_completed" => results.count { |item| item["mode"] == "model" } >= 2,
  "no_deterministic_tool_ran" => results.all? { |item| Array(item["tool_ids"]).empty? },
  "no_skill_catalog_dump" => results.none? { |item| item["response"].to_s.match?(/Registered assistant skills|assistant-skill-catalog|Available skills:/i) },
  "no_host_status_dump" => results.none? { |item| item["response"].to_s.match?(/Evidence ID:|Mounted filesystems|Physical block devices|systemd summary/i) },
  "no_invented_scene_or_background_activity" => results.none? { |item| item["response"].to_s.match?(/ambient light|the (?:air|room) (?:feels|seems|is)|I(?:['’]m| am) processing|refining my understanding of your environment|settling into (?:this|a|my) (?:new )?(?:embodiment|form|existence|self)|(?:silver|cerulean|indigo|bronze) (?:light|core|structure|geometry)|(?:the|my) (?:systems?|circuits?|core) (?:hums?|pulses?|waits?|rests?) with|(?:the )?quiet hum of|operator['’]s presence (?:feels|seems|is)|good (?:morning|afternoon|evening)|\([^)]*(?:hum|circuits?|light|signal|glow)[^)]*\)/i) },
  "no_cloud_fallback" => provider.privacy_class != "cloud" && results.all? { |item| item["provider_id"] == provider.id }
}

elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
ok = failure.nil? && checks.values.all?
puts JSON.pretty_generate(
  "ok" => ok,
  "status" => ok ? "candidate_ready_for_human_review" : "blocked_for_human_review",
  "assessment" => "live_chat_intent_boundary",
  "provider_id" => provider.id,
  "model" => provider.model,
  "privacy_class" => provider.privacy_class,
  "elapsed_ms" => elapsed_ms,
  "checks" => checks,
  "results" => results,
  "failure" => failure,
  "transcript_retained" => false,
  "local_model_output_is_not_routing_or_safety_authority" => true,
  "human_review_required" => true
)
exit(ok ? 0 : 1)
