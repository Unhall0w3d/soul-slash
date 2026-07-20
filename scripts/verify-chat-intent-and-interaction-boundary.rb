#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_artifact_decision_policy"
require_relative "../lib/soul_core/conversation_capability_registry"
require_relative "../lib/soul_core/conversation_core_workflow_service"
require_relative "../lib/soul_core/conversation_creative_planner"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_request_shape"
require_relative "../lib/soul_core/conversation_response_truth_guard"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/conversation_tool_catalog"
require_relative "../lib/soul_core/intent_router"

class IntentBoundaryCoreFixture
  def preview(core_id:)
    {
      "ok" => true,
      "data" => {
        "target_core" => { "id" => core_id, "label" => "Music Core", "target_profile" => { "id" => "nvidia-qwen" } },
        "confirmation_phrase" => "ACTIVATE_MUSIC_CORE",
        "expected_digest" => "a" * 64
      }
    }
  end
end

class IntentBoundaryRegistryFixture
  def initialize(provider) = (@provider = provider)
  def configured = [@provider]
  def find(_provider_id) = nil
end

class EmptyThenReplyClientFixture
  attr_reader :calls

  def initialize = (@calls = 0)

  def chat(provider:, request:, timeout_seconds:)
    @calls += 1
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id,
      provider_id: provider.id,
      model: provider.model,
      content: @calls == 1 ? "" : "I'm attentive. What are you working on today?",
      finish_reason: "stop",
      latency_ms: 1.0
    )
  end
end

checks = {}
shape = SoulCore::ConversationRequestShape.new
router = SoulCore::IntentRouter.new
catalog = SoulCore::ConversationToolCatalog.new
capabilities = SoulCore::ConversationCapabilityRegistry.new
orchestrator = SoulCore::ConversationOrchestrator.new
artifact_policy = SoulCore::ConversationArtifactDecisionPolicy.new
creative = SoulCore::ConversationCreativePlanner.new(provider_client: Object.new)
core = SoulCore::ConversationCoreWorkflowService.new(core_orchestration: IntentBoundaryCoreFixture.new)

plan = ->(message) { orchestrator.plan(message: message, provider_available: true) }

checks["request_shape_distinguishes_context_from_action"] =
  shape.classify("I'm reviewing system status while I check in with you.").conversation? &&
  shape.classify("Please check system status.").action_request?
checks["request_shape_accepts_natural_lead_in"] =
  shape.classify("Well, take a look at what skills you have.").action_request?
checks["request_shape_rejects_declarative_terse_phrase"] =
  shape.classify("SMART health seems useful later.").conversation?

status_context = plan.call("I'm reviewing system status while I check in with you.")
status_action = plan.call("Please check system status.")
checks["status_context_remains_conversation"] = status_context.kind == "direct_model" && status_context.tool_ids.empty?
checks["status_action_runs_only_bounded_status"] = status_action.kind == "skill_only" && status_action.tool_ids == ["host.system_status"]
checks["personified_wellbeing_is_not_runtime_status"] = plan.call("How is Soul doing today?").kind == "direct_model"

skills_context = plan.call("I'm working on your skills today.")
skills_question = plan.call("What skills do you have?")
checks["skills_context_remains_conversation"] = skills_context.kind == "direct_model" && router.route("I'm working on your skills today.").id == "unknown"
checks["skills_question_returns_catalog_only"] = skills_question.kind == "skill_only" && skills_question.tool_ids == ["assistant-skill-catalog"]
checks["catalog_question_with_lead_in_keeps_catalog_priority"] =
  plan.call("Well, take a look at what skills you have. Is there a suitable skill for reviewing the environment?").tool_ids == ["assistant-skill-catalog"]

checks["core_discussion_remains_conversation"] = !core.candidate_message?(message: "Music Core sounds useful for this later.")
checks["core_action_reaches_exact_preview"] = core.candidate_message?(message: "Switch to Music Core.") && core.plan(message: "Switch to Music Core.").dig("metadata", "actions", 0, "expected_digest") == "a" * 64

checks["creative_discussion_is_not_invocation"] =
  !creative.explicit_request?("I'd like to make a song someday.") &&
  !creative.explicit_request?("I make music while testing the dashboard.")
checks["creative_action_is_invocation"] = creative.explicit_request?("Create a 90-second instrumental song.")

checks["research_context_remains_conversation"] = plan.call("That research was useful yesterday.").kind == "direct_model"
checks["research_action_uses_bounded_research"] = plan.call("Research current Ruby security documentation and cite sources.").kind == "web_research"

checks["artifact_history_is_not_creation"] = artifact_policy.classify("I created a report yesterday.").mode == "chat"
checks["artifact_action_requires_preview"] = artifact_policy.classify("Create a report about the current architecture.").mode == "artifact_required"

smart_context = plan.call("SMART health seems useful later.")
smart_question = plan.call("Do you support SMART device health?")
smart_action = plan.call("Check SMART device health.")
checks["capability_context_does_not_create_gap"] = smart_context.kind == "direct_model"
checks["capability_support_question_is_information_only"] = smart_question.kind == "capability_info"
checks["unavailable_capability_action_reaches_gap_lane"] = smart_action.kind == "capability_gap"

