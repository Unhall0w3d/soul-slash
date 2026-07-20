#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_creative_workflow_service"
require_relative "../lib/soul_core/conversation_core_workflow_service"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_response_truth_guard"
require_relative "../lib/soul_core/intent_router"

class FakePlanner
  attr_accessor :plan
  def initialize(plan) = (@plan = plan)
  def explicit_request?(message) = message.match?(/\b(?:make|create|generate)\b/i) && message.match?(/\b(?:song|image|music|visual)\b/i)
  def cancel?(message) = message.strip.casecmp?("cancel creative flow")
  def draft(**) = { "ok" => true, "lifecycle_state" => "complete", "plan" => @plan }
  def missing_required(value)
    missing = []
    supplied = value.fetch("user_provided_required")
    missing << "intent" if %w[music combined].include?(value["kind"]) && value["existing_music_title"].empty? && !supplied.include?("music_intent")
    missing << "visual intent" if %w[visual combined].include?(value["kind"]) && value["existing_visual_title"].empty? && !supplied.include?("visual_intent")
    missing
  end
end

class FakeCore
  attr_reader :executions, :active
  def initialize = (@active = "daily"; @executions = 0)
  def status = outcome({ "active_core_id" => @active })
  def preview(core_id:)
    outcome({ "target_core" => { "id" => core_id, "target_profile" => { "id" => "nvidia-qwen" } },
      "confirmation_phrase" => "ACTIVATE_MUSIC_CORE", "expected_digest" => "a" * 64 })
  end
  def execute(**attributes)
    @active = attributes.fetch(:core_id); @executions += 1; outcome({ "active_core_id" => @active }, mutation: "core_activated")
  end
  private
  def outcome(data, mutation: "none") = { "ok" => true, "lifecycle_state" => "complete", "reason" => "ok", "data" => data, "mutation" => mutation }
end

class FakeReviewPlanner
  attr_accessor :music_disposition
  def initialize(music_disposition: "keep") = (@music_disposition = music_disposition)
  def draft(**)
    { "ok" => true, "review" => {
      "related" => true, "music_disposition" => @music_disposition, "music_rating" => 4,
      "musical_quality" => "passed", "prompt_adherence" => "partial",
      "vocal_adherence" => "passed", "lyric_adherence" => "passed",
      "music_notes" => "The groove is coherent; the brass payoff arrives a little late.",
      "visual_disposition" => "keep", "visual_rating" => 5,
      "visual_notes" => "The image carries the intended poised, luminous atmosphere.",
      "next_question" => ""
    } }
  end
end

class FakeMusic
  attr_reader :created, :reviews, :revisions
  def initialize = (@created = []; @reviews = []; @revisions = [])
  def create_project(attributes)
    @created << attributes
    ok("project" => attributes.merge("project_id" => "music_1111111111111111"))
  end
  def generation_preview(project_id:) = ok("candidate_id" => "candidate_2222222222222222", "confirmation_phrase" => "START_MUSIC_GENERATION", "expected_digest" => "b" * 64)
  def generation_execute(**) = ok("candidate" => candidate("candidate_2222222222222222"))
  def record_review(project_id:, candidate_id:, review:)
    @reviews << review.merge("project_id" => project_id, "candidate_id" => candidate_id)
    ok("review" => review)
  end
  def list_projects(limit:) = ok("projects" => [])
  def inspect_project(project_id:)
    project = @created.last.merge("project_id" => project_id)
    review = @reviews.reverse.find { |item| item["candidate_id"] == "candidate_2222222222222222" }
    ok("project" => project, "generations" => [candidate("candidate_2222222222222222").merge("review" => review)])
  end
  def revision_preview(project_id:, source_candidate_id:, revision:)
    @revision_preview = { "project_id" => project_id, "source_candidate_id" => source_candidate_id, "revision" => revision }
    ok("candidate_id" => "candidate_5555555555555555", "confirmation_phrase" => "START_MUSIC_GENERATION", "expected_digest" => "d" * 64)
  end
  def revision_execute(**attributes)
    @revisions << attributes
    ok("candidate" => candidate("candidate_5555555555555555").merge("source_candidate_id" => attributes.fetch(:source_candidate_id)))
  end
  private
  def candidate(candidate_id)
    { "candidate_id" => candidate_id, "generation_input" => {
      "caption" => "Technical guitar and liquid breakbeats interlock, gather brass color, then resolve with a deliberate final cadence.",
      "lyrics" => "", "bpm" => 110, "keyscale" => "D minor", "timesignature" => "4"
    } }
  end
  def ok(data) = { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "reason" => "ok", "data" => data, "mutation" => "test" }
