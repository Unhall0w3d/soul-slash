#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/configuration_resolver"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "../lib/soul_core/conversation_provider_registry"
require_relative "../lib/soul_core/music_reference_synthesis_service"

root = File.expand_path("..", __dir__)
resolver = SoulCore::ConfigurationResolver.new(root: root, process_env: ENV)
report = resolver.resolve
abort "Configuration is invalid" unless report.fetch("ok")
environment = resolver.effective_environment
provider = SoulCore::ConversationProviderRegistry.new(env: environment).local.find(&:configured?)
abort "No configured local provider" unless provider

result = nil
Dir.mktmpdir("soul-reference-synthesis-live-eval") do |temporary|
  store = SoulCore::MusicReferenceLibraryStore.new(root: temporary, id_generator: -> { "abababababababab" })
  store.write_track(
    "reference_id" => "ref_1212121212121212", "status" => "candidate",
    "provenance" => {
      "canonical_url" => "https://youtu.be/EvalOnly1234", "platform" => "youtube", "source_id" => "EvalOnly1234",
      "title" => "Measured Night Pattern", "artists" => ["Reference Evaluation Ensemble"], "album" => nil,
      "duration_seconds" => 188, "rights_assertion" => "analysis_only", "captured_at" => "2026-07-17T20:00:00Z",
      "musicbrainz" => {}, "tools" => { "fixture" => "synthetic behavioral evaluation" }
    },
    "evidence" => {
      "status" => "extracted", "bpm" => 104.2, "bpm_alternatives" => [52.1], "key" => "A minor",
      "key_alternatives" => ["C major"], "meter" => nil, "sections" => [],
      "instrumentation" => ["clean electric guitar likely", "electric bass likely", "acoustic drums likely"],
      "production_traits" => ["moderate dynamic range", "dry transient emphasis"],
      "energy_curve" => ["restrained opening", "gradual mid-song lift", "highest energy in final third"],
      "vocal_traits" => [], "lyrical_traits" => [],
      "confidence_notes" => ["meter, vocal delivery, lyrics, and exact section boundaries were not measured"],
      "extractor_receipt" => { "fixture" => true, "audio_retained" => false }
    }
  )
  client = SoulCore::ConversationProviderClient.new(env: environment, root: root)
  service = SoulCore::MusicReferenceSynthesisService.new(provider_client: client, store: store)
  result = service.draft(reference_id: "ref_1212121212121212", scope: "all", provider: provider)
end

revision = result.dig("data", "revision")
puts JSON.pretty_generate(
  "provider" => provider.id, "model" => provider.model,
  "lifecycle_state" => result["lifecycle_state"], "reason" => result["reason"],
  "candidate" => revision&.slice("title", "intent", "caption", "lyrics", "bpm", "keyscale", "timesignature", "exclusions", "rationale"),
  "automatic_approval" => result.dig("data", "automatic_approval")
)
abort "Live music reference synthesis eval did not reach human review" unless result["lifecycle_state"] == "blocked_for_human_review" && revision
