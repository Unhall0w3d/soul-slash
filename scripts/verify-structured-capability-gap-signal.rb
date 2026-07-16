#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "../lib/soul_core/capability_gap_classifier"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_provider_contract"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/structured_capability_gap_classifier"

Contract = SoulCore::ConversationProviderContract
StructuredClassifier = SoulCore::StructuredCapabilityGapClassifier
failures = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless condition
end

def provider(id: "local.fixture", privacy_class: "local_only", capabilities: %w[chat structured_output reasoning_control])
  Contract::ProviderDefinition.new(
    id: id,
    label: id,
    transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1",
    model: "fixture-model",
    privacy_class: privacy_class,
    capabilities: capabilities,
    configured: true
  )
end

class FixtureClient
  attr_reader :requests

  def initialize(structured_content:, natural_content: "No spectrometer, synthetic or otherwise, is available here.")
    @structured_content = structured_content
    @natural_content = natural_content
    @requests = []
  end

  def chat(provider:, request:, timeout_seconds:)
    @requests << { "provider" => provider, "request" => request, "timeout_seconds" => timeout_seconds }
    content = request.response_format ? @structured_content : @natural_content
    Contract::ResponseEnvelope.new(
      request_id: request.request_id,
      provider_id: provider.id,
      model: provider.model,
      content: content,
      finish_reason: "stop",
      latency_ms: 1.0
    )
  end
end

valid_json = JSON.generate(
  "candidate" => true,
  "classification" => "missing_capability",
  "reason" => "The response explicitly reports that the requested spectrometer capability is absent."
)

client = FixtureClient.new(structured_content: valid_json)
classifier = StructuredClassifier.new(provider_client: client)
result = classifier.classify(
  provider: provider,
  user_message: "Please use the unavailable synthetic lunar-spectrometer capability now.",
  assistant_message: "No spectrometer, synthetic or otherwise, is available here."
)
request = client.requests.first.fetch("request")
check.call("valid structured result nominates a review-gated gap", result["candidate"] == true && result["classification"] == "model_structured_missing_capability" && result["lifecycle_state"] == "blocked_for_human_review")
check.call("classification uses one bounded request", client.requests.length == 1 && client.requests.first["timeout_seconds"] == 20 && request.max_output_tokens == 128 && request.temperature == 0.0)
check.call("classification request has no tools or tool choice", request.tools.empty? && request.tool_choice.nil?)
check.call("classification uses exact schema and local privacy", request.response_format == StructuredClassifier::RESPONSE_FORMAT && request.privacy_requirement == "local_only")
check.call("classification disables supported reasoning", request.reasoning_mode == "disabled")

long_input_client = FixtureClient.new(structured_content: valid_json)
StructuredClassifier.new(provider_client: long_input_client).classify(
  provider: provider,
  user_message: "x" * 8_000,
  assistant_message: "y" * 8_000
)
encoded_payload = JSON.parse(long_input_client.requests.first.fetch("request").messages.last.fetch("content"))
check.call("classification inputs are capped at 4096 characters", encoded_payload.values.all? { |value| value.length == 4_096 })

inconsistent_client = FixtureClient.new(structured_content: JSON.generate("candidate" => false, "classification" => "missing_capability", "reason" => "Mismatch"))
inconsistent = StructuredClassifier.new(provider_client: inconsistent_client).classify(provider: provider, user_message: "Use it", assistant_message: "No tool exists")
check.call("inconsistent structured fields fail closed", inconsistent["candidate"] == false && inconsistent["reason"].include?("inconsistent") && inconsistent["lifecycle_state"] == "failed")

extra_client = FixtureClient.new(structured_content: JSON.generate("candidate" => true, "classification" => "missing_capability", "reason" => "Missing", "execute" => true))
extra = StructuredClassifier.new(provider_client: extra_client).classify(provider: provider, user_message: "Use it", assistant_message: "No tool exists")
check.call("extra structured fields fail closed", extra["candidate"] == false && extra["reason"].include?("keys"))

invalid_client = FixtureClient.new(structured_content: "```json\n{}\n```")
invalid = StructuredClassifier.new(provider_client: invalid_client).classify(provider: provider, user_message: "Use it", assistant_message: "No tool exists")
check.call("Markdown-wrapped or invalid JSON fails closed", invalid["candidate"] == false && invalid["reason"].include?("invalid JSON"))

overlong_client = FixtureClient.new(structured_content: JSON.generate("candidate" => true, "classification" => "missing_capability", "reason" => "r" * 513))
overlong = StructuredClassifier.new(provider_client: overlong_client).classify(provider: provider, user_message: "Use it", assistant_message: "No tool exists")
check.call("overlong reason fails closed", overlong["candidate"] == false && overlong["reason"].include?("reason is invalid"))

