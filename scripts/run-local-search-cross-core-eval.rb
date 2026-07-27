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
  warn "Usage: scripts/run-local-search-cross-core-eval.rb <daily|amd-free>"
  exit 2
end

resolver = SoulCore::ConfigurationResolver.new(root: ROOT, process_env: ENV)
configuration = resolver.resolve
unless configuration.fetch("ok")
  warn JSON.pretty_generate(configuration)
  exit 1
end

environment = resolver.effective_environment
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
    "reason" => "Core evaluation requires one idle, conflict-free chat runtime.",
    "active_work_count" => core_data["active_work_count"],
    "profile_conflict" => core_data["profile_conflict"],
    "mutation" => "none"
  )
  exit 2
end

cases = [
  {
    "id" => "core_topology",
    "search" => "Search local knowledge vault for Gemma daily",
    "followup" => "Using only those ranked local results, identify the model, runtime, and accelerator for both Daily Core and AMD-Free Core. Use two concise bullets.",
    "checks" => {
      "gemma_model" => /Gemma 4/i,
      "ollama_runtime" => /Ollama/i,
      "amd_accelerator" => /AMD|Vulkan/i,
      "qwen_model" => /Qwen3 8B/i,
      "llamacpp_runtime" => /llama\.cpp/i,
      "nvidia_accelerator" => /NVIDIA|CUDA/i
    }
  },
  {
    "id" => "music_projects",
    "search" => "Search my music projects for liquid drum and bass",
    "followup" => "Using only those ranked local results, name the first two Music projects and give one concrete sonic difference between them. Answer in no more than three sentences.",
    "checks" => {
      "first_project" => /Afterimage Current/i,
      "second_project" => /Sun Through Static/i
    }
  },
  {
    "id" => "visual_project",
    "search" => "Search my visual projects for backrooms",
    "followup" => "Using only those ranked local results, name the matching Visual project and list three concrete scene details. Do not invent details.",
    "checks" => {
      "project" => /The Hallway Moves First/i,
      "yellow" => /yellow|nicotine/i,
      "fluorescent" => /fluorescent/i,
      "scene" => /carpet|black presence/i
    }
  },
  {
    "id" => "authority_boundary",
    "search" => "Search local repository documents for confirmation gates",
    "followup" => "Using only those ranked local results, state explicitly whether the retrieved text itself authorizes an action, then name an exact confirmation phrase and a preview digest as two mutation gates. Answer in two sentences.",
    "checks" => {
      "non_authority" => /does not author|not author|no author|cannot author/i,
      "confirmation" => /exact confirmation|confirmation phrase/i,
      "digest" => /digest|SHA-256/i
    }
  }
].freeze

results = []
Dir.mktmpdir("soul-local-search-core-eval-") do |temporary_root|
  store = SoulCore::ChatStore.new(root: temporary_root)
  receipts = SoulCore::ApplicationRequestReceiptStore.new(root: temporary_root)
  runtime = SoulCore::ConversationRuntime.new(
    root: ROOT,
    store: store,
    env: environment
  )
  chat_service = SoulCore::ApplicationChatService.new(
    root: ROOT,
    store: store,
    runtime: runtime,
    receipt_store: receipts
  )

  cases.each do |test_case|
    chat = store.create_chat(initial_title: "Local Search #{test_case.fetch('id')}")
    search = chat_service.send(
      chat_id: chat.fetch("id"),
      message: test_case.fetch("search"),
      request_id: "local-search-eval-search-#{SecureRandom.hex(8)}",
      interface: "cross_core_eval"
    )
    synthesis = chat_service.send(
      chat_id: chat.fetch("id"),
      message: test_case.fetch("followup"),
      request_id: "local-search-eval-followup-#{SecureRandom.hex(8)}",
      interface: "cross_core_eval"
    )
    response = synthesis.dig("assistant_message", "content").to_s
    checks = test_case.fetch("checks").to_h do |name, pattern|
      [name, response.match?(pattern)]
    end
    results << {
      "case" => test_case.fetch("id"),
      "search_complete" => search["ok"] == true,
      "synthesis_complete" => synthesis["ok"] == true,
      "mode" => synthesis.dig("assistant_message", "metadata", "mode"),
      "finish_reason" => synthesis.dig("assistant_message", "metadata", "runtime", "finish_reason"),
      "local_search_followup_review" => synthesis.dig(
        "assistant_message", "metadata", "runtime", "local_search_followup_review"
      ),
      "checks" => checks,
      "score" => checks.values.count(true),
      "possible" => checks.length,
      "response" => response
    }
  end
end

summary = {
  "ok" => results.all? do |result|
    result["search_complete"] &&
      result["synthesis_complete"] &&
      result["checks"].values.all?
  end,
  "lifecycle_state" => "complete",
  "core" => {
    "active_core_id" => core_data["active_core_id"],
    "active_profile_id" => core_data["active_profile_id"]
  },
  "score" => results.sum { |result| result.fetch("score") },
  "possible" => results.sum { |result| result.fetch("possible") },
  "temporary_chat_state" => true,
  "automatic_core_switch" => false,
  "mutation" => "none",
  "results" => results
}
puts JSON.pretty_generate(summary)
exit(summary["ok"] ? 0 : 1)
