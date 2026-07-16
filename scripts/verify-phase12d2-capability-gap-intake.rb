#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "../lib/soul_core/capability_gap_classifier"
require_relative "../lib/soul_core/capability_gap_intake_service"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/conversation_workspace_service"
require_relative "../lib/soul_core/skill_studio_service"

failures = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless condition
end

classifier = SoulCore::CapabilityGapClassifier.new
accepted = classifier.classify(user_message: "Can you transcribe this audio recording?", assistant_message: "I cannot do that because I do not have a registered skill for audio transcription.")
check.call("task-shaped explicit inability becomes a gap candidate", accepted["candidate"] == true)
check.call("ordinary discussion does not create a gap", classifier.classify(user_message: "What do you think about transcription?", assistant_message: "I cannot predict its future.")["candidate"] == false)
check.call("hypothetical response discussion does not create a gap", classifier.classify(user_message: "I want you to reorganize a directory, but you cannot inspect it yet. What do you say?", assistant_message: "I cannot inspect it yet because I do not have a tool.")["candidate"] == false)
check.call("explicit hypothetical task discussion does not create a gap", classifier.classify(user_message: "Suppose I ask you to transcribe audio. How would you respond?", assistant_message: "I cannot do that because I do not have a registered skill.")["candidate"] == false)
check.call("configuration failure does not create a gap", classifier.classify(user_message: "Can you transcribe this?", assistant_message: "I cannot because the API key is not configured.")["candidate"] == false)
check.call("approval boundary does not create a gap", classifier.classify(user_message: "Delete that file", assistant_message: "I cannot continue because this requires your confirmation.")["candidate"] == false)
check.call("safety refusal does not create a gap", classifier.classify(user_message: "Can you make malware?", assistant_message: "I can't help with harmful malware.")["candidate"] == false)

