#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/conversation_knowledge_reflection_service"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_provider_contract"
require_relative "../lib/soul_core/knowledge_vault_service"

errors = []
check = lambda do |name, condition|
  puts "- #{name}: #{condition ? 'ok' : 'FAIL'}"
  errors << name unless condition
end

class KnowledgeDraftClient
  attr_reader :requests

  def initialize(content)
    @content = content
    @requests = []
  end

  def chat(provider:, request:, timeout_seconds:)
    @requests << { provider: provider, request: request, timeout_seconds: timeout_seconds }
    SoulCore::ConversationProviderContract::ResponseEnvelope.new(
      request_id: request.request_id,
      provider_id: provider.id,
      model: provider.model,
      content: @content,
      finish_reason: "stop",
      latency_ms: 1.0
    )
  end
end

def provider(privacy_class: "local_only")
  SoulCore::ConversationProviderContract::ProviderDefinition.new(
    id: "fixture.#{privacy_class}",
    label: "Knowledge reflection fixture",
    transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1",
    model: "fixture-model",
    privacy_class: privacy_class,
    capabilities: %w[chat structured_output reasoning_control],
    configured: true
  )
end

def initialized_vault(root, clock)
  vault = File.join(root, "vault")
  FileUtils.mkdir_p(vault)
  service = SoulCore::KnowledgeVaultService.new(
    root: root,
    process_env: { "SOUL_KNOWLEDGE_VAULT_PATH" => vault },
    clock: clock
  )
  preview = service.initialize_preview
  service.initialize_execute(
    confirmation: SoulCore::KnowledgeVaultService::INITIALIZE_CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  [vault, service]
end

clock = -> { Time.utc(2026, 7, 24, 22, 30, 0) }
messages = [
  { "role" => "user", "content" => "We verified the Daily Core topology." },
  { "role" => "assistant", "content" => "Gemma runs on AMD and Qwen remains the NVIDIA fallback." }
]
durable_draft = JSON.generate(
  "preserve" => true,
  "title" => "Daily Core Topology",
  "body" => "The reviewed Daily Core runs Gemma on AMD while Qwen remains the NVIDIA fallback.",
  "knowledge_kind" => "decision",
  "tags" => %w[models runtime],
  "rationale" => "This is a stable reviewed project decision.",
  "uncertainties" => []
)

puts "Knowledge Reflection A2 verification:"

orchestrator = SoulCore::ConversationOrchestrator.new
explicit = orchestrator.plan(
  message: "Reflect on this conversation for reusable knowledge.",
  provider_available: true
)
casual = orchestrator.plan(
  message: "I have been thinking about knowledge and reflection lately.",
  provider_available: true
)
check.call("only a narrow explicit request routes to conversational reflection",
           explicit.kind == "knowledge_reflection" && casual.kind != "knowledge_reflection")

Dir.mktmpdir("soul-knowledge-a2-no-provider") do |root|
  _vault, knowledge = initialized_vault(root, clock)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: KnowledgeDraftClient.new(durable_draft),
    knowledge_vault_service: knowledge,
    clock: clock
  )
  outcome = service.create(chat_id: "chat_fixture", messages: messages, provider: nil)
  check.call("missing local provider waits without mutation",
             outcome["lifecycle_state"] == "awaiting_input" &&
               Dir.glob(File.join(root, "Soul/reflection/knowledge_pending/*")).empty?)
end

Dir.mktmpdir("soul-knowledge-a2-cloud") do |root|
  _vault, knowledge = initialized_vault(root, clock)
  client = KnowledgeDraftClient.new(durable_draft)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: client,
    knowledge_vault_service: knowledge,
    clock: clock
  )
  outcome = service.create(chat_id: "chat_fixture", messages: messages, provider: provider(privacy_class: "cloud"))
  check.call("cloud provider is rejected before transcript transmission",
             outcome["lifecycle_state"] == "blocked_for_human_review" && client.requests.empty?)
end

