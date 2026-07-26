#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "yaml"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/local_search_chat_controls"
require_relative "../lib/soul_core/local_search_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class FakeVaultSearch
  def initialize(available: true)
    @available = available
  end

  def search(query:, limit:)
    unless @available
      return {
        "ok" => false,
        "lifecycle_state" => "awaiting_input",
        "message" => "SOUL_KNOWLEDGE_VAULT_PATH is not configured",
        "data" => {}
      }
    end

    content = "Signal Orchard is a reviewed vault workflow."
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "message" => "knowledge vault search complete",
      "data" => {
        "records" => [
          {
            "relative_path" => "Projects/Signal Orchard.md",
            "title" => "Signal Orchard",
            "excerpt" => content,
            "score" => 7,
            "sha256" => Digest::SHA256.hexdigest(content)
          }
        ].first(limit),
        "files_scanned" => 1
      }
    }
  end
end

class FakeMusicSearchStore
  def list(limit:)
    [
      {
        "project_id" => "music_1111111111111111",
        "title" => "Signal Engine",
        "intent" => "A signal-driven liquid drum and bass composition.",
        "caption" => "Rolling breaks, warm sub bass, evolving signal motif.",
        "lyrics" => "[Instrumental]",
        "bpm" => 174,
        "keyscale" => "D minor",
        "timesignature" => "4",
        "vocal_mode" => "instrumental",
        "rights_status" => "original",
        "updated_at" => "2026-07-26T12:00:00Z"
      }
    ].first(limit)
  end
end

class FakeVisualSearchStore
  def list(limit:)
    projects = [
      {
        "project_id" => "visual_project_2222222222222222",
        "title" => "Signal Cathedral",
        "intent" => "A machine cathedral receiving a distant signal.",
        "prompt" => "Dark cerulean architecture and one luminous signal line.",
        "negative_prompt" => "text, watermark",
        "aspect_ratio" => "landscape",
        "updated_at" => "2026-07-26T12:30:00Z"
      }
    ].first(limit)
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "message" => "visual projects listed",
      "data" => { "projects" => projects }
    }
  end
end