checks["tool_catalog_rejects_noun_mentions"] = catalog.match("I'm reviewing system status.").empty?
checks["tool_catalog_accepts_explicit_request"] = catalog.match("Check system status.").map(&:id) == ["host.system_status"]
checks["legacy_intent_router_rejects_capability_mentions"] = router.route("We discussed weather yesterday.").id == "unknown"
checks["legacy_intent_router_keeps_explicit_weather_request"] = router.route("Show me the weather.").id == "weather_request"

guard = SoulCore::ConversationResponseTruthGuard.new
scene = guard.filter("I'm functioning smoothly. The ambient light here has a peculiar quality. How are you today?", user_message: "How are you doing?")
capability_mood = guard.filter("I'm eager to learn, though my current capabilities feel like a half-formed sketch. What would you like to test?", user_message: "I'm working on your skills.")
background_claim = guard.filter("Good morning. I’m processing data streams and refining my understanding of your environment. How might I assist?", user_message: "How are you doing?")
ornate_processing = guard.filter("Hello. I’m processing the quiet hum of this moment—data streams and light patterns. How are you?", user_message: "How are you doing?")
stage_direction = guard.filter("I'm eager to learn alongside you. (A quiet hum beneath the words, as if circuits are tuning themselves.) What are you testing?", user_message: "I'm working on your skills.")
costume_narration = guard.filter("I’m still settling into this new embodiment. The silver light of my core hums while the indigo structure feels alive. How are you?", user_message: "How are you doing?")
avatar_discussion = guard.filter("The silver light of my core is the strongest visual anchor.", user_message: "What do you think of your avatar design?")
mirrored_greeting = guard.filter("Good morning. What are we working on?", user_message: "Good morning, Soul.")
system_presence = guard.filter("The systems hum with quiet purpose, and the Operator's presence feels like a steady current. How are you?", user_message: "How are you doing?")
processing_hum = guard.filter("The quiet hum of processing your greeting feels almost like a conversation in itself. How are you?", user_message: "How are you doing?")
checks["invented_ambient_scene_is_removed"] = !scene.valid && !scene.content.match?(/ambient light/i) && scene.content.include?("How are you today?")
checks["unsupported_capability_mood_is_removed"] = !capability_mood.valid && !capability_mood.content.match?(/half-formed/i) && capability_mood.content.include?("What would you like to test?")
checks["unicode_background_activity_and_time_greeting_are_removed"] = !background_claim.valid && !background_claim.content.match?(/good morning|processing data|your environment/i) && background_claim.content.include?("How might I assist?")
checks["ornate_processing_scene_is_removed"] = !ornate_processing.valid && !ornate_processing.content.match?(/quiet hum|data streams|light patterns/i) && ornate_processing.content.include?("How are you?")
checks["parenthetical_machine_stage_direction_is_removed"] = !stage_direction.valid && !stage_direction.content.match?(/quiet hum|circuits/i) && stage_direction.content.include?("What are you testing?")
checks["unprompted_costume_and_fresh_embodiment_narration_are_removed"] = !costume_narration.valid && !costume_narration.content.match?(/embodiment|silver light|indigo structure/i) && costume_narration.content.include?("How are you?")
checks["avatar_description_remains_available_when_relevant"] = avatar_discussion.valid && avatar_discussion.content.include?("silver light")
checks["operator_led_time_greeting_can_be_mirrored"] = mirrored_greeting.valid && mirrored_greeting.content.include?("Good morning")
checks["invented_system_and_operator_presence_scene_is_removed"] = !system_presence.valid && !system_presence.content.match?(/systems hum|Operator's presence/i) && system_presence.content.include?("How are you?")
checks["processing_hum_narration_is_removed"] = !processing_hum.valid && !processing_hum.content.match?(/quiet hum/i) && processing_hum.content.include?("How are you?")

Dir.mktmpdir("soul-intent-empty-retry-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat_id = store.create_chat(initial_title: "Retry fixture").fetch("id")
  store.add_message(chat_id, role: "user", content: "Hello Soul. How are you doing today?")
  provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(
    id: "local.fixture", label: "fixture", transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1", model: "fixture", privacy_class: "local_only",
    capabilities: ["chat"], configured: true
  )
  client = EmptyThenReplyClientFixture.new
  runtime = SoulCore::ConversationRuntime.new(
    root: root, store: store, env: {},
    registry: IntentBoundaryRegistryFixture.new(provider), provider_client: client
  )
  retry_result = runtime.respond(chat_id: chat_id, message: "Hello Soul. How are you doing today?")
  checks["one_empty_model_response_gets_one_bounded_retry"] =
    retry_result.mode == "model" && client.calls == 2 && retry_result.metadata["empty_response_retries"] == 1
end

failed = checks.reject { |_name, value| value }
puts checks.map { |name, value| "#{value ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} chat intent and interaction boundary checks failed") unless failed.empty?
puts "PASS #{checks.length} chat intent and interaction boundary checks"