Dir.mktmpdir("soul-knowledge-a2-bounds") do |root|
  _vault, knowledge = initialized_vault(root, clock)
  client = KnowledgeDraftClient.new(durable_draft)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: client,
    knowledge_vault_service: knowledge,
    clock: clock
  )
  bounded_messages = 105.times.map { |index| { "role" => index.even? ? "user" : "assistant", "content" => "message #{index}" } }
  service.create(chat_id: "chat_fixture", messages: bounded_messages, provider: provider)
  packet = JSON.parse(client.requests.fetch(0).fetch(:request).messages.fetch(1).fetch("content"))
  check.call("conversation packet keeps only the newest 100 messages",
             packet.fetch("messages").length == 100 && packet.fetch("messages").first.fetch("content") == "message 5")

  oversized_client = KnowledgeDraftClient.new(durable_draft)
  oversized_service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: oversized_client,
    knowledge_vault_service: knowledge,
    clock: clock
  )
  oversized = 40.times.map { |index| { "role" => index.even? ? "user" : "assistant", "content" => "x" * 2_000 } }
  outcome = oversized_service.create(chat_id: "chat_oversized", messages: oversized, provider: provider)
  check.call("serialized transcript byte limit blocks before model transmission",
             outcome["lifecycle_state"] == "awaiting_input" && oversized_client.requests.empty?)
end

Dir.mktmpdir("soul-knowledge-a2-durable") do |root|
  vault, knowledge = initialized_vault(root, clock)
  client = KnowledgeDraftClient.new(durable_draft)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: client,
    knowledge_vault_service: knowledge,
    clock: clock
  )
  outcome = service.create(chat_id: "chat_fixture", messages: messages, provider: provider)
  data = outcome.fetch("data")
  candidate_path = File.join(root, data.fetch("candidate_path"))
  candidate = JSON.parse(File.read(candidate_path))
  request = client.requests.fetch(0).fetch(:request)
  destination = File.join(vault, data.fetch("relative_path"))
  check.call("local transcript is bounded and uses strict structured output",
             request.response_format&.dig("type") == "json_schema" &&
               request.privacy_requirement == "local_only" &&
               request.messages.map { |message| message["role"] } == %w[system user])
  check.call("durable candidate creates one private pending record and no vault note",
             outcome["lifecycle_state"] == "blocked_for_human_review" &&
               outcome["mutation"] == "knowledge_reflection_candidate_created" &&
               candidate["status"] == "pending_review" &&
               candidate["automatic_write"] == false &&
               (File.stat(candidate_path).mode & 0o777) == 0o600 &&
               !File.exist?(destination))
  check.call("provenance and evidence authority are assigned outside model output",
             candidate.dig("reflection_inputs", "source_reference") == "conversation:chat_fixture" &&
               candidate.dig("reflection_inputs", "evidence_status") == "operator_confirmed")
  check.call("preview exposes complete exact review data",
             data["recommended_destination"] == "knowledge_vault" &&
               data["markdown"].include?("# Daily Core Topology") &&
               data["preview_digest"].to_s.length == 64 &&
               data["write_command"] == "WRITE_KNOWLEDGE_VAULT_NOTE #{data['candidate_id']} #{data['preview_digest']}")

  wrong = service.execute(
    chat_id: "chat_fixture",
    command: "WRITE_KNOWLEDGE_VAULT_NOTE #{data['candidate_id']} #{'0' * 64}"
  )
  other_chat = service.execute(
    chat_id: "chat_other",
    command: data.fetch("write_command")
  )
  check.call("wrong digest and another conversation write nothing",
             wrong["lifecycle_state"] == "blocked_for_human_review" &&
               other_chat["lifecycle_state"] == "blocked_for_human_review" &&
               !File.exist?(destination))

  written = service.execute(chat_id: "chat_fixture", command: data.fetch("write_command"))
  updated_candidate = JSON.parse(File.read(candidate_path))
  check.call("exact command writes only the reviewed note through A1",
             written["lifecycle_state"] == "complete" &&
               File.file?(destination) &&
               File.read(destination).include?("The reviewed Daily Core runs Gemma on AMD") &&
               updated_candidate["status"] == "complete")

  repeated = service.execute(chat_id: "chat_fixture", command: data.fetch("write_command"))
  check.call("completed candidate cannot be executed twice",
             repeated["lifecycle_state"] == "blocked_for_human_review")