end

class FakeRevisionDrafter
  attr_reader :calls
  def initialize = (@calls = [])
  def draft(**attributes)
    @calls << attributes
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "reason" => "drafted", "data" => {
      "revision" => {
        "caption" => "Technical guitars interlock more clearly over liquid breakbeats, with patient counterpoint, controlled brass escalation, and a deliberate resolved ending.",
        "lyrics" => "", "bpm" => 112, "keyscale" => "D minor", "timesignature" => "4"
      },
      "rationale" => "Preserve the successful arc while making the guitar dialogue and ending more explicit.",
      "changes" => ["Replace Sound and Structure with the proposed materially revised arrangement.", "Change tempo from 110 BPM to 112 BPM."],
      "packet_digest" => "e" * 64
    } }
  end
end

class FakeMusicDisposition
  attr_reader :export_executions, :reject_executions
  def initialize = (@export_executions = []; @reject_executions = [])
  def export_preview(project_id:, candidate_id:)
    ok("confirmation_phrase" => "EXPORT_FINISHED_SONG", "expected_digest" => "f" * 64, "preview_scope" => {
      "operation" => "export_finished_song", "project_id" => project_id, "candidate_id" => candidate_id,
      "destination" => "/home/operator/Music/soul-music/signal-loom", "files" => %w[master.flac listening.mp3 song.json song-info.md],
      "overwrite" => false, "external_publication" => false
    })
  end
  def export_execute(**attributes)
    @export_executions << attributes
    complete({ "export" => { "destination" => "/home/operator/Music/soul-music/signal-loom" } }, mutation: "finished_song_exported")
  end
  def reject_preview(project_id:, candidate_id:)
    ok("confirmation_phrase" => "DELETE_REJECTED_CANDIDATE", "expected_digest" => "1" * 64, "preview_scope" => {
      "operation" => "delete_rejected_music_candidate", "project_id" => project_id, "candidate_id" => candidate_id,
      "deletes" => %w[FLAC MP3 candidate_input vocal_analysis current_review], "retains" => ["small rejection receipt"],
      "descendant_candidate_ids" => [], "external_export_deleted" => false
    })
  end
  def reject_execute(**attributes)
    @reject_executions << attributes
    complete({ "rejection" => { "candidate_id" => attributes.fetch(:candidate_id) } }, mutation: "music_candidate_deleted")
  end
  private
  def ok(data) = { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "reason" => "previewed", "data" => data, "mutation" => "none" }
  def complete(data, mutation:) = { "ok" => true, "lifecycle_state" => "complete", "reason" => "complete", "data" => data, "mutation" => mutation }
end

class FakeVisual
  attr_reader :created, :reviews
  def initialize = (@created = []; @reviews = [])
  def create(attributes)
    @created << attributes
    ok("project" => attributes.merge("project_id" => "visual_project_3333333333333333", "candidates" => []))
  end
  def generation_preview(project_id:) = ok("candidate_id" => "visual_candidate_4444444444444444", "confirmation_phrase" => "GENERATE_VISUAL_DRAFT", "expected_digest" => "c" * 64)
  def generation_execute(**) = ok("candidate" => { "candidate_id" => "visual_candidate_4444444444444444" })
  def record_review(project_id:, candidate_id:, review:)
    @reviews << review.merge("project_id" => project_id, "candidate_id" => candidate_id)
    ok("review" => review)
  end
  def list(limit:) = ok("projects" => [])
  private
  def ok(data) = { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "reason" => "ok", "data" => data, "mutation" => "test" }
