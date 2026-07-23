#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/music_revision_draft_service"
require_relative "../lib/soul_core/application_facade"

Contract = SoulCore::ConversationProviderContract
failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

def provider(privacy: "local_only", capabilities: %w[chat structured_output reasoning_control], configured: true)
  Contract::ProviderDefinition.new(
    id: "fixture.music-revision", label: "Music revision fixture", transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1", model: "fixture-model", privacy_class: privacy,
    capabilities: capabilities, configured: configured
  )
end

class RevisionDraftClient
  attr_reader :calls

  def initialize(content)
    @content = content
    @calls = []
  end

  def chat(provider:, request:, timeout_seconds:)
    @calls << { provider: provider, request: request, timeout_seconds: timeout_seconds }
    Contract::ResponseEnvelope.new(
      request_id: request.request_id, provider_id: provider.id, model: provider.model,
      content: @content, finish_reason: "stop", latency_ms: 1.0
    )
  end
end

source = {
  "caption" => "Melodic rock with clear drums and guitars.",
  "lyrics" => "[Verse 1]\nA careful hand upon the table",
  "bpm" => 120, "keyscale" => "E minor", "timesignature" => "4",
  "language" => "en", "duration" => 180, "seed" => 1701,
  "batch_size" => 1, "inference_steps" => 8
}
project = {
  "title" => "Fixture song", "intent" => "A restrained song that opens with every written line.",
  "target_duration_seconds" => 180, "vocal_mode" => "vocal", "rights_status" => "original"
}
review = {
  "rating" => 3, "disposition" => "revise", "musical_quality" => "passed", "prompt_adherence" => "partial",
  "vocal_adherence" => "partial", "lyric_adherence" => "failed", "notes" => "The first two lines were dropped; later lyrics drifted. Preserve the ending."
}
candidate = { "candidate_id" => "candidate_1111111111111111", "generation_input" => source, "review" => review }
analysis = {
  "machine_route" => "revision_recommended", "machine_heard_formatted" => "[Verse 1]\nA careful hand upon the table",
  "alignment" => { "sequence_recall" => 0.71, "lines" => [{ "status" => "missing", "intended" => "First line", "sequence_recall" => 0.0 }] }
}
valid_draft = JSON.generate(
  "caption" => "**Tense melodic rock** with a two-bar exposed vocal pickup before dry drums enter, then a restrained arrangement with clearly separated lead vocal. Keep the electric guitars narrow and subdued beneath each lyric, leave deliberate space between phrases, and widen the latter passage without masking consonants. Preserve the accepted ending with a short controlled decay and no added vocal ad-libs.",
  "bpm" => 116, "keyscale" => "E minor", "timesignature" => "4",
  "rationale" => "The exposed pickup and reduced opening arrangement should protect the missing lines while preserving the accepted ending."
)

client = RevisionDraftClient.new(valid_draft)
service = SoulCore::MusicRevisionDraftService.new(provider_client: client, clock: -> { Time.utc(2026, 7, 17, 22, 0, 0) })
result = service.draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
request = client.calls.first.fetch(:request)
packet = JSON.parse(request.messages.last.fetch("content"))
check.call("Soul produces one clean sonic caption and code preserves lyrics", result["lifecycle_state"] == "blocked_for_human_review" && result.dig("data", "revision", "caption").include?("exposed vocal pickup") && !result.dig("data", "revision", "caption").include?("Revision directives:") && !result.dig("data", "revision", "caption").include?("**") && result.dig("data", "revision", "lyrics") == source["lyrics"] && result.dig("data", "automatic_generation") == false && result.dig("data", "human_edit_required") == true && result["mutation"] == "none")
check.call("one bounded local request uses strict structured output and no tools", client.calls.length == 1 && client.calls.first.fetch(:timeout_seconds) == 90.0 && request.max_output_tokens == 5_000 && request.response_format == SoulCore::MusicRevisionDraftService::RESPONSE_FORMAT && request.reasoning_mode == "disabled" && request.tools.empty? && request.privacy_requirement == "local_only")
check.call("drafting packet carries exact source plus human and machine evidence", packet.dig("source_input", "caption") == source["caption"] && packet.dig("human_review", "notes") == review["notes"] && packet.dig("machine_heard", "route") == "revision_recommended" && packet["digest"].match?(/\A[a-f0-9]{64}\z/))
check.call("drafting packet binds the authoritative repeated section sequence", packet["required_section_sequence"] == ["Verse 1"] && packet.dig("project", "target_duration_seconds") == 180)
check.call("revision prompt separates sonic caption from metadata and temporal script", request.messages.first.fetch("content").include?("overall sonic portrait only") && request.messages.first.fetch("content").include?("dedicated metadata or the preserved lyrics script"))

check.call("review summary is reconstructed from exact materially changed fields", result.dig("data", "changes") == ["Replace Sound and Structure with the proposed materially revised arrangement.", "Change tempo from 120 BPM to 116 BPM."])

