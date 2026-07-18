#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/music_reference_synthesis_service"
require_relative "../lib/soul_core/application_facade"

Contract = SoulCore::ConversationProviderContract
failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

def provider(privacy: "local_only", configured: true)
  Contract::ProviderDefinition.new(
    id: "fixture.reference-synthesis", label: "Reference synthesis fixture",
    transport: "openai_compatible", endpoint: "http://127.0.0.1:1/v1", model: "fixture-model",
    privacy_class: privacy, capabilities: %w[chat structured_output reasoning_control], configured: configured
  )
end

class ReferenceSynthesisClient
  attr_reader :calls

  def initialize(*contents)
    @contents = contents
    @calls = []
  end

  def chat(provider:, request:, timeout_seconds:)
    @calls << { provider: provider, request: request, timeout_seconds: timeout_seconds }
    Contract::ResponseEnvelope.new(
      request_id: request.request_id, provider_id: provider.id, model: provider.model,
      content: @contents.fetch(@calls.length - 1), finish_reason: "stop", latency_ms: 1.0
    )
  end
end

def proposal(**overrides)
  JSON.generate({
    "intent" => "A **tense** but hopeful nocturnal song about choosing motion over certainty.",
    "title" => "Signal Through Rain",
    "caption" => "Original art-rock pulse built from clipped clean-guitar figures, elastic electric bass, and close, dry acoustic drums. Begin with an exposed guitar motif, add the rhythm section for restrained verses, then widen each refrain with a second guitar register rather than stacked genre cues. Keep the lead vocal centered and intelligible with minimal ambience. Let the bridge thin to bass and rim clicks before the final refrain restores the full band, raises the dynamic ceiling, and ends on a short unresolved instrumental tag.",
    "lyrics" => "[**Verse 1**] We count the sparks beneath the rain [Chorus] Move before the map is drawn",
    "bpm" => 118, "keyscale" => "D minor", "timesignature" => "4",
    "exclusions" => ["No copied melody", "No source vocal likeness"],
    "rationale" => "The target translates measured energy and pulse into a distinct composition brief"
  }.merge(overrides))
end

def fusion_proposal
  value = JSON.parse(proposal(
    "title" => "Brass in the Static", "bpm" => 112,
    "caption" => "A unified nocturnal funk-rock arrangement led by syncopated clean guitar, elastic bass, tight dry drums, and compact brass answers. Open with the guitar pocket alone, bring the vocal into a restrained verse, then let brass punctuate only the ends of phrases. Build each chorus by widening the guitar voicing and adding counter-rhythmic horns without overlaying separate genre sections. Drop to bass, voice, and rim clicks in the bridge, then restore the full ensemble for one escalating final chorus and a precise ensemble stop."
  ))
  value["roles"] = [
    { "source_key" => "source_1", "role" => "harmonic tension and rising arrangement arc", "weight" => 0.55 },
    { "source_key" => "source_2", "role" => "syncopated pocket and brass punctuation", "weight" => 0.45 }
  ]
  JSON.generate(value)
end

def track_fixture
  {
    "reference_id" => "ref_1111111111111111", "status" => "candidate",
    "provenance" => {
      "canonical_url" => "https://youtu.be/ABCdef12345", "platform" => "youtube", "source_id" => "ABCdef12345",
      "title" => "Observed Source", "artists" => ["Fixture Artist"], "album" => "Fixture Album",
      "duration_seconds" => 201, "rights_assertion" => "analysis_only", "captured_at" => "2026-07-17T20:00:00Z",
      "musicbrainz" => {}, "tools" => { "yt_dlp" => "fixture", "essentia" => "fixture" }
    },
    "evidence" => {
      "status" => "extracted", "bpm" => 116.8, "bpm_alternatives" => [58.4], "key" => "D minor",
      "key_alternatives" => ["F major"], "meter" => "4/4 likely", "sections" => ["restrained verse", "widening refrain"],
      "instrumentation" => ["guitar likely", "bass likely"], "production_traits" => ["moderate dynamic range"],
      "energy_curve" => ["rising final third"], "vocal_traits" => ["single lead vocal likely"], "lyrical_traits" => ["compact phrases"],
      "confidence_notes" => ["meter remains a fallible estimate"], "extractor_receipt" => { "audio_retained" => false, "semantic_evidence_version" => 1 }
    }
  }
end

