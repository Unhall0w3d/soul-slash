#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_creative_workflow_service"
require_relative "../lib/soul_core/conversation_core_workflow_service"
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
  def draft(**)
    { "ok" => true, "review" => {
      "related" => true, "music_disposition" => "keep", "music_rating" => 4,
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
  attr_reader :created, :reviews
  def initialize = (@created = []; @reviews = [])
  def create_project(attributes)
    @created << attributes
    ok("project" => attributes.merge("project_id" => "music_1111111111111111"))
  end
  def generation_preview(project_id:) = ok("candidate_id" => "candidate_2222222222222222", "confirmation_phrase" => "START_MUSIC_GENERATION", "expected_digest" => "b" * 64)
  def generation_execute(**) = ok("candidate" => { "candidate_id" => "candidate_2222222222222222" })
  def record_review(project_id:, candidate_id:, review:)
    @reviews << review.merge("project_id" => project_id, "candidate_id" => candidate_id)
    ok("review" => review)
  end
  def list_projects(limit:) = ok("projects" => [])
  private
  def ok(data) = { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "reason" => "ok", "data" => data, "mutation" => "test" }
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
  service = SoulCore::ConversationCreativeWorkflowService.new(root: root, chat_store: store, provider_client: Object.new,
    music_generation: music, visual_studio: visual, core_orchestration: core, planner: planner, review_planner: FakeReviewPlanner.new)

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
  checks["exact_reviews_are_recorded"] = reviewed["ok"] && reviewed["lifecycle_state"] == "complete" && music.reviews.one? && visual.reviews.one?
  reviewed_replay = service.execute(chat_id: chat.fetch("id"), flow_id: review_action.fetch("flow_id"), action_id: review_action.fetch("action_id"),
    confirmation: review_action.fetch("confirmation_phrase"), expected_digest: review_action.fetch("expected_digest"))
  checks["review_execution_is_idempotent"] = reviewed_replay.dig("data", "idempotent_replay") == true && music.reviews.one? && visual.reviews.one?

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
end

failed = checks.reject { |_name, value| value }
puts checks.map { |name, value| "#{value ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} conversational creative workflow checks failed") unless failed.empty?
puts "PASS #{checks.length} conversational creative workflow checks"