meter_client = RevisionDraftClient.new(JSON.generate(JSON.parse(valid_draft).merge("timesignature" => "4/4")))
meter = SoulCore::MusicRevisionDraftService.new(provider_client: meter_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
check.call("conventional equivalent meter notation normalizes to Soul's compact generation value", meter["lifecycle_state"] == "blocked_for_human_review" && meter.dig("data", "revision", "timesignature") == "4" && meter.dig("data", "changes").none? { |change| change.include?("time signature") })

unsupported_meter_client = RevisionDraftClient.new(JSON.generate(JSON.parse(valid_draft).merge("timesignature" => "11/8")))
unsupported_meter = SoulCore::MusicRevisionDraftService.new(provider_client: unsupported_meter_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
check.call("unsupported meter notation remains fail-closed", unsupported_meter["lifecycle_state"] == "awaiting_input" && unsupported_meter["reason"].include?("time signature is invalid"))

over_budget_caption = "Verse 1 (40 sec) begins sparsely with precise diction and controlled breath. Hook (40 sec) widens without masking the lead. Verse 2 (50 sec) restores every supplied line over restrained percussion. Hook (40 sec) repeats with matching clarity. Outro (20 sec) closes quietly with a short decay."
over_budget_client = RevisionDraftClient.new(JSON.generate(JSON.parse(valid_draft).merge("caption" => over_budget_caption)))
over_budget = SoulCore::MusicRevisionDraftService.new(provider_client: over_budget_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
metadata_caption = "High-energy progressive rock at 110 BPM in A-flat major and 4/4 time, driven by distorted electric guitars, technical bass, deep 808 sub-bass, rapid trap hi-hats, hard dry drums, and an aggressive close male vocal. The arrangement grows from a clean electric motif into a dense final instrumental passage."
metadata_client = RevisionDraftClient.new(JSON.generate(JSON.parse(valid_draft).merge("caption" => metadata_caption)))
metadata = SoulCore::MusicRevisionDraftService.new(provider_client: metadata_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
check.call("exact section timing is rejected from the sonic caption", over_budget["lifecycle_state"] == "awaiting_input" && over_budget["reason"].include?("temporal section changes"))
check.call("BPM key and meter are rejected from the sonic caption", metadata["lifecycle_state"] == "awaiting_input" && metadata["reason"].include?("dedicated field"))

fragment_client = RevisionDraftClient.new(JSON.generate(JSON.parse(valid_draft).merge("caption" => "Revised noir arrangement. Key revisions: (1) Intro: Expand to include the full")))
fragment = SoulCore::MusicRevisionDraftService.new(provider_client: fragment_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
check.call("truncated or embedded-list Sound and Structure fails before generation", fragment["lifecycle_state"] == "awaiting_input" && fragment["reason"].match?(/too short|mid-thought|cohesive instruction/) && fragment["mutation"] == "none")

unchanged_client = RevisionDraftClient.new(JSON.generate(
  "caption" => source["caption"], "bpm" => source["bpm"], "keyscale" => source["keyscale"], "timesignature" => source["timesignature"],
  "rationale" => "Try another seed."
))
unchanged = SoulCore::MusicRevisionDraftService.new(provider_client: unchanged_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
check.call("seed-only or otherwise unchanged model advice fails before any generation", unchanged["lifecycle_state"] == "awaiting_input" && unchanged["reason"].include?("material revision") && unchanged["mutation"] == "none")

closing_source = source.merge(
  "caption" => "Progressive alternative metal with ritual drums, snarling bass, downtuned guitars, industrial scrape, and raw male vocals rising from restraint to eruption. Open on a dying drone, drive through asymmetric riff cycles, hollow out the middle, then rebuild faster and heavier before an abrupt unresolved cutoff.",
  "lyrics" => "[Final Escalation]\nThe pressure taught the dark to bite\n[Cutoff]\nThe weight remembered"
)
closing_candidate = candidate.merge("generation_input" => closing_source, "review" => review.merge("notes" => "Nearly exact, but the final title line was dropped."))
closing_analysis = analysis.merge("alignment" => { "sequence_recall" => 0.95, "lines" => [{ "status" => "partial", "intended" => "The weight remembered", "sequence_recall" => 0.5 }] })
unchanged_closing = JSON.generate(
  "caption" => closing_source["caption"], "bpm" => closing_source["bpm"], "keyscale" => closing_source["keyscale"], "timesignature" => closing_source["timesignature"],
  "rationale" => "Preserve the accepted candidate."
)
closing_client = RevisionDraftClient.new(unchanged_closing)
closing = SoulCore::MusicRevisionDraftService.new(provider_client: closing_client).draft(project: project, candidate: closing_candidate, analysis: closing_analysis, provider: provider)
check.call("an isolated missing final lyric gets one bounded material caption adjustment", closing_client.calls.one? && closing["lifecycle_state"] == "blocked_for_human_review" && closing.dig("data", "revision", "caption").length <= 512 && closing.dig("data", "revision", "caption").include?("isolated closing lyric") && closing.dig("data", "revision", "lyrics") == closing_source["lyrics"] && closing.dig("data", "changes") == ["Replace Sound and Structure with the proposed materially revised arrangement."])

oversized_closing_client = RevisionDraftClient.new(JSON.generate(JSON.parse(unchanged_closing).merge("caption" => "Overwritten arrangement " * 40)))
oversized_closing = SoulCore::MusicRevisionDraftService.new(provider_client: oversized_closing_client).draft(project: project, candidate: closing_candidate, analysis: closing_analysis, provider: provider)
check.call("over-limit final-lyric advice is compressed without a second model request", oversized_closing_client.calls.one? && oversized_closing["lifecycle_state"] == "blocked_for_human_review" && oversized_closing.dig("data", "revision", "caption").length <= 512)

invalid_client = RevisionDraftClient.new("```json\n#{valid_draft}\n```")
invalid = SoulCore::MusicRevisionDraftService.new(provider_client: invalid_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider)
check.call("Markdown-wrapped JSON fails closed", invalid["lifecycle_state"] == "failed" && invalid["reason"].include?("invalid revision JSON"))

blocked_client = RevisionDraftClient.new(valid_draft)
cloud = SoulCore::MusicRevisionDraftService.new(provider_client: blocked_client).draft(project: project, candidate: candidate, analysis: analysis, provider: provider(privacy: "cloud"))
no_evidence = SoulCore::MusicRevisionDraftService.new(provider_client: blocked_client).draft(project: project, candidate: candidate.merge("review" => nil), analysis: nil, provider: provider)
check.call("cloud providers and evidence-free drafts stop before a model call", cloud["lifecycle_state"] == "blocked_for_human_review" && no_evidence["lifecycle_state"] == "awaiting_input" && blocked_client.calls.empty?)

class RevisionGenerationFacadeFixture
  attr_reader :preview_args, :execute_args

  def initialize(project, candidate)
    @project = project
    @candidate = candidate
  end

  def inspect_project(project_id:)
    { "ok" => true, "lifecycle_state" => "complete", "data" => { "project" => @project.merge("project_id" => project_id), "generations" => [@candidate.merge("project_id" => project_id)] } }
  end

  def revision_preview(**args)
    @preview_args = args
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => { "candidate_id" => "candidate_2222222222222222" } }
  end

  def revision_execute(**args)
    @execute_args = args
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => { "candidate" => { "generation_kind" => "revision" } } }
  end
end

class RevisionAnalysisFacadeFixture
  def initialize(analysis) = (@analysis = analysis)
  def read(**) = @analysis
end

class RevisionDraftFacadeFixture
  attr_reader :args
  def draft(**args)
    @args = args
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => { "revision" => { "caption" => "fixture revision" } }, "mutation" => "none" }
  end
end

generation_fixture = RevisionGenerationFacadeFixture.new(project, candidate)
draft_fixture = RevisionDraftFacadeFixture.new
facade = SoulCore::ApplicationFacade.new(
  root: Dir.pwd, music_generation_service: generation_fixture,
  music_candidate_analysis_service: RevisionAnalysisFacadeFixture.new(analysis),
  music_revision_draft_service: draft_fixture, music_revision_provider: provider
)
request = lambda do |operation, parameters|
  facade.call({ "schema_version" => "soul.application.v1", "request_id" => "revision-#{operation}", "operation" => operation, "parameters" => parameters, "context" => { "interface" => "dashboard" } })
end
draft_envelope = request.call("music.candidates.revision.draft", { "project_id" => "music_1111111111111111", "source_candidate_id" => candidate.fetch("candidate_id") })
revision_input = { "caption" => "changed", "lyrics" => source["lyrics"], "bpm" => 116, "keyscale" => "E minor", "timesignature" => "4", "seed" => 1702 }
preview_envelope = request.call("music.candidates.revision.preview", { "project_id" => "music_1111111111111111", "source_candidate_id" => candidate.fetch("candidate_id"), "revision" => revision_input })
execute_envelope = request.call("music.candidates.revision.execute", { "project_id" => "music_1111111111111111", "source_candidate_id" => candidate.fetch("candidate_id"), "candidate_id" => "candidate_2222222222222222", "revision" => revision_input, "confirmation" => "START_MUSIC_REVISION", "expected_digest" => "a" * 64 })
check.call("application contract dispatches the review-only Soul draft", draft_envelope["lifecycle_state"] == "blocked_for_human_review" && draft_fixture.args&.dig(:provider)&.id == "fixture.music-revision")
check.call("application contract dispatches exact revision preview", preview_envelope["lifecycle_state"] == "blocked_for_human_review" && generation_fixture.preview_args&.dig(:revision) == revision_input)
check.call("application contract dispatches confirmed foreground revision", execute_envelope["lifecycle_state"] == "blocked_for_human_review" && generation_fixture.execute_args&.dig(:confirmation) == "START_MUSIC_REVISION")

dashboard_js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard can retry a review-only Soul draft before generation", dashboard_js.include?('launch.textContent = "Retry Soul draft"') && dashboard_js.include?('.music-revision-rationale,.music-revision,.music-revision-gate') && dashboard_js.include?("No generation has started"))

abort "#{failures.length} music revision draft verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Music revision draft deterministic verification passed."