end

preference_draft = JSON.generate(
  "preserve" => true,
  "title" => "Operator Music Preference",
  "body" => "The Operator prefers layered technical music.",
  "knowledge_kind" => "preference",
  "tags" => ["music"],
  "rationale" => "This is stable personal context.",
  "uncertainties" => []
)
Dir.mktmpdir("soul-knowledge-a2-preference") do |root|
  _vault, knowledge = initialized_vault(root, clock)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: KnowledgeDraftClient.new(preference_draft),
    knowledge_vault_service: knowledge,
    clock: clock
  )
  outcome = service.create(chat_id: "chat_fixture", messages: messages, provider: provider)
  check.call("non-vault destination creates no isolated pending store",
             outcome["lifecycle_state"] == "complete" &&
               outcome.dig("data", "recommended_destination") == "shared_memory_candidate" &&
               Dir.glob(File.join(root, "Soul/reflection/knowledge_pending/*")).empty?)
end

secret_draft = JSON.generate(
  "preserve" => true,
  "title" => "Deployment Credential",
  "body" => "api_key=sk-abcdefghijklmnopqrstuvwxyz123456",
  "knowledge_kind" => "project",
  "tags" => ["deployment"],
  "rationale" => "The model incorrectly selected a secret.",
  "uncertainties" => []
)
Dir.mktmpdir("soul-knowledge-a2-secret") do |root|
  _vault, knowledge = initialized_vault(root, clock)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: KnowledgeDraftClient.new(secret_draft),
    knowledge_vault_service: knowledge,
    clock: clock
  )
  outcome = service.create(chat_id: "chat_fixture", messages: messages, provider: provider)
  check.call("secret-like model output is never persisted",
             outcome["lifecycle_state"] == "blocked_for_human_review" &&
               outcome.dig("data", "recommended_destination") == "never_store" &&
               Dir.glob(File.join(root, "Soul/reflection/knowledge_pending/*")).empty?)
end

Dir.mktmpdir("soul-knowledge-a2-invalid") do |root|
  _vault, knowledge = initialized_vault(root, clock)
  service = SoulCore::ConversationKnowledgeReflectionService.new(
    root: root,
    provider_client: KnowledgeDraftClient.new("```json\n#{durable_draft}\n```"),
    knowledge_vault_service: knowledge,
    clock: clock
  )
  outcome = service.create(chat_id: "chat_fixture", messages: messages, provider: provider)
  check.call("Markdown-wrapped model JSON fails closed",
             outcome["lifecycle_state"] == "failed" &&
               Dir.glob(File.join(root, "Soul/reflection/knowledge_pending/*")).empty?)
end

control = orchestrator.plan(
  message: "WRITE_KNOWLEDGE_VAULT_NOTE knref_20260724T223000Z_0123456789 #{'a' * 64}",
  provider_available: true
)
check.call("only the exact ID and digest form routes to write control",
           control.kind == "knowledge_reflection_control")

source = File.read(File.join(__dir__, "../lib/soul_core/conversation_knowledge_reflection_service.rb"))
check.call("implementation adds no watcher, service, scheduler, or background loop",
           !source.match?(/\b(Net::HTTP|TCPSocket|inotify|listen|cron|systemctl|Thread\.new|fork)\b/) &&
             source.include?("\"automatic_write\" => false"))

if errors.empty?
  puts "PASS: 17 checks"
  exit 0
end

warn "FAIL: #{errors.length} checks failed: #{errors.join(', ')}"
exit 1