Dir.mktmpdir("soul-local-search-") do |root|
  FileUtils.mkdir_p(File.join(root, "docs", ".hidden"))
  File.write(File.join(root, "README.md"), "# Signal Manual\n\nRepository signal routing overview.\n")
  File.write(File.join(root, "docs", "SEARCH.md"), "# Search Design\n\nEvery signal result carries a source citation.\n")
  File.write(File.join(root, "docs", ".hidden", "SECRET.md"), "# Hidden Signal\n\nmust not appear\n")
  File.write(File.join(root, "docs", "oversized.md"), "signal " * 50_000)
  File.symlink(File.join(root, "docs", "SEARCH.md"), File.join(root, "docs", "linked.md"))

  clock = -> { Time.utc(2026, 7, 26, 17, 0, 0) }
  service = SoulCore::LocalSearchService.new(
    root: root,
    knowledge_vault_service: FakeVaultSearch.new,
    music_store: FakeMusicSearchStore.new,
    visual_studio: FakeVisualSearchStore.new,
    clock: clock
  )

  outcome = service.search(query: "signal", limit: 20)
  results = outcome.dig("data", "results") || []
  sources = results.map { |record| record["source"] }.uniq.sort
  check.call("all reviewed adapters contribute", outcome["lifecycle_state"] == "complete" && sources == SoulCore::LocalSearchService::SOURCES.sort)
  check.call(
    "results carry citations and freshness",
    results.all? do |record|
      record["reference"].to_s.length.positive? &&
        record["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/) &&
        record["retrieved_at"] == "2026-07-26T17:00:00.000000Z" &&
        record["authority"] == "reference_only"
    end
  )
  references = results.map { |record| record["reference"] }
  check.call("hidden, symlinked, and oversized documents excluded", references.none? { |value| value.include?("SECRET.md") || value.include?("linked.md") || value.include?("oversized.md") })
  check.call("search creates no persistent index", outcome.dig("data", "persistent_index") == false && Dir.glob(File.join(root, "**", "*index*"), File::FNM_DOTMATCH).empty?)

  music_only = service.search(query: "signal", limit: 5, sources: ["music"])
  check.call("source filter is exact", music_only.dig("data", "sources") == ["music"] && music_only.dig("data", "results").all? { |record| record["source"] == "music" })
  check.call("unknown source fails safely", service.search(query: "signal", sources: ["home"]).fetch("lifecycle_state") == "awaiting_input")
  check.call("query and result limits are bounded", service.search(query: "x", limit: 10)["lifecycle_state"] == "awaiting_input" && service.search(query: "signal", limit: 21)["lifecycle_state"] == "awaiting_input")

  without_vault = SoulCore::LocalSearchService.new(
    root: root,
    knowledge_vault_service: FakeVaultSearch.new(available: false),
    music_store: FakeMusicSearchStore.new,
    visual_studio: FakeVisualSearchStore.new,
    clock: clock
  ).search(query: "signal", limit: 10)
  check.call(
    "unavailable vault is isolated",
    without_vault["lifecycle_state"] == "complete" &&
      without_vault.dig("data", "source_status", "knowledge_vault", "lifecycle_state") == "awaiting_input" &&
      without_vault.dig("data", "results").any?
  )

  controls = SoulCore::LocalSearchChatControls.new(root: root, service: service)
  check.call("explicit Chat search is recognized", controls.match?("Search local projects and documents for signal"))
  check.call("ordinary project conversation is not search", !controls.match?("I am working on local projects and documents today."))
  check.call("generic source search remains available to web research", !controls.match?("Find sources for signal processing"))
  rendered = controls.respond("Search local projects and documents for signal")
  check.call("Chat renders source-attributed bounded results", rendered.include?("[music]") && rendered.include?("music://music_1111111111111111") && rendered.include?("Mutation: none"))

  decision = SoulCore::ConversationOrchestrator.new.plan(
    message: "Search local projects and documents for signal",
    provider_available: true
  )
  ordinary = SoulCore::ConversationOrchestrator.new.plan(
    message: "I am working on local projects and documents today.",
    provider_available: true
  )
  check.call("orchestrator preserves explicit deterministic routing", decision.kind == "deterministic_passthrough" && decision.flags["local_search_control"] == true)
  check.call("ordinary conversation stays conversational", ordinary.flags["local_search_control"] != true)

  facade = SoulCore::ApplicationFacade.new(root: root, local_search_service: service)
  envelope = facade.call(
    {
      "schema_version" => "soul.application.v1",
      "request_id" => "local-search-test-0001",
      "operation" => "local_search.search",
      "parameters" => { "query" => "signal", "limit" => 4, "sources" => ["repository", "music"] },
      "context" => { "interface" => "dashboard_test" }
    }
  )
  bad_shape = facade.call(
    {
      "schema_version" => "soul.application.v1",
      "request_id" => "local-search-test-0002",
      "operation" => "local_search.search",
      "parameters" => { "query" => "signal", "sources" => "music" },
      "context" => { "interface" => "dashboard_test" }
    }
  )
  check.call("typed application operation is bounded", envelope["lifecycle_state"] == "complete" && envelope.dig("data", "sources") == %w[repository music])
  check.call("application rejects malformed source filters", bad_shape["lifecycle_state"] == "failed")
end

registry = YAML.safe_load(File.binread(File.expand_path("../Soul/skills/registry.yaml", __dir__)))
skill = registry.dig("skills", "local.search")
check.call("skill registry exposes read-only local search", skill && skill["risk"] == "read_only" && skill["writes_files"] == false && skill["requires_approval"] == false)

implementation = %w[
  lib/soul_core/local_search_service.rb
  lib/soul_core/local_search_chat_controls.rb
  scripts/soul-local-search
].map { |path| File.binread(File.expand_path("../#{path}", __dir__)) }.join("\n")
check.call("implementation has no network or resident behavior", !implementation.match?(/Net::HTTP|TCPSocket|Thread\.new|watcher|inotify|systemd|cron/i))

puts "Local project and document search A1 verification:"
if errors.empty?
  puts "Local project and document search A1 verification passed."
else
  warn "Missing: #{errors.join(', ')}"
  exit 1
end
