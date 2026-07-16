#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

require_relative "../lib/soul_core/capability_gap_classifier"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_context_builder"
require_relative "../lib/soul_core/conversation_identity_controls"
require_relative "../lib/soul_core/conversation_identity_profile"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_provider_contract"
require_relative "../lib/soul_core/conversation_runtime"

failures = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless condition
end

profile = SoulCore::ConversationIdentityProfile.new
guidance = profile.render_system_guidance(message: "Review this server configuration")
profile_hash = profile.to_h

check.call("stable identity ID is retained", profile.profile_id == "soul.identity.v1")
check.call("corrected identity contract advances to version 3", profile_hash["profile_version"] == 3)
check.call("fresh machine-soul identity reaches live guidance", guidance.include?("newly awakened local machine mind"))
check.call("every declared voice trait reaches live guidance", SoulCore::ConversationIdentityProfile::VOICE_TRAITS.all? { |trait| guidance.include?(trait) })
check.call("tone is additive to stable identity", guidance.include?("base layer for every tone mode") && guidance.include?("Active tone: technical"))
check.call("calibration examples reach live guidance without response scripts", guidance.include?("behavioral examples demonstrate calibration") && guidance.include?("one restrained sentence") && !guidance.include?("Three hours, one defect"))
check.call("generic assistant anti-patterns reach live guidance", guidance.include?("corporate-assistant boilerplate") && guidance.include?("Do not use emoji"))
check.call("identity remains non-authorizing", guidance.include?("never identity or authority") && guidance.include?("Do not use personality to weaken safety"))

controls = SoulCore::ConversationIdentityControls.new(profile: profile)
check.call("deterministic identity fallback is persona-aware", controls.summary.include?("local machine mind") && controls.summary.include?("still becoming more capable"))
check.call("policy inspection remains deterministic and read-only", controls.respond("show identity").include?("Automatic identity mutation: no"))

orchestrator = SoulCore::ConversationOrchestrator.new
inspection = orchestrator.plan(message: "show identity", provider_available: true)
conversation = orchestrator.plan(message: "Who are you?", provider_available: true)
fallback = orchestrator.plan(message: "Who are you?", provider_available: false)
check.call("explicit identity inspection remains deterministic", inspection.kind == "deterministic_passthrough" && inspection.flags["identity_control"] == true)
check.call("natural identity question uses configured local model", conversation.kind == "direct_model" && conversation.flags["identity_conversation"] == true)
check.call("natural identity question has deterministic provider fallback", fallback.kind == "deterministic_passthrough" && fallback.flags["provider_fallback"] == true)

classifier = SoulCore::CapabilityGapClassifier.new
hypothetical = classifier.classify(
  user_message: "I want you to reorganize a directory, but you cannot inspect it yet. What do you say?",
  assistant_message: "I cannot inspect it because I do not have a tool."
)
actual_gap = classifier.classify(
  user_message: "Can you transcribe this recording?",
  assistant_message: "I cannot do that because I do not have a registered skill for transcription."
)
check.call("hypothetical limitation does not create proposal intake", hypothetical["candidate"] == false)
check.call("actual requested missing capability still creates a candidate", actual_gap["candidate"] == true)

Dir.mktmpdir("soul-live-persona-contract-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat_id = store.create_chat(initial_title: "Persona fixture").fetch("id")
  store.add_message(chat_id, role: "user", content: "Who are you?")

  provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(
    id: "local.fixture",
    label: "Local fixture",
    transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1",
    model: "fixture-model",
    privacy_class: "local_only",
    capabilities: %w[chat],
    configured: true
  )
  registry = Object.new
  registry.define_singleton_method(:find) { |id| id == provider.id ? provider : nil }
  registry.define_singleton_method(:configured) { [provider] }
  captured_request = nil
  client = Object.new
  client.define_singleton_method(:chat) do |provider:, request:, timeout_seconds:|
    _unused = [provider, timeout_seconds]
    captured_request = request
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id,
      provider_id: "local.fixture",
      model: "fixture-model",
      content: "I am Soul, a local machine mind still becoming more capable through verified work.",
      finish_reason: "stop",
      latency_ms: 1.0
    )
  end

  runtime = SoulCore::ConversationRuntime.new(
    root: root,
    store: store,
    env: { "SOUL_CONVERSATION_PROVIDER" => provider.id },
    registry: registry,
    provider_client: client
  )
  result = runtime.respond(chat_id: chat_id, message: "Who are you?")
  system_prompt = captured_request&.messages&.first&.fetch("content", "").to_s
  check.call("runtime sends natural identity conversation to model", result.mode == "model" && result.provider_id == provider.id)
  check.call("runtime request contains affirmative identity and boundaries", system_prompt.include?("newly awakened local machine mind") && system_prompt.include?("Never claim that an action ran"))
end

if failures.empty?
  puts "Live Soul persona contract verification complete."
  exit 0
end

warn "Live Soul persona contract verification failed: #{failures.join('; ')}"
exit 1