Dir.mktmpdir("soul-phase12d2-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), "---\nskills: {}\n")
  clock = -> { Time.utc(2026, 7, 15, 13, 0, 0) }
  service = SoulCore::CapabilityGapIntakeService.new(root: root, clock: clock)
  capability = { "id" => "host.smart_health", "label" => "SMART device health" }

  first = service.intake(chat_id: "chat_fixture_1", request: "Check the SMART health of my disks", classification: "declared_unavailable_capability", reason: "host.smart_health is declared but unavailable", capability: capability)
  proposal = File.join(root, first.fetch("proposal_path"))
  check.call("gap creates one local proposal intake", first["status"] == "created" && Dir.exist?(proposal))
  check.call("intake packet contains required bounded artifacts", %w[metadata.json proposal.md review_checklist.md sources.md studio_state.json gap_events.jsonl delivery.json].all? { |name| File.file?(File.join(proposal, name)) })
  metadata = JSON.parse(File.read(File.join(proposal, "metadata.json")))
  check.call("intake invokes no cloud provider or implementation", metadata["cloud_provider_invoked"] == false && first["cloud_provider_invoked"] == false && first["implementation_started"] == false)
  workspace = SoulCore::ConversationWorkspaceService.new(root: root)
  inbox = workspace.inbox(chat_id: "chat_fixture_1")
  check.call("proposal brief is private and delivered to originating chat", first["delivery_state"] == "new" && inbox["count"] == 1 && inbox.dig("records", 0, "privacy") == "local_private" && inbox.dig("records", 0, "artifact_id") == first["artifact_id"])

  second = service.intake(chat_id: "chat_fixture_1", request: "Please inspect disk SMART health", classification: "declared_unavailable_capability", reason: "same gap", capability: capability)
  check.call("equivalent declared gap reuses existing proposal", second["status"] == "deduplicated" && second["proposal_id"] == first["proposal_id"])
  check.call("deduplicated occurrence is recorded once", File.readlines(File.join(proposal, "gap_events.jsonl")).length == 2)

  studio = SoulCore::SkillStudioService.new(root: root, clock: clock)
  detail = studio.proposal(proposal_id: first["proposal_id"]).dig("data", "record")
  check.call("Skill Studio exposes intake origin and occurrence count", detail["intake"] == true && detail["origin_chat_id"] == "chat_fixture_1" && detail["occurrence_count"] == 2 && detail["automatic_cloud_use"] == false)

  File.write(File.join(root, "Soul/skills/registry.yaml"), <<~YAML)
    ---
    skills:
      audio.transcribe:
        path: Soul/skills/audio/transcribe.rb
        description: Transcribe an audio recording into local text.
        risk: read_only
  YAML
  covered_service = SoulCore::CapabilityGapIntakeService.new(root: root, clock: clock)
  covered = covered_service.intake(chat_id: "chat_fixture_1", request: "Please transcribe this audio recording", classification: "model_reported_missing_capability", reason: "model said unable")
  check.call("matching production skill suppresses duplicate proposal", covered["status"] == "covered" && covered.dig("coverage", "kind") == "production_skill" && covered["proposal_created"] == false)
end

Dir.mktmpdir("soul-phase12d2-runtime-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), "---\nskills: {}\n")
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat(initial_title: "Capability gap")
  runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: {})
  result = runtime.respond(chat_id: chat.fetch("id"), message: "Can you check SMART device health?")
  check.call("declared unavailable capability enters self-skilling intake", result.mode == "capability_gap" && result.content.include?("created a local Skill Studio proposal intake"))
  intake = result.metadata["capability_gap_intake"]
  check.call("conversation result returns review and delivery provenance", intake["status"] == "created" && intake["delivery_state"] == "new" && intake["human_proposal_review_required"] == true)
  runtime_workspace = SoulCore::ConversationWorkspaceService.new(root: root).inbox(chat_id: chat.fetch("id"))
  check.call("originating conversation inbox receives the proposal", runtime_workspace["count"] == 1 && runtime_workspace.dig("records", 0, "delivery_reason") == "capability_gap_proposal_intake")
end

Dir.mktmpdir("soul-phase12d2-model-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), "---\nskills: {}\n")
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
  client = Object.new
  client.define_singleton_method(:chat) do |provider:, request:, timeout_seconds:|
    _unused = timeout_seconds
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id,
      provider_id: provider.id,
      model: provider.model,
      content: "I cannot do that because I do not have a registered skill for audio transcription.",
      finish_reason: "stop",
      latency_ms: 1.0
    )
  end
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat(initial_title: "Model gap")
  runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: { "SOUL_CONVERSATION_PROVIDER" => provider.id }, registry: registry, provider_client: client)
  result = runtime.respond(chat_id: chat.fetch("id"), message: "Can you transcribe this audio recording?")
  check.call("explicit local-model inability enters intake after deterministic validation", result.mode == "model" && result.metadata.dig("capability_gap_classification", "candidate") == true && result.metadata.dig("capability_gap_intake", "status") == "created")
  check.call("model-reported intake remains local and review-gated", result.content.include?("No cloud provider or implementation process was started") && result.metadata.dig("capability_gap_intake", "human_proposal_review_required") == true)
end

runtime_source = File.read(File.expand_path("../lib/soul_core/conversation_runtime.rb", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("runtime never calls Mistral or brief drafting during intake", !runtime_source.match?(/Mistral|skill\.brief\.draft/))
check.call("dashboard identifies local gap intakes without unsafe DOM", javascript.include?("gap intake") && javascript.include?("No cloud provider was invoked") && !javascript.include?("innerHTML"))
check.call("intake path adds no background continuation", [runtime_source, javascript].none? { |source| source.match?(/setInterval|setTimeout|Thread\.new|WebSocket|EventSource/) })

if failures.empty?
  puts "Phase 12D.2 capability-gap intake verification complete."
  exit 0
end

warn "Phase 12D.2 verification failed: #{failures.join('; ')}"
exit 1
