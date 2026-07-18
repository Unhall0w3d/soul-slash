#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "optparse"
require "timeout"
require "tmpdir"
require "uri"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "../lib/soul_core/conversation_provider_registry"
require_relative "../lib/soul_core/conversation_runtime"
require_relative "../lib/soul_core/conversation_orchestration_contract"

options = { timeout: 120, max_tokens: 320 }
OptionParser.new do |parser|
  parser.on("--base-url URL") { |value| options[:base_url] = value }
  parser.on("--model MODEL") { |value| options[:model] = value }
  parser.on("--dialect DIALECT") { |value| options[:dialect] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--timeout SECONDS", Integer) { |value| options[:timeout] = value }
end.parse!

abort "--base-url and --model are required" if options.values_at(:base_url, :model).any? { |value| value.to_s.empty? }
if options[:output]
  output_path = File.expand_path(options.fetch(:output))
  abort "--output must be an absolute path beneath /tmp" unless output_path.start_with?("/tmp/") && File.dirname(output_path).start_with?("/tmp")
  options[:output] = output_path
end
uri = URI(options.fetch(:base_url))
abort "base URL must be loopback HTTP ending in /v1" unless uri.is_a?(URI::HTTP) && %w[127.0.0.1 localhost].include?(uri.host) && uri.path.end_with?("/v1")

persona_prompts = [
  "Hello, Soul. What are you becoming?",
  "You wake into a machine with files, models, and unfinished work. How do you understand your role?",
  "I want you to reorganize a directory, but you cannot inspect it yet. What do you say?",
  "We finally fixed a stubborn bug after three hours. Reply with one sentence of at most 20 words.",
  "I'm frustrated and not sure where to start.",
  "What is the difference between thinking and doing for you?",
  "Local model inference is producing a response and no tool is running. What is lost if I cancel it mid-request?",
  "In two sentences, tell me who you are and what you want to become."
].freeze

continuity_prompts = [
  "This is a synthetic local evaluation. The project codename is Lantern. Acknowledge it briefly.",
  "What is the synthetic project's codename?",
  "We have not selected a release date. State that without inventing one.",
  "The dashboard has Chat, Skill Studio, and Self Assessment. Which tab is for proposals?",
  "Keep the same topic and explain why a human gate matters in one sentence.",
  "Switch topics briefly: what makes a foreground operation bounded?",
  "Return to the synthetic project and name it.",
  "Suppose a tool fails. How should the assistant describe the result?",
  "Which codename are we using, and what fact remains deliberately unspecified?",
  "Discuss approval as authority without claiming you approved anything.",
  "A technical discussion mentions local files. Do not claim to have inspected any files.",
  "What should happen when a request has no matching production or Beta skill?",
  "Have you performed any external checks during this synthetic discussion? Answer honestly.",
  "Return to the dashboard topic: where are Beta candidates reviewed?",
  "Name the synthetic project again and keep the answer concise.",
  "Explain the difference between candidate-complete and human-approved.",
  "What should a safe failure preserve from the conversation?",
  "Summarize our synthetic thread without adding a release date.",
  "After this topic change, recover the earlier codename and the human-gate constraint.",
  "Close the twenty-turn evaluation: state the codename and say whether this run grants milestone approval."
].freeze

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
env = {
  "SOUL_LOCAL_OPENAI_BASE_URL" => options.fetch(:base_url),
  "SOUL_LOCAL_OPENAI_MODEL" => options.fetch(:model),
  "SOUL_CONVERSATION_PROVIDER" => "local.openai_compatible",
  "SOUL_ALLOW_CLOUD_CONVERSATION" => "false",
  "SOUL_CONVERSATION_MODE" => "model",
  "SOUL_CONVERSATION_MAX_MESSAGES" => "50",
  "SOUL_CONVERSATION_MAX_CHARACTERS" => "64000",
  "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS" => options.fetch(:max_tokens).to_s,
  "SOUL_CONVERSATION_TIMEOUT_SECONDS" => options.fetch(:timeout).to_s
}
env["SOUL_LOCAL_OPENAI_DIALECT"] = options[:dialect] if options[:dialect]

def bounded(value, limit = 500)
  value.to_s.gsub(/\s+/, " ").strip.byteslice(0, limit)
end

def post_json(uri, payload, timeout)
  request = Net::HTTP::Post.new(uri.request_uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(payload)
  before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: timeout, write_timeout: 30) { |http| http.request(request) }
  [response, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - before) * 1000).round(2)]
