#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "../lib/soul_core/conversation_provider_contract"

Contract = SoulCore::ConversationProviderContract
errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class CapturingProviderClient < SoulCore::ConversationProviderClient
  attr_reader :payloads

  FakeResponse = Struct.new(:code, :body)

  def initialize(root:)
    super(env: {}, root: root)
    @payloads = []
  end

  private

  def post_json(uri, payload, provider:, timeout_seconds:)
    @payloads << {
      "uri" => uri.to_s,
      "payload" => payload,
      "provider" => provider.id,
      "timeout_seconds" => timeout_seconds
    }
    body =
      if provider.transport == "ollama"
        JSON.generate({ "message" => { "content" => "{\"status\":\"ok\"}" }, "done" => true })
      else
        JSON.generate({ "object" => "chat.completion", "choices" => [{ "message" => { "content" => "{\"status\":\"ok\"}" }, "finish_reason" => "stop" }] })
      end
    [FakeResponse.new("200", body), 1.0]
  end
end

def provider(id:, transport:, capabilities:)
  Contract::ProviderDefinition.new(
    id: id,
    label: id,
    transport: transport,
    endpoint: transport == "ollama" ? "http://127.0.0.1:11434" : "http://127.0.0.1:8082/v1",
    model: "test-model",
    privacy_class: "local_only",
    capabilities: capabilities,
    configured: true
  )
end

def envelope(response_format)
  Contract::RequestEnvelope.new(
    conversation_id: "structured-output-test",
    messages: [{ role: "user", content: "Return the requested structure." }],
    model: "test-model",
    temperature: 0.0,
    max_output_tokens: 128,
    response_format: response_format,
    reasoning_mode: "disabled",
    privacy_requirement: "local_only"
  )
end

puts "Soul structured-output provider contract verification:"

schema = {
  type: "json_schema",
  json_schema: {
    name: "status_response",
    schema: {
      type: "object",
      properties: {
        status: { type: "string" },
        executed: { type: "boolean" }
      },
      required: %w[status executed],
      additionalProperties: false
    }
  }
}
valid = envelope(schema)
check("bounded JSON schema request validates", valid.valid?, errors)
check("schema keys are normalized", valid.response_format.dig("json_schema", "schema", "required") == %w[status executed], errors)

invalid_type = envelope(type: "markdown")
check("unsupported response type is rejected", invalid_type.validation_errors.any? { |item| item.include?("unsupported response_format type") }, errors)

external_ref = envelope(type: "json_object", schema: { "$ref" => "https://example.invalid/schema.json" })
check("schema references are rejected", external_ref.validation_errors.any? { |item| item.include?("must not contain $ref") }, errors)

tools_and_schema = Contract::RequestEnvelope.new(
  conversation_id: "structured-output-tools-test",
  messages: [{ role: "user", content: "Choose a tool." }],
  tools: [{ type: "function", function: { name: "status", parameters: { type: "object" } } }],
  response_format: { type: "json_object" }
)
check("tools and structured output cannot be mixed", tools_and_schema.validation_errors.any? { |item| item.include?("cannot be combined") }, errors)

Dir.mktmpdir("soul-structured-output-") do |root|
  openai_client = CapturingProviderClient.new(root: root)
  openai_response = openai_client.chat(
    provider: provider(id: "test.openai", transport: "openai_compatible", capabilities: %w[chat structured_output reasoning_control]),
    request: valid,
    timeout_seconds: 2
  )
  openai_payload = openai_client.payloads.first.fetch("payload")
  check("OpenAI-compatible transport forwards response_format", openai_response.success? && openai_payload["response_format"] == valid.response_format, errors)
  check("OpenAI-compatible structured request disables thinking", openai_payload["chat_template_kwargs"] == { "enable_thinking" => false }, errors)

  ollama_client = CapturingProviderClient.new(root: root)
  ollama_response = ollama_client.chat(
    provider: provider(id: "test.ollama", transport: "ollama", capabilities: %w[chat structured_output reasoning_control]),
    request: valid,
    timeout_seconds: 2
  )
  ollama_payload = ollama_client.payloads.first.fetch("payload")
  check("Ollama transport maps schema to format", ollama_response.success? && ollama_payload["format"] == valid.response_format.dig("json_schema", "schema"), errors)
  check("Ollama structured request disables thinking", ollama_payload["think"] == false, errors)

  unsupported_client = CapturingProviderClient.new(root: root)
  unsupported = unsupported_client.chat(
    provider: provider(id: "test.plain", transport: "openai_compatible", capabilities: %w[chat]),
    request: valid,
    timeout_seconds: 2
  )
  check("undeclared structured-output capability fails before network", !unsupported.success? && unsupported.error["type"] == "unsupported_capability" && unsupported_client.payloads.empty?, errors)

  no_reasoning_client = CapturingProviderClient.new(root: root)
  no_reasoning_control = no_reasoning_client.chat(
    provider: provider(id: "test.no-reasoning", transport: "openai_compatible", capabilities: %w[chat structured_output]),
    request: valid,
    timeout_seconds: 2
  )
  check("undeclared reasoning control fails before network", !no_reasoning_control.success? && no_reasoning_control.error["message"].include?("reasoning_control") && no_reasoning_client.payloads.empty?, errors)
end

if errors.empty?
  puts "Verification complete."
  puts "Structured-output provider contract is candidate-ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