Dir.mktmpdir("soul-reference-synthesis-a5") do |root|
  ids = %w[aaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbb cccccccccccccccc dddddddddddddddd eeeeeeeeeeeeeeee]
  store = SoulCore::MusicReferenceLibraryStore.new(root: root, id_generator: -> { ids.shift }, clock: -> { Time.utc(2026, 7, 17, 21, 0, 0) })
  store.write_track(track_fixture)
  client = ReferenceSynthesisClient.new(
    proposal,
    proposal("title" => "Antenna in the Weather", "bpm" => 130, "intent" => "This model change must not leak."),
    proposal("title" => "Antenna in the Weather", "bpm" => 130)
  )
  service = SoulCore::MusicReferenceSynthesisService.new(provider_client: client, store: store, clock: -> { Time.utc(2026, 7, 17, 22, 0, 0) })

  wrong_first = service.draft(reference_id: track_fixture["reference_id"], scope: "title", provider: provider)
  first = service.draft(reference_id: track_fixture["reference_id"], scope: "all", provider: provider)
  first_revision = first.dig("data", "revision")
  request = client.calls.first.fetch(:request)
  packet = JSON.parse(request.messages.last.fetch("content"))
  check.call("first draft requires all scope and records one immutable candidate", wrong_first["lifecycle_state"] == "awaiting_input" && first["lifecycle_state"] == "blocked_for_human_review" && first["mutation"] == "music_reference_synthesis_candidate_recorded" && store.read(track_fixture["reference_id"]).dig("synthesis", "revisions").length == 1)
  check.call("one bounded local request uses strict structured output and no tools", client.calls.length == 1 && client.calls.first.fetch(:timeout_seconds) == 90.0 && request.max_output_tokens == 3_500 && request.response_format == SoulCore::MusicReferenceSynthesisService::RESPONSE_FORMAT && request.reasoning_mode == "disabled" && request.tools.empty? && request.privacy_requirement == "local_only")
  check.call("profile synthesis separates sonic portrait from metadata and temporal script", request.messages.first.fetch("content").include?("overall sonic portrait only") && request.messages.first.fetch("content").include?("separate lyrics value is the temporal script"))
  encoded_packet = JSON.generate(packet)
  check.call("packet distinguishes fallible observations from target synthesis", packet.dig("observed_evidence", "bpm") == 116.8 && packet.dig("rules", "original_material_only") == true && packet["current_synthesis"].nil? && packet["digest"].match?(/\A[a-f0-9]{64}\z/))
  check.call("synthesis withholds source identity and raw extractor scalars", !encoded_packet.include?("Observed Source") && !encoded_packet.include?("Fixture Artist") && !encoded_packet.include?("Fixture Album") && !encoded_packet.include?("extractor_receipt") && packet.dig("source_constraints", "duration_seconds") == 201)
  check.call("stored target fields are plain text with nonrepeating section markers", !first_revision["intent"].include?("**") && first_revision["lyrics"].start_with?("[Verse 1]\n") && first_revision["lyrics"].scan("[Verse 1]").length == 1 && first_revision["lyrics"].scan("[Chorus]").length == 1)

  stale_preview = service.approval_preview(reference_id: track_fixture["reference_id"], revision_id: first_revision["revision_id"])
  title_retry = service.draft(reference_id: track_fixture["reference_id"], scope: "title", provider: provider)
  second_revision = title_retry.dig("data", "revision")
  preserved = SoulCore::MusicReferenceSynthesisService::COMPONENTS.reject { |field| field == "title" }.all? { |field| second_revision[field] == first_revision[field] }
  check.call("component retry changes only its named component byte-for-byte", title_retry["lifecycle_state"] == "blocked_for_human_review" && second_revision["title"] == "Antenna in the Weather" && preserved && second_revision["revision_id"] != first_revision["revision_id"])
  stale_approval = service.approve(reference_id: track_fixture["reference_id"], revision_id: first_revision["revision_id"], confirmation: stale_preview.dig("data", "confirmation_phrase"), expected_digest: stale_preview.dig("data", "expected_digest"))
  check.call("a newly appended revision invalidates an older approval preview", stale_approval["lifecycle_state"] == "blocked_for_human_review" && stale_approval["reason"].include?("state changed"))
  unchanged = service.draft(reference_id: track_fixture["reference_id"], scope: "title", provider: provider)
  check.call("unchanged component retry stops without appending", unchanged["lifecycle_state"] == "awaiting_input" && unchanged["reason"].include?("did not change title") && store.read(track_fixture["reference_id"]).dig("synthesis", "revisions").length == 2)

  markdown_client = ReferenceSynthesisClient.new("```json\n#{proposal}\n```")
  markdown = SoulCore::MusicReferenceSynthesisService.new(provider_client: markdown_client, store: store).draft(reference_id: track_fixture["reference_id"], scope: "all", provider: provider)
  blocked_client = ReferenceSynthesisClient.new(proposal)
  cloud = SoulCore::MusicReferenceSynthesisService.new(provider_client: blocked_client, store: store).draft(reference_id: track_fixture["reference_id"], scope: "all", provider: provider(privacy: "cloud"))
  check.call("Markdown JSON fails and cloud synthesis stops before the model", markdown["lifecycle_state"] == "failed" && cloud["lifecycle_state"] == "blocked_for_human_review" && blocked_client.calls.empty?)

  preview = service.approval_preview(reference_id: track_fixture["reference_id"], revision_id: second_revision["revision_id"])
  denied = service.approve(reference_id: track_fixture["reference_id"], revision_id: second_revision["revision_id"], confirmation: "approve", expected_digest: preview.dig("data", "expected_digest"))
  approved = service.approve(reference_id: track_fixture["reference_id"], revision_id: second_revision["revision_id"], confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  approved_again = service.approve(reference_id: track_fixture["reference_id"], revision_id: second_revision["revision_id"], confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  saved = store.read(track_fixture["reference_id"])
  check.call("exact digest-bound approval is idempotent and preserves history", preview["lifecycle_state"] == "blocked_for_human_review" && denied["lifecycle_state"] == "blocked_for_human_review" && approved["lifecycle_state"] == "complete" && approved_again["lifecycle_state"] == "complete" && approved_again["mutation"] == "none" && saved.dig("synthesis", "selected_revision_id") == second_revision["revision_id"] && saved.dig("synthesis", "revisions").map { |item| item["revision_id"] } == [first_revision["revision_id"], second_revision["revision_id"]])

  second_track = track_fixture.merge(
    "reference_id" => "ref_2222222222222222",
    "provenance" => track_fixture.fetch("provenance").merge("canonical_url" => "https://youtu.be/ZYXwvu98765", "source_id" => "ZYXwvu98765", "title" => "Second Observation", "artists" => ["Second Fixture"]),
    "status" => "approved",
    "synthesis" => { "status" => "approved", "selected_revision_id" => "syn_9999999999999999", "revisions" => [first_revision.merge("revision_id" => "syn_9999999999999999", "title" => "Copper Orbit")] }
  )
  store.write_track(second_track)
  fusion_client = ReferenceSynthesisClient.new(fusion_proposal, proposal("title" => "Static Over Brass", "bpm" => 140))
  fusion_service = SoulCore::MusicReferenceSynthesisService.new(provider_client: fusion_client, store: store, clock: -> { Time.utc(2026, 7, 17, 23, 0, 0) })
  duplicate = fusion_service.draft_fusion(reference_ids: [track_fixture["reference_id"], track_fixture["reference_id"]], provider: provider)
  fusion = fusion_service.draft_fusion(reference_ids: [track_fixture["reference_id"], second_track["reference_id"]], provider: provider)
  fusion_packet = JSON.parse(fusion_client.calls.first.fetch(:request).messages.last.fetch("content"))
  fusion_record = fusion.dig("data", "reference")
  check.call("fusion rejects invalid selections before a model call", duplicate["lifecycle_state"] == "awaiting_input" && fusion_client.calls.length == 1)
  check.call("fusion sends only approved derived packets under opaque labels", fusion_packet.fetch("sources").length == 2 && fusion_packet.dig("sources", 0, "source_key") == "source_1" && !JSON.generate(fusion_packet).include?("Fixture Artist") && !JSON.generate(fusion_packet).include?("Observed Source"))
  check.call("fusion records one coherent unapproved candidate with normalized source roles", fusion["lifecycle_state"] == "blocked_for_human_review" && fusion["mutation"] == "music_reference_fusion_candidate_recorded" && fusion_record["record_type"] == "fusion" && fusion_record["status"] == "candidate" && fusion_record["roles"].sum { |role| role["weight"] } == 1.0 && fusion_record.dig("synthesis", "selected_revision_id").nil? && fusion.dig("data", "automatic_generation") == false)
  fusion_preview = fusion_service.approval_preview(reference_id: fusion_record["fusion_id"], revision_id: fusion.dig("data", "revision", "revision_id"))
  fusion_approved = fusion_service.approve(reference_id: fusion_record["fusion_id"], revision_id: fusion.dig("data", "revision", "revision_id"), confirmation: fusion_preview.dig("data", "confirmation_phrase"), expected_digest: fusion_preview.dig("data", "expected_digest"))
  check.call("the same exact gate approves a fusion without generating audio", fusion_approved["lifecycle_state"] == "complete" && fusion_approved.dig("data", "reference", "status") == "approved" && fusion_approved.dig("data", "reference", "synthesis", "selected_revision_id") == fusion.dig("data", "revision", "revision_id"))
  fusion_retry = fusion_service.draft(reference_id: fusion_record["fusion_id"], scope: "title", provider: provider)
  retried_fusion = fusion_retry.dig("data", "reference")
  check.call("fusion component retry preserves roles weights and every other target field", fusion_retry["lifecycle_state"] == "blocked_for_human_review" && fusion_retry.dig("data", "source_roles_changed") == false && retried_fusion["roles"] == fusion_record["roles"] && fusion_retry.dig("data", "revision", "title") == "Static Over Brass" && fusion_retry.dig("data", "revision", "bpm") == fusion.dig("data", "revision", "bpm") && retried_fusion.dig("synthesis", "revisions").length == 2)
  retry_preview = fusion_service.approval_preview(reference_id: fusion_record["fusion_id"], revision_id: fusion_retry.dig("data", "revision", "revision_id"))
  retry_approved = fusion_service.approve(reference_id: fusion_record["fusion_id"], revision_id: fusion_retry.dig("data", "revision", "revision_id"), confirmation: retry_preview.dig("data", "confirmation_phrase"), expected_digest: retry_preview.dig("data", "expected_digest"))
  check.call("approved fusion title tracks the selected immutable revision", retry_approved.dig("data", "reference", "title") == "Static Over Brass" && retry_approved.dig("data", "reference", "synthesis", "selected_revision_id") == fusion_retry.dig("data", "revision", "revision_id"))

  facade = SoulCore::ApplicationFacade.new(root: root, music_reference_synthesis_service: service, music_reference_synthesis_provider: provider)
  envelope = facade.call({ "schema_version" => "soul.application.v1", "request_id" => "reference-synthesis-a5-0001", "operation" => "music.references.synthesis.approval.preview", "parameters" => { "reference_id" => track_fixture["reference_id"], "revision_id" => second_revision["revision_id"] }, "context" => {} })
  check.call("application contract exposes the synthesis approval gate", envelope["lifecycle_state"] == "blocked_for_human_review" && envelope.dig("data", "confirmation_phrase") == SoulCore::MusicReferenceSynthesisService::CONFIRMATION)
end

Dir.mktmpdir("soul-reference-synthesis-caption-contract-a5") do |root|
  store = SoulCore::MusicReferenceLibraryStore.new(root: root)
  store.write_track(track_fixture)
  caption = "High-energy progressive rock at 110 BPM in D minor and 4/4 time, driven by distorted electric guitars, technical bass, deep 808 sub-bass, rapid trap hi-hats, and hard dry drums. The arrangement begins with a clean electric motif before escalating into a dense final passage with an aggressive close vocal and precise rhythmic articulation. Layer tapping guitar above the central riff, leave deliberate space around each vocal phrase, and use a compact instrumental turn to connect the restrained opening with the forceful final hook. Keep the production polished, immediate, and rhythmically exact."
  client = ReferenceSynthesisClient.new(proposal("caption" => caption))
  result = SoulCore::MusicReferenceSynthesisService.new(provider_client: client, store: store).draft(reference_id: track_fixture["reference_id"], scope: "all", provider: provider)
  check.call("profile synthesis rejects metadata embedded in Sound and Structure", result["lifecycle_state"] == "awaiting_input" && result["reason"].include?("dedicated field"))
end


Dir.mktmpdir("soul-reference-synthesis-insufficient-a5") do |root|
  store = SoulCore::MusicReferenceLibraryStore.new(root: root)
  sparse = track_fixture
  sparse["evidence"] = sparse.fetch("evidence").merge(
    "sections" => [], "instrumentation" => [], "vocal_traits" => [], "lyrical_traits" => [],
    "energy_curve" => ["segment 1: steady relative energy", "segment 2: lower relative energy"],
    "extractor_receipt" => { "dynamic_complexity" => 3.3248, "danceability" => 1.1342 }
  )
  store.write_track(sparse)
  client = ReferenceSynthesisClient.new(proposal)
  result = SoulCore::MusicReferenceSynthesisService.new(provider_client: client, store: store).draft(reference_id: sparse["reference_id"], scope: "all", provider: provider)
  check.call("sparse extractor-only evidence fails closed before the model", result["lifecycle_state"] == "awaiting_input" && result["reason"].include?("semantic evidence is incomplete") && result["reason"].include?("enrichment receipt") && client.calls.empty?)
end

Dir.mktmpdir("soul-reference-synthesis-rejection-a5") do |root|
  ids = %w[4444444444444444 5555555555555555]
  store = SoulCore::MusicReferenceLibraryStore.new(root: root, id_generator: -> { ids.shift })
  store.write_track(track_fixture)
  client = ReferenceSynthesisClient.new(proposal, proposal("title" => "Second Deliberate Target"))
  service = SoulCore::MusicReferenceSynthesisService.new(provider_client: client, store: store)
  candidate = service.draft(reference_id: track_fixture["reference_id"], scope: "all", provider: provider)
  revision_id = candidate.dig("data", "revision", "revision_id")
  preview = service.rejection_preview(reference_id: track_fixture["reference_id"], revision_id: revision_id)
  wrong = service.reject(reference_id: track_fixture["reference_id"], revision_id: revision_id, confirmation: "reject", expected_digest: preview.dig("data", "expected_digest"))
  rejected = service.reject(reference_id: track_fixture["reference_id"], revision_id: revision_id, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  rejected_again = service.reject(reference_id: track_fixture["reference_id"], revision_id: revision_id, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  approval = service.approval_preview(reference_id: track_fixture["reference_id"], revision_id: revision_id)
  check.call("wrong rejection confirmation preserves the candidate", wrong["lifecycle_state"] == "blocked_for_human_review" && wrong["mutation"] == "none")
  check.call("exact rejection preserves the immutable revision and is idempotent", rejected["lifecycle_state"] == "complete" && rejected["mutation"] == "music_reference_synthesis_rejected" && rejected.dig("data", "reference", "synthesis", "status") == "rejected" && rejected.dig("data", "reference", "synthesis", "rejected_revision_ids") == [revision_id] && rejected.dig("data", "reference", "synthesis", "revisions").length == 1 && rejected_again["lifecycle_state"] == "complete" && rejected_again["mutation"] == "none")
  check.call("a rejected revision cannot later be approved", approval["lifecycle_state"] == "awaiting_input" && approval["reason"].include?("cannot be approved"))
  retry_result = service.draft(reference_id: track_fixture["reference_id"], scope: "all", provider: provider)
  check.call("retry after rejection records a new candidate while retaining rejection history", retry_result["lifecycle_state"] == "blocked_for_human_review" && retry_result.dig("data", "reference", "synthesis", "status") == "candidate" && retry_result.dig("data", "reference", "synthesis", "rejected_revision_ids") == [revision_id] && retry_result.dig("data", "reference", "synthesis", "revisions").length == 2)
end

Dir.mktmpdir("soul-reference-synthesis-lock-a5") do |root|
  store = SoulCore::MusicReferenceLibraryStore.new(root: root)
  store.write_track(track_fixture)
  template = JSON.parse(proposal).slice(*SoulCore::MusicReferenceSynthesisService::COMPONENTS).merge(
    "scope" => "all", "rationale" => "Concurrent fixture", "created_at" => "2026-07-17T22:00:00Z",
    "provider_receipt" => { "local_only" => true }
  )
  revisions = %w[7777777777777777 8888888888888888].map { |suffix| template.merge("revision_id" => "syn_#{suffix}") }
  revisions.map { |revision| Thread.new { store.append_synthesis_revision(track_fixture["reference_id"], revision) } }.each(&:value)
  saved = store.read(track_fixture["reference_id"])
  check.call("per-record locking preserves simultaneous immutable appends", saved.dig("synthesis", "revisions").map { |revision| revision["revision_id"] }.sort == revisions.map { |revision| revision["revision_id"] }.sort)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("Music Studio separates evidence targets approval and exact rejection", %w[music-reference-observed music-reference-target music-reference-synthesis-confirmation music-reference-synthesis-reject-confirmation].all? { |id| html.include?(id) } && javascript.include?("music.references.synthesis.draft") && javascript.include?("music.references.synthesis.approval.execute") && javascript.include?("music.references.synthesis.rejection.execute"))
check.call("fusion UI requires explicit profile selection and exposes no automatic generation", html.include?("draft-music-reference-fusion") && javascript.include?("music.references.fusion.draft") && javascript.include?("count < 2 || count > 5") && !javascript.include?("setInterval(draftMusicReference"))
check.call("composition form teaches the ACE-Step caption and temporal-script split", html.include?("Describe the overall sonic identity here") && html.include?("[Intro - clean electric guitar instrumental]") && html.include?("Put BPM, key, and time in their dedicated fields"))

abort "Music reference synthesis A5 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music reference synthesis A5 verification passed."