end

def plan(kind: "combined", supplied: %w[music_intent duration_seconds vocal_mode rights_status visual_intent])
  {
    "related" => true, "kind" => kind, "music_intent" => "an intricate but coherent ascent", "duration_seconds" => 90,
    "vocal_mode" => "instrumental", "rights_status" => "original", "title" => "Signal Loom", "caption" => "Technical guitar and liquid breakbeats interlock, gather brass color, then resolve with a deliberate final cadence.",
    "lyrics" => "", "bpm" => 110, "keyscale" => "D minor", "timesignature" => "4", "seed" => 42,
    "visual_intent" => "cover art for the same ascending signal", "visual_title" => "Signal Loom Cover",
    "visual_prompt" => "A poised machine figure mapping luminous signal paths in an abyssal indigo observatory, cinematic landscape composition.",
    "negative_prompt" => "text, watermark, extra fingers", "aspect_ratio" => "landscape", "visual_seed" => 84,
    "existing_music_title" => "", "existing_visual_title" => "", "user_provided_required" => supplied,
    "next_question" => "", "summary" => "One coordinated music and visual candidate."
  }
end

class FixedPlanClient
  def initialize(value) = (@value = value)
  def chat(provider:, request:, timeout_seconds:)
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id, provider_id: provider.id, model: provider.model,
      content: JSON.generate(@value), finish_reason: "stop", latency_ms: 1.0
    )
  end
end

checks = {}
checks["skill_catalog_requires_explicit_request"] = SoulCore::IntentRouter.new.route("I am working on your skills today").id == "unknown"
checks["explicit_skill_catalog_still_routes"] = SoulCore::IntentRouter.new.route("What skills do you have?").id == "skill_catalog"
status_statement = "I'm doing alright, reviewing system status while I check in with you."
status_router = SoulCore::IntentRouter.new
status_orchestrator = SoulCore::ConversationOrchestrator.new
statement_plan = status_orchestrator.plan(message: status_statement, provider_available: true)
request_plan = status_orchestrator.plan(message: "Please check system status", provider_available: true)
checks["system_status_mention_remains_conversation"] = status_router.route(status_statement).id == "unknown" && statement_plan.kind == "direct_model" && statement_plan.tool_ids.empty?
checks["explicit_system_status_request_still_runs_bounded_skill"] = request_plan.kind == "skill_only" && request_plan.tool_ids == ["host.system_status"]
checks["personified_soul_wellbeing_question_remains_conversation"] = status_orchestrator.plan(message: "How is Soul doing today?", provider_available: true).kind == "direct_model"
guarded_greeting = SoulCore::ConversationResponseTruthGuard.new.filter("Hello! I'm processing the day's data with quiet efficiency. How are you today? 🌟", user_message: "Hello Soul! How are you doing today?")
checks["unsupported_background_activity_and_unprompted_emoji_are_removed"] = !guarded_greeting.valid && !guarded_greeting.content.include?("processing") && !guarded_greeting.content.include?("🌟") && guarded_greeting.content.include?("How are you today?") && guarded_greeting.style_adjustments == ["removed unprompted emoji"]

core_control = FakeCore.new
core_workflow = SoulCore::ConversationCoreWorkflowService.new(core_orchestration: core_control)
checks["explicit_core_request_is_recognized"] = core_workflow.candidate_message?(message: "Switch to Music Core")
checks["core_discussion_is_not_an_invocation"] = !core_workflow.candidate_message?(message: "I was thinking about Music Core earlier")
core_ready = core_workflow.plan(message: "Switch to Music Core")
checks["core_chat_action_reuses_exact_runtime_gate"] = core_ready["mode"] == "core_activation_ready" && core_ready.dig("metadata", "actions", 0, "operation") == "core.activate.execute" && core_control.executions.zero?

provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(id: "local.fixture", label: "fixture", transport: "openai_compatible",
  endpoint: "http://127.0.0.1:1/v1", model: "fixture", privacy_class: "local_only", capabilities: %w[chat structured_output], configured: true)