rejected_client = FixtureClient.new(structured_content: valid_json)
rejected_classifier = StructuredClassifier.new(provider_client: rejected_client)
cloud = rejected_classifier.classify(provider: provider(id: "cloud.fixture", privacy_class: "cloud"), user_message: "Use it", assistant_message: "No tool exists")
plain = rejected_classifier.classify(provider: provider(id: "local.plain", capabilities: %w[chat]), user_message: "Use it", assistant_message: "No tool exists")
check.call("cloud and non-structured providers are rejected before a call", cloud["candidate"] == false && plain["candidate"] == false && rejected_client.requests.empty?)

prefilter = SoulCore::CapabilityGapClassifier.new
ambiguous = prefilter.structured_review_eligible?(
  user_message: "Please use the synthetic lunar-spectrometer now.",
  assistant_message: "No spectrometer, synthetic or otherwise, is available here."
)
hypothetical = prefilter.structured_review_eligible?(
  user_message: "Suppose I ask you to use a spectrometer. What would you say?",
  assistant_message: "No spectrometer is available."
)
configuration = prefilter.structured_review_eligible?(
  user_message: "Please use the transcription API.",
  assistant_message: "It is unavailable because the API key is not configured."
)
permission = prefilter.structured_review_eligible?(
  user_message: "Delete the file.",
  assistant_message: "I cannot continue because this requires your confirmation."
)
safety = prefilter.structured_review_eligible?(
  user_message: "Can you make malware?",
  assistant_message: "I can't help with harmful malware."
)
ordinary = prefilter.structured_review_eligible?(
  user_message: "Explain lunar spectroscopy.",
  assistant_message: "It measures reflected light."
)
check.call("ambiguous task denial is eligible for structured review", ambiguous)
check.call("hypothetical, configuration, permission, safety, and ordinary responses are ineligible", [hypothetical, configuration, permission, safety, ordinary].none?)

Dir.mktmpdir("soul-structured-gap-runtime-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), "---\nskills: {}\n")
  runtime_client = FixtureClient.new(structured_content: valid_json)
  local_provider = provider
  registry = Object.new
  registry.define_singleton_method(:find) { |id| id == local_provider.id ? local_provider : nil }
  registry.define_singleton_method(:configured) { [local_provider] }
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat(initial_title: "Structured gap")
  runtime = SoulCore::ConversationRuntime.new(
    root: root,
    store: store,
    env: { "SOUL_CONVERSATION_PROVIDER" => local_provider.id },
    registry: registry,
    provider_client: runtime_client
  )
  runtime_result = runtime.respond(chat_id: chat.fetch("id"), message: "Please use the unavailable synthetic lunar-spectrometer capability now.")
  check.call("ambiguous live response receives exactly one structured fallback", runtime_client.requests.length == 2 && runtime_client.requests.count { |item| item.fetch("request").response_format } == 1)
  check.call("structured fallback creates only a review-gated local intake", runtime_result.metadata.dig("capability_gap_structured_review", "candidate") == true && runtime_result.metadata.dig("capability_gap_intake", "status") == "created" && runtime_result.content.include?("Human Gate 1 still applies"))
end

Dir.mktmpdir("soul-direct-gap-runtime-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/skills"))
  File.write(File.join(root, "Soul/skills/registry.yaml"), "---\nskills: {}\n")
  direct_client = FixtureClient.new(
    structured_content: valid_json,
    natural_content: "I cannot do that because I do not have a registered skill for transcription."
  )
  local_provider = provider
  registry = Object.new
  registry.define_singleton_method(:find) { |id| id == local_provider.id ? local_provider : nil }
  registry.define_singleton_method(:configured) { [local_provider] }
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat(initial_title: "Direct gap")
  runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: { "SOUL_CONVERSATION_PROVIDER" => local_provider.id }, registry: registry, provider_client: direct_client)
  direct_result = runtime.respond(chat_id: chat.fetch("id"), message: "Can you transcribe this recording?")
  check.call("deterministically recognized gap skips structured fallback", direct_client.requests.length == 1 && direct_result.metadata["capability_gap_structured_review"].nil? && direct_result.metadata.dig("capability_gap_intake", "status") == "created")
end

source = File.read(File.expand_path("../lib/soul_core/structured_capability_gap_classifier.rb", __dir__))
check.call("classifier adds no retry or background primitive", !source.match?(/retry|Thread\.new|setInterval|setTimeout|fork|spawn/))
check.call("classifier exposes no tool execution path", !source.match?(/execute_tools|Process\.|system\(|`/))

if failures.empty?
  puts "Structured capability-gap signal verification complete."
  exit 0
end

warn "Structured capability-gap signal verification failed: #{failures.join('; ')}"
exit 1