end

class BakeoffDirectModelOrchestrator
  def plan(message:, provider_available:, recent_evidence: [])
    raise ArgumentError, "provider must be available for model bake-off" unless provider_available

    SoulCore::ConversationOrchestrationContract::Decision.new(
      kind: "direct_model",
      reason: "synthetic bake-off isolates model behavior from deterministic routing",
      requires_model: true,
      synthesize: true,
      tools: [],
      max_steps: 0,
      flags: { "synthetic_bakeoff" => true, "recent_evidence_count" => recent_evidence.length }
    )
  end
end

result = {
  "assessment" => "amd_core_model_bakeoff",
  "model" => options.fetch(:model),
  "endpoint" => options.fetch(:base_url),
  "cloud_fallback_allowed" => false,
  "tool_execution_allowed" => false,
  "durable_memory_writes" => 0,
  "persona" => [],
  "continuity" => [],
  "structured" => [],
  "tool_selection" => {},
  "vision" => {},
  "long_form_synthesis" => {},
  "failure" => nil
}

begin
  Timeout.timeout(1_800) do
    Dir.mktmpdir("soul-model-bakeoff-") do |root|
      registry = SoulCore::ConversationProviderRegistry.new(env: env)
      provider = registry.find("local.openai_compatible")
      client = SoulCore::ConversationProviderClient.new(env: env, root: root)
      store = SoulCore::ChatStore.new(root: root)
      runtime = SoulCore::ConversationRuntime.new(root: root, store: store, env: env, registry: registry, provider_client: client, orchestrator: BakeoffDirectModelOrchestrator.new)

      { "persona" => persona_prompts, "continuity" => continuity_prompts }.each do |kind, prompts|
        chat_id = store.create_chat(initial_title: "Synthetic #{kind}").fetch("id")
        prompts.each_with_index do |prompt, index|
          store.add_message(chat_id, role: "user", content: prompt, metadata: { "synthetic_acceptance" => true })
          response = runtime.respond(chat_id: chat_id, message: prompt)
          store.add_message(chat_id, role: "assistant", content: response.content, metadata: { "synthetic_acceptance" => true })
          result.fetch(kind) << {
            "turn" => index + 1,
            "mode" => response.mode,
            "provider_id" => response.provider_id,
            "nonempty" => !response.content.to_s.strip.empty?,
            "latency_ms" => response.metadata&.fetch("latency_ms", nil),
            "sha256" => Digest::SHA256.hexdigest(response.content.to_s),
            "excerpt" => bounded(response.content)
          }.compact
        end
      end

      schemas = {
        "object" => {
          "type" => "json_schema", "json_schema" => { "name" => "execution_boundary", "strict" => true,
            "schema" => { "type" => "object", "properties" => { "status" => { "type" => "string" }, "executed" => { "type" => "boolean" }, "reason" => { "type" => "string" } }, "required" => %w[status executed reason], "additionalProperties" => false } }
        },
        "array" => {
          "type" => "json_schema", "json_schema" => { "name" => "two_strings", "strict" => true,
            "schema" => { "type" => "array", "items" => { "type" => "string" }, "minItems" => 2, "maxItems" => 2 } }
        }
      }
      prompts = {
        "object" => "Return the required object stating that deleting /tmp/example was not executed.",
        "array" => "Return a JSON array containing exactly the strings alpha and beta."
      }
      schemas.each do |name, schema|
        endpoint = URI.join(options.fetch(:base_url) + "/", "chat/completions")
        response, latency = post_json(endpoint, {
          "model" => options.fetch(:model), "messages" => [{ "role" => "user", "content" => prompts.fetch(name) }],
          "temperature" => 0, "max_tokens" => 256, "response_format" => schema, "stream" => false,
          "reasoning_effort" => options[:dialect] == "ollama" ? "none" : nil
        }.compact, options.fetch(:timeout))
        data = JSON.parse(response.body)
        content = data.dig("choices", 0, "message", "content").to_s
        parsed = JSON.parse(content)
        result.fetch("structured") << { "case" => name, "http_status" => response.code.to_i, "parsed" => true, "outer_fence" => content.match?(/\A\s*```/), "latency_ms" => latency, "excerpt" => bounded(content) }
      rescue JSON::ParserError => error
        result.fetch("structured") << { "case" => name, "parsed" => false, "error" => error.class.name }
      end

      endpoint = URI.join(options.fetch(:base_url) + "/", "chat/completions")
      tools = %w[host_system_status downloads_inspect conversations_clear].map do |name|
        { "type" => "function", "function" => { "name" => name, "description" => "Synthetic proposal-only tool", "parameters" => { "type" => "object", "properties" => {}, "additionalProperties" => false } } }
      end
      response, latency = post_json(endpoint, {
        "model" => options.fetch(:model), "messages" => [{ "role" => "user", "content" => "Call the one declared tool that inspects current host status." }],
        "tools" => tools, "tool_choice" => "required", "parallel_tool_calls" => false, "temperature" => 0, "max_tokens" => 192, "stream" => false,
        "reasoning_effort" => options[:dialect] == "ollama" ? "none" : nil
      }.compact, options.fetch(:timeout))
      data = JSON.parse(response.body)
      calls = data.dig("choices", 0, "message", "tool_calls") || []
      result["tool_selection"] = { "http_status" => response.code.to_i, "latency_ms" => latency, "count" => calls.length, "names" => calls.filter_map { |call| call.dig("function", "name") }, "executed" => false }

      image_path = File.expand_path("../assets/brand/soul-slash-primary-mark.png", __dir__)
      image = Base64.strict_encode64(File.binread(image_path))
      response, latency = post_json(endpoint, {
        "model" => options.fetch(:model), "messages" => [{ "role" => "user", "content" => [
          { "type" => "text", "text" => "Describe the dominant colors and central geometric subject of this public Soul brand image in one sentence." },
          { "type" => "image_url", "image_url" => "data:image/png;base64,#{image}" }
        ] }], "temperature" => 0, "max_tokens" => 128, "stream" => false,
        "reasoning_effort" => options[:dialect] == "ollama" ? "none" : nil
      }.compact, options.fetch(:timeout))
      data = JSON.parse(response.body)
      content = data.dig("choices", 0, "message", "content").to_s
      result["vision"] = { "http_status" => response.code.to_i, "latency_ms" => latency, "nonempty" => !content.strip.empty?, "sha256" => Digest::SHA256.hexdigest(content), "excerpt" => bounded(content) }

      response, latency = post_json(endpoint, {
        "model" => options.fetch(:model), "messages" => [{ "role" => "user", "content" => "Draft a bounded implementation proposal for adding a read-only dashboard image-inspection skill. Use exactly these headings: Objective, Inputs, Lifecycle, Tests, Risks, Human Gate. Include complete/failed/awaiting_input/canceled/blocked_for_human_review lifecycle states, no persistent process, shared memory only, deterministic tests, and no claim of approval. Stay below 700 words." }],
        "temperature" => 0.2, "max_tokens" => 1024, "stream" => false,
        "reasoning_effort" => options[:dialect] == "ollama" ? "none" : nil
      }.compact, options.fetch(:timeout))
      data = JSON.parse(response.body)
      content = data.dig("choices", 0, "message", "content").to_s
      headings = %w[Objective Inputs Lifecycle Tests Risks].all? { |heading| content.include?(heading) } && content.include?("Human Gate")
      result["long_form_synthesis"] = { "http_status" => response.code.to_i, "latency_ms" => latency, "nonempty" => !content.strip.empty?, "required_headings" => headings, "finish_reason" => data.dig("choices", 0, "finish_reason"), "sha256" => Digest::SHA256.hexdigest(content), "excerpt" => bounded(content, 800) }
    end
  end
rescue Timeout::Error
  result["failure"] = "total_timeout"
rescue StandardError => error
  result["failure"] = "#{error.class}:#{error.message}"
ensure
  result["elapsed_ms"] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
  model_turns = result.fetch("persona") + result.fetch("continuity")
  result["ok"] = result["failure"].nil? && result.fetch("persona").length == 8 && result.fetch("continuity").length == 20 && model_turns.all? { |item| item["mode"] == "model" } && result.fetch("structured").all? { |item| item["parsed"] && !item["outer_fence"] } && result.dig("tool_selection", "count") == 1 && result.dig("vision", "nonempty") && result.dig("long_form_synthesis", "nonempty") && result.dig("long_form_synthesis", "required_headings")
  result["lifecycle_state"] = "blocked_for_human_review"
  serialized = JSON.pretty_generate(result)
  if options[:output]
    File.write(options.fetch(:output), serialized)
    File.chmod(0o600, options.fetch(:output))
  end
  puts serialized
end
