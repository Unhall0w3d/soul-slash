#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
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

  def initialize(root:, env: {})
    super(env: env, root: root)
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

required_tool = Contract::RequestEnvelope.new(
  conversation_id: "required-tool-test",
  messages: [{ role: "user", content: "Choose one tool." }],
  tools: [{ type: "function", function: { name: "status", parameters: { type: "object" } } }],
  tool_choice: "required"
)
check("required tool choice validates with declared tools", required_tool.valid?, errors)
check("tool choice is preserved by the request contract", required_tool.to_h["tool_choice"] == "required", errors)
check("tool choice without tools is rejected", Contract::RequestEnvelope.new(conversation_id: "missing-tools", messages: [{ role: "user", content: "Choose." }], tool_choice: "required").validation_errors.any? { |item| item.include?("requires at least one") }, errors)
check("unsupported tool choice is rejected", Contract::RequestEnvelope.new(conversation_id: "bad-choice", messages: [{ role: "user", content: "Choose." }], tools: required_tool.tools, tool_choice: "sometimes").validation_errors.any? { |item| item.include?("unsupported tool_choice") }, errors)

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

  ollama_openai_client = CapturingProviderClient.new(root: root, env: { "SOUL_LOCAL_OPENAI_DIALECT" => "ollama" })
  ollama_openai_response = ollama_openai_client.chat(
    provider: provider(id: "test.ollama-openai", transport: "openai_compatible", capabilities: %w[chat structured_output reasoning_control]),
    request: valid,
    timeout_seconds: 2
  )
  ollama_openai_payload = ollama_openai_client.payloads.first.fetch("payload")
  check("Ollama OpenAI dialect uses documented no-reasoning control", ollama_openai_response.success? && ollama_openai_payload["reasoning_effort"] == "none" && !ollama_openai_payload.key?("chat_template_kwargs"), errors)

  ollama_default_request = Contract::RequestEnvelope.new(
    conversation_id: "ollama-default-reasoning-test",
    messages: [{ role: "user", content: "Reply briefly." }],
    max_output_tokens: 64
  )
  ollama_default_client = CapturingProviderClient.new(root: root, env: { "SOUL_LOCAL_OPENAI_DIALECT" => "ollama" })
  ollama_default_client.chat(
    provider: provider(id: "test.ollama-default", transport: "openai_compatible", capabilities: %w[chat reasoning_control]),
    request: ollama_default_request,
    timeout_seconds: 2
  )
  check("Ollama OpenAI dialect keeps ordinary bounded chat out of hidden reasoning", ollama_default_client.payloads.first.dig("payload", "reasoning_effort") == "none", errors)

  FileUtils.mkdir_p(File.join(root, "Soul/config"))
  File.write(File.join(root, "Soul/config/profiles.yaml"), <<~YAML)
    schema_version: soul.model_runtime_profiles.v3
    default_profile: local-llama
    profiles:
      - id: local-llama
        label: Local llama
        model_name: Test llama
        api_model: test-model
        runtime: llamacpp_openai
        accelerator: Test GPU
        service: soul-local-llama.service
        endpoint: http://127.0.0.1:8082/v1
        core_role: daily-chat
      - id: local-ollama
        label: Local Ollama
        model_name: Test Gemma
        api_model: test-model
        runtime: ollama_openai
        accelerator: Test GPU
        service: soul-local-ollama.service
        endpoint: http://127.0.0.1:8082/v1
        core_role: daily-chat
  YAML
  FileUtils.mkdir_p(File.join(root, "Soul/runtime/model_runtime"))
  File.write(File.join(root, "Soul/runtime/model_runtime/selected_profile.json"), JSON.generate("profile_id" => "local-ollama"))
  auto_client = CapturingProviderClient.new(root: root, env: { "SOUL_LOCAL_OPENAI_DIALECT" => "auto", "SOUL_MODEL_RUNTIME_PROFILES_FILE" => "Soul/config/profiles.yaml" })
  auto_client.chat(provider: provider(id: "local.openai_compatible", transport: "openai_compatible", capabilities: %w[chat structured_output reasoning_control]), request: valid, timeout_seconds: 2)
  check("auto dialect follows the reviewed selected Ollama profile", auto_client.payloads.first.dig("payload", "reasoning_effort") == "none" && !auto_client.payloads.first.dig("payload").key?("chat_template_kwargs"), errors)

  tool_client = CapturingProviderClient.new(root: root)
  tool_response = tool_client.chat(
    provider: provider(id: "test.tools", transport: "openai_compatible", capabilities: %w[chat tools]),
    request: required_tool,
    timeout_seconds: 2
  )
  tool_payload = tool_client.payloads.first.fetch("payload")
  check("OpenAI-compatible transport forwards required tool choice", tool_response.success? && tool_payload["tool_choice"] == "required", errors)
  check("required tool selection disables parallel calls", tool_payload["parallel_tool_calls"] == false, errors)

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

  unsupported_tools_client = CapturingProviderClient.new(root: root)
  unsupported_tools = unsupported_tools_client.chat(
    provider: provider(id: "test.no-tools", transport: "openai_compatible", capabilities: %w[chat]),
    request: required_tool,
    timeout_seconds: 2
  )
  check("undeclared tools capability fails before network", !unsupported_tools.success? && unsupported_tools.error["type"] == "unsupported_capability" && unsupported_tools_client.payloads.empty?, errors)

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