omitted_optional = plan(kind: "music", supplied: %w[music_intent duration_seconds vocal_mode rights_status]).merge("title" => "", "bpm" => 0, "keyscale" => "", "timesignature" => "")
completed = SoulCore::ConversationCreativePlanner.new(provider_client: FixedPlanClient.new(omitted_optional)).draft(provider: provider, chat_id: "chat_fixture", messages: [{ "role" => "user", "content" => "Make the song" }])
completed_plan = completed.fetch("plan")
checks["omitted_optional_fields_are_completed_without_touching_required_values"] = !completed_plan["title"].empty? && completed_plan["bpm"].between?(30, 300) && completed_plan.slice("music_intent", "duration_seconds", "vocal_mode", "rights_status") == omitted_optional.slice("music_intent", "duration_seconds", "vocal_mode", "rights_status")

Dir.mktmpdir("soul-creative-workflow") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat
  planner = FakePlanner.new(plan)
  core = FakeCore.new; music = FakeMusic.new; visual = FakeVisual.new
  review_planner = FakeReviewPlanner.new
  revision_drafter = FakeRevisionDrafter.new
  music_disposition = FakeMusicDisposition.new
  service = SoulCore::ConversationCreativeWorkflowService.new(root: root, chat_store: store, provider_client: Object.new,
    music_generation: music, visual_studio: visual, core_orchestration: core, planner: planner,
    review_planner: review_planner, revision_drafter: revision_drafter, music_disposition: music_disposition)

  checks["mention_is_not_initial_invocation"] = service.candidate_message?(chat_id: chat.fetch("id"), message: "I am working on music skills") == false
  ready = service.plan(chat_id: chat.fetch("id"), message: "Make a song and image", provider: Object.new)
  action = ready.dig("metadata", "actions", 0)
  checks["ready_brief_has_exact_action"] = ready["mode"] == "creative_ready" && action["operation"] == "chats.creative.execute" && action["expected_digest"].match?(/\A[a-f0-9]{64}\z/)

  stale = service.execute(chat_id: chat.fetch("id"), flow_id: action.fetch("flow_id"), confirmation: "START_CREATIVE_WORKFLOW", expected_digest: "0" * 64)
  checks["stale_action_is_blocked"] = !stale["ok"] && stale["reason"].include?("changed") && core.executions.zero?

  result = service.execute(chat_id: chat.fetch("id"), flow_id: action.fetch("flow_id"), confirmation: action.fetch("confirmation_phrase"), expected_digest: action.fetch("expected_digest"))
  attachments = result.dig("data", "attachments")
  checks["combined_generation_reaches_review_gate"] = result["ok"] && result["lifecycle_state"] == "blocked_for_human_review" && attachments.map { |item| item["kind"] } == %w[audio image]
  checks["core_transition_is_click_bound"] = core.executions == 1
  checks["music_required_values_are_preserved"] = music.created.first.slice("intent", "target_duration_seconds", "vocal_mode", "rights_status") == { "intent" => "an intricate but coherent ascent", "target_duration_seconds" => 90, "vocal_mode" => "instrumental", "rights_status" => "original" }
  checks["visual_candidate_is_authenticated_route"] = attachments.last["image_url"] == "/api/v1/visual/image/visual_project_3333333333333333/visual_candidate_4444444444444444"
  replay = service.execute(chat_id: chat.fetch("id"), flow_id: action.fetch("flow_id"), confirmation: action.fetch("confirmation_phrase"), expected_digest: action.fetch("expected_digest"))
  checks["execution_is_idempotent"] = replay.dig("data", "idempotent_replay") == true && core.executions == 1

  review_ready = service.plan(chat_id: chat.fetch("id"), message: "Keep both. Music is 4/5 and the image is 5/5.", provider: Object.new)
  review_action = review_ready.dig("metadata", "actions", 0)
  checks["human_feedback_becomes_exact_review_action"] = review_ready["mode"] == "creative_review_ready" && review_action["action_id"] == "creative_review"
  wrong_action = service.execute(chat_id: chat.fetch("id"), flow_id: review_action.fetch("flow_id"), action_id: "creative_generate",
    confirmation: review_action.fetch("confirmation_phrase"), expected_digest: review_action.fetch("expected_digest"))
  checks["review_action_identity_is_bound"] = !wrong_action["ok"] && music.reviews.empty? && visual.reviews.empty?
  reviewed = service.execute(chat_id: chat.fetch("id"), flow_id: review_action.fetch("flow_id"), action_id: review_action.fetch("action_id"),
    confirmation: review_action.fetch("confirmation_phrase"), expected_digest: review_action.fetch("expected_digest"))
  checks["exact_reviews_are_recorded"] = reviewed["ok"] && reviewed["lifecycle_state"] == "blocked_for_human_review" && music.reviews.one? && visual.reviews.one?
  reviewed_replay = service.execute(chat_id: chat.fetch("id"), flow_id: review_action.fetch("flow_id"), action_id: review_action.fetch("action_id"),
    confirmation: review_action.fetch("confirmation_phrase"), expected_digest: review_action.fetch("expected_digest"))
  checks["review_execution_is_idempotent"] = reviewed_replay.dig("data", "idempotent_replay") == true && music.reviews.one? && visual.reviews.one?

  checks["export_discussion_does_not_prepare_or_execute"] = service.plan(chat_id: chat.fetch("id"), message: "Export seems useful for finished work later.", provider: Object.new).nil? && music_disposition.export_executions.empty?
  export_ready = service.plan(chat_id: chat.fetch("id"), message: "Export the kept song.", provider: Object.new)
  export_action = export_ready.dig("metadata", "actions", 0)
  checks["kept_candidate_prepares_exact_export_action"] = export_ready["mode"] == "creative_music_export_ready" && export_action["action_id"] == "creative_music_export" && export_ready["content"].include?("Overwrite: forbidden")
  stale_export = service.execute(chat_id: chat.fetch("id"), flow_id: export_action.fetch("flow_id"), action_id: export_action.fetch("action_id"),
    confirmation: export_action.fetch("confirmation_phrase"), expected_digest: "0" * 64)
  checks["stale_export_action_mutates_nothing"] = !stale_export["ok"] && music_disposition.export_executions.empty?
  exported = service.execute(chat_id: chat.fetch("id"), flow_id: export_action.fetch("flow_id"), action_id: export_action.fetch("action_id"),
    confirmation: export_action.fetch("confirmation_phrase"), expected_digest: export_action.fetch("expected_digest"))
  checks["exact_export_completes_without_publication"] = exported["ok"] && exported["lifecycle_state"] == "complete" && exported.dig("data", "attachments", 0, "kind") == "audio" && music_disposition.export_executions.one?
  export_replay = service.execute(chat_id: chat.fetch("id"), flow_id: export_action.fetch("flow_id"), action_id: export_action.fetch("action_id"),
    confirmation: export_action.fetch("confirmation_phrase"), expected_digest: export_action.fetch("expected_digest"))
  checks["export_action_is_idempotent"] = export_replay.dig("data", "idempotent_replay") == true && music_disposition.export_executions.one?

  second = store.create_chat
  planner.plan = plan(kind: "music", supplied: %w[duration_seconds vocal_mode rights_status])
  missing = service.plan(chat_id: second.fetch("id"), message: "Make a song", provider: Object.new)
  checks["missing_user_required_field_is_not_invented"] = missing["mode"] == "creative_awaiting_input" && missing.dig("metadata", "creative_workflow", "missing_required") == ["intent"] && missing.dig("metadata", "actions").to_a.empty?

  canceled = service.plan(chat_id: second.fetch("id"), message: "cancel creative flow", provider: Object.new)
  checks["workflow_can_cancel_without_execution"] = canceled["mode"] == "creative_canceled"

  visual_chat = store.create_chat
  planner.plan = plan(kind: "visual", supplied: %w[visual_intent])
  visual_ready = service.plan(chat_id: visual_chat.fetch("id"), message: "Create an image", provider: Object.new)
  visual_action = visual_ready.dig("metadata", "actions", 0)
  visual_result = service.execute(chat_id: visual_chat.fetch("id"), flow_id: visual_action.fetch("flow_id"), action_id: visual_action.fetch("action_id"),
    confirmation: visual_action.fetch("confirmation_phrase"), expected_digest: visual_action.fetch("expected_digest"))
  checks["visual_only_uses_amd_free_core"] = visual_result["ok"] && core.active == "amd-free"

  revision_chat = store.create_chat
  planner.plan = plan(kind: "music", supplied: %w[music_intent duration_seconds vocal_mode rights_status])
  review_planner.music_disposition = "revise"
  revision_ready = service.plan(chat_id: revision_chat.fetch("id"), message: "Create a song", provider: Object.new)
  generation_action = revision_ready.dig("metadata", "actions", 0)
  service.execute(chat_id: revision_chat.fetch("id"), flow_id: generation_action.fetch("flow_id"), action_id: generation_action.fetch("action_id"),
    confirmation: generation_action.fetch("confirmation_phrase"), expected_digest: generation_action.fetch("expected_digest"))
  review_ready = service.plan(chat_id: revision_chat.fetch("id"), message: "Revise it. The guitars need clearer counterpoint and the ending should resolve naturally.", provider: Object.new)
  review_action = review_ready.dig("metadata", "actions", 0)
  recorded = service.execute(chat_id: revision_chat.fetch("id"), flow_id: review_action.fetch("flow_id"), action_id: review_action.fetch("action_id"),
    confirmation: review_action.fetch("confirmation_phrase"), expected_digest: review_action.fetch("expected_digest"))
  checks["revise_review_keeps_flow_active"] = recorded["ok"] && recorded["lifecycle_state"] == "blocked_for_human_review"
  checks["revision_discussion_does_not_draft_or_execute"] = service.plan(chat_id: revision_chat.fetch("id"), message: "The revision feature seems useful.", provider: Object.new).nil? && revision_drafter.calls.empty? && music.revisions.empty?

  proposed = service.plan(chat_id: revision_chat.fetch("id"), message: "Draft the revision and let me review it.", provider: Object.new)
  revision_action = proposed.dig("metadata", "actions", 0)
  revision_scope = proposed.dig("metadata", "creative_workflow", "revision_draft", "revision")
  checks["explicit_revision_request_returns_exact_action"] = proposed["mode"] == "creative_music_revision_ready" && revision_action["action_id"] == "creative_music_revision" && revision_scope["lyrics"] == ""
  stale_revision = service.execute(chat_id: revision_chat.fetch("id"), flow_id: revision_action.fetch("flow_id"), action_id: revision_action.fetch("action_id"),
    confirmation: revision_action.fetch("confirmation_phrase"), expected_digest: "0" * 64)
  checks["stale_revision_action_mutates_nothing"] = !stale_revision["ok"] && music.revisions.empty?

  revised = service.execute(chat_id: revision_chat.fetch("id"), flow_id: revision_action.fetch("flow_id"), action_id: revision_action.fetch("action_id"),
    confirmation: revision_action.fetch("confirmation_phrase"), expected_digest: revision_action.fetch("expected_digest"))
  checks["exact_revision_returns_linked_audio_candidate"] = revised["ok"] && revised["lifecycle_state"] == "blocked_for_human_review" &&
    revised.dig("data", "attachments", 0, "candidate_id") == "candidate_5555555555555555" && music.revisions.one? &&
    music.revisions.first.fetch(:source_candidate_id) == "candidate_2222222222222222"
  revision_replay = service.execute(chat_id: revision_chat.fetch("id"), flow_id: revision_action.fetch("flow_id"), action_id: revision_action.fetch("action_id"),
    confirmation: revision_action.fetch("confirmation_phrase"), expected_digest: revision_action.fetch("expected_digest"))
  checks["revision_action_is_idempotent"] = revision_replay.dig("data", "idempotent_replay") == true && music.revisions.one?

  reject_chat = store.create_chat
  planner.plan = plan(kind: "music", supplied: %w[music_intent duration_seconds vocal_mode rights_status])
  review_planner.music_disposition = "reject"
  reject_ready = service.plan(chat_id: reject_chat.fetch("id"), message: "Create a song", provider: Object.new)
  reject_generation = reject_ready.dig("metadata", "actions", 0)
  service.execute(chat_id: reject_chat.fetch("id"), flow_id: reject_generation.fetch("flow_id"), action_id: reject_generation.fetch("action_id"),
    confirmation: reject_generation.fetch("confirmation_phrase"), expected_digest: reject_generation.fetch("expected_digest"))
  reject_review = service.plan(chat_id: reject_chat.fetch("id"), message: "Reject it. The musical identity does not match the brief.", provider: Object.new)
  reject_review_action = reject_review.dig("metadata", "actions", 0)
  service.execute(chat_id: reject_chat.fetch("id"), flow_id: reject_review_action.fetch("flow_id"), action_id: reject_review_action.fetch("action_id"),
    confirmation: reject_review_action.fetch("confirmation_phrase"), expected_digest: reject_review_action.fetch("expected_digest"))
  checks["deletion_discussion_does_not_prepare_or_execute"] = service.plan(chat_id: reject_chat.fetch("id"), message: "Deleting rejected songs is appropriately serious.", provider: Object.new).nil? && music_disposition.reject_executions.empty?
  rejection_ready = service.plan(chat_id: reject_chat.fetch("id"), message: "Delete the rejected candidate.", provider: Object.new)
  rejection_action = rejection_ready.dig("metadata", "actions", 0)
  checks["rejected_candidate_prepares_exact_deletion_action"] = rejection_ready["mode"] == "creative_music_reject_ready" && rejection_action["action_id"] == "creative_music_reject" && rejection_ready["content"].include?("small rejection receipt")
  rejected = service.execute(chat_id: reject_chat.fetch("id"), flow_id: rejection_action.fetch("flow_id"), action_id: rejection_action.fetch("action_id"),
    confirmation: rejection_action.fetch("confirmation_phrase"), expected_digest: rejection_action.fetch("expected_digest"))
  checks["exact_rejection_removes_active_audio_candidate"] = rejected["ok"] && rejected["lifecycle_state"] == "complete" && rejected.dig("data", "flow", "generated", "music").nil? && music_disposition.reject_executions.one?

  supersede_chat = store.create_chat
  review_planner.music_disposition = "keep"
  first_ready = service.plan(chat_id: supersede_chat.fetch("id"), message: "Create a song", provider: Object.new)
  first_action = first_ready.dig("metadata", "actions", 0)
  service.execute(chat_id: supersede_chat.fetch("id"), flow_id: first_action.fetch("flow_id"), action_id: first_action.fetch("action_id"),
    confirmation: first_action.fetch("confirmation_phrase"), expected_digest: first_action.fetch("expected_digest"))
  first_review = service.plan(chat_id: supersede_chat.fetch("id"), message: "Keep it. This candidate matches the brief.", provider: Object.new)
  first_review_action = first_review.dig("metadata", "actions", 0)
  service.execute(chat_id: supersede_chat.fetch("id"), flow_id: first_review_action.fetch("flow_id"), action_id: first_review_action.fetch("action_id"),
    confirmation: first_review_action.fetch("confirmation_phrase"), expected_digest: first_review_action.fetch("expected_digest"))
  mismatch = service.plan(chat_id: supersede_chat.fetch("id"), message: "Delete the kept candidate.", provider: Object.new)
  checks["kept_candidate_cannot_prepare_rejection"] = mismatch["mode"] == "creative_music_disposition_mismatch" && music_disposition.reject_executions.one?
  second_ready = service.plan(chat_id: supersede_chat.fetch("id"), message: "Create another song", provider: Object.new)
  checks["new_creative_request_supersedes_unconsumed_disposition_flow"] = second_ready["mode"] == "creative_ready" && second_ready.dig("metadata", "creative_workflow", "flow_id") != first_action.fetch("flow_id")
end

failed = checks.reject { |_name, value| value }
puts checks.map { |name, value| "#{value ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} conversational creative workflow checks failed") unless failed.empty?
puts "PASS #{checks.length} conversational creative workflow checks"
