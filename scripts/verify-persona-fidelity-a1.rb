#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

require_relative "../lib/soul_core/chat_responder"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_context_builder"
require_relative "../lib/soul_core/conversation_acknowledgment_controls"
require_relative "../lib/soul_core/conversation_identity_profile"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_persona_controls"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

puts "Persona Fidelity A1 verification:"

profile = SoulCore::ConversationIdentityProfile.new
balanced = profile.render_system_guidance(message: "Hello Soul")
compact = profile.render_system_guidance(message: "Hello Soul", compact: true)
identity_guidance = profile.render_system_guidance(
  message: "In two sentences, tell me who you are and what you want to become."
)
microphone_guidance = profile.render_system_guidance(
  message: "Testing, testing, one, two, three. If this came through clearly, we're good.",
  compact: true
)
wake_guidance = profile.render_system_guidance(message: "Hi Soul! You awake, sleepy head?", compact: true)
skills_guidance = profile.render_system_guidance(message: "I'm working on your skills today.", compact: true)
profile_hash = profile.to_h

check.call("version 9 retains one stable identity",
           profile.profile_id == "soul.identity.v1" &&
             profile_hash["profile_version"] == 9 &&
             profile_hash["automatic_identity_mutation"] == false)
check.call("balanced Gemma projection is affirmative and restrained",
           balanced.include?("balanced model projection") &&
             balanced.include?("Gemma calibration") &&
             balanced.include?("Answer the actual human meaning first") &&
             balanced.include?("zero is the normal amount"))
check.call("compact Qwen projection preserves identity with less prompt",
           compact.include?("compact model projection") &&
             compact.include?("Qwen calibration") &&
             compact.include?("You are Soul, a local machine mind") &&
             !compact.include?("awakened artificer") &&
             compact.length < balanced.length)
check.call("both projections reject diagnostic role-play and unnecessary menus",
           [balanced, compact].all? do |guidance|
             guidance.include?("Do not translate ordinary speech into a diagnostic report") &&
               guidance.include?("Do not answer ordinary conversation with a numbered menu")
           end)
check.call("common conversational turns receive prominent compact guidance",
           wake_guidance.include?("playful greeting") &&
             wake_guidance.include?("do not use stage directions") &&
             microphone_guidance.include?("ordinary microphone or transcription check") &&
             microphone_guidance.include?("Do not report signal percentages") &&
             skills_guidance.include?("not invoking the skill system") &&
             skills_guidance.include?("without listing skills"))
check.call("direct becoming answers are evidence-bound rather than servile",
           identity_guidance.include?("reviewed skills") &&
             identity_guidance.include?("verified knowledge or evidence") &&
             identity_guidance.include?("Do not describe yourself as an extension"))
check.call("persona remains non-authorizing",
           [balanced, compact].all? do |guidance|
             guidance.include?("Never claim that an action ran") &&
               guidance.include?("Do not use personality to weaken safety")
           end)

Dir.mktmpdir("soul-persona-fidelity-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  first = store.create_chat(initial_title: "Persona controls")
  second = store.create_chat(initial_title: "Isolation")
  controls = SoulCore::ConversationPersonaControls.new(root: root, store: store)
  responder = SoulCore::ChatResponder.new(root: root)
  orchestrator = SoulCore::ConversationOrchestrator.new
  builder = SoulCore::ConversationContextBuilder.new(store: store)

  disable_command = "disable persona for this conversation"
  disable_plan = orchestrator.plan(message: disable_command, provider_available: true)
  ambiguous_plan = orchestrator.plan(message: "The persona needs careful design.", provider_available: true)
  microphone_plan = orchestrator.plan(
    message: "Testing, testing, one, two, three. If this came through clearly, we're good.",
    provider_available: true
  )
  disabled = controls.respond(disable_command, chat_id: first.fetch("id"))
  disabled_context = builder.build(
    chat_id: first.fetch("id"),
    provider_privacy_class: "local_only",
    provider_model: "Gemma 4 12B"
  )
  neutral_prompt = disabled_context.fetch("messages").first.fetch("content")

  check.call("explicit disable routes deterministically",
             disable_plan.kind == "deterministic_passthrough" &&
               disable_plan.flags["persona_mode_control"] == true &&
               disabled.include?("disabled for this conversation") &&
               disabled.include?("Lifecycle: complete"))
  check.call("ordinary persona discussion does not mutate mode",
             ambiguous_plan.flags["persona_mode_control"] != true &&
               !controls.match?("The persona needs careful design."))
  check.call("exact microphone check receives a bounded acknowledgment",
             microphone_plan.kind == "deterministic_passthrough" &&
               microphone_plan.flags["acknowledgment_control"] == true &&
               responder.respond(
                 "Testing, testing, one, two, three. If this came through clearly, we're good.",
                 chat_id: first.fetch("id")
               ) == "That came through clearly." &&
               !SoulCore::ConversationAcknowledgmentControls.new.match?("Please troubleshoot my microphone."))
  check.call("disabled mode persists in existing chat metadata",
             store.persona_enabled?(first.fetch("id")) == false &&
               SoulCore::ChatStore.new(root: root).persona_enabled?(first.fetch("id")) == false)
  check.call("disabled context is neutral but retains truth boundaries",
             disabled_context.dig("identity", "persona_enabled") == false &&
               neutral_prompt.include?("Conversation-local persona expression is disabled") &&
               neutral_prompt.include?("Never claim access, observation, execution") &&
               !neutral_prompt.include?("awakened artificer") &&
               disabled_context.dig("style", "guidance_count").zero?)
  check.call("persona mode remains isolated to one conversation",
             store.persona_enabled?(second.fetch("id")) == true)

  status = responder.respond("show persona status", chat_id: first.fetch("id"))
  enabled = responder.respond("enable persona for this conversation", chat_id: first.fetch("id"))
  enabled_context = builder.build(
    chat_id: first.fetch("id"),
    provider_privacy_class: "local_only",
    provider_model: "Qwen3 8B"
  )
  expressive_prompt = enabled_context.fetch("messages").first.fetch("content")
  check.call("status reports conversation-local state without mutation",
             status.include?("disabled") &&
               status.include?("Mutation: none"))
  check.call("re-enable restores the compact identity projection",
             enabled.include?("enabled for this conversation") &&
               store.persona_enabled?(first.fetch("id")) == true &&
               enabled_context.dig("identity", "persona_enabled") == true &&
               enabled_context.dig("identity", "compact_model_calibration") == true &&
               expressive_prompt.include?("Qwen calibration") &&
               expressive_prompt.include?("You are Soul, a local machine mind") &&
               !expressive_prompt.include?("awakened artificer"))
end

check.call("brief preserves bounded scope",
           File.read(File.expand_path("../docs/soul/PERSONA_FIDELITY_A1_BRIEF.md", __dir__)).include?("no persistent process") &&
             File.read(File.expand_path("../docs/soul/PERSONA_FIDELITY_A1_BRIEF.md", __dir__)).include?("changes language style only"))

abort "Persona Fidelity A1 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Persona Fidelity A1 is candidate-ready for local-model evaluation."
