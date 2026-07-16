# frozen_string_literal: true

require "json"
require "socket"
require "time"
require_relative "conversation_provider_contract"
require_relative "conversation_provider_probe"
require_relative "conversation_provider_registry"

module SoulCore
  class ConversationProviderFoundationAssessor
    Contract = ConversationProviderContract

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      registry = ConversationProviderRegistry.new(env: {})
      providers = registry.providers

      valid_request = Contract::RequestEnvelope.new(
        conversation_id: "phase2-assessment",
        messages: [
          { role: "system", content: "Respond safely." },
          { role: "user", content: "Hello." }
        ],
        model: "test-model",
        temperature: 0.4,
        max_output_tokens: 256,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "phase2_response",
            schema: {
              type: "object",
              properties: { message: { type: "string" } },
              required: ["message"],
              additionalProperties: false
            }
          }
        },
        privacy_requirement: "local_only",
        metadata: { source: "assessment" }
      )

      invalid_request = Contract::RequestEnvelope.new(
        conversation_id: "",
        messages: [],
        temperature: 9.0,
        max_output_tokens: 0,
        response_format: { type: "markdown" },
        privacy_requirement: "unknown"
      )

      response = Contract::ResponseEnvelope.new(
        request_id: valid_request.request_id,
        provider_id: "local.openai_compatible",
        model: "test-model",
        content: "Hello.",
        finish_reason: "stop",
        usage: {
          input_tokens: 4,
          output_tokens: 2
        },
        latency_ms: 12.5
      )

      positive_probe = run_positive_probe
      unavailable_probe = run_unavailable_probe
      timeout_probe = run_timeout_probe

      serialized_registry = JSON.generate(registry.summary)

      blockers = []
      blockers << "Expected three provider definitions" unless providers.length == 3
      blockers << "Missing local OpenAI-compatible provider" unless registry.find("local.openai_compatible")
      blockers << "Missing local Ollama provider" unless registry.find("local.ollama")
      blockers << "Missing disabled cloud provider shape" unless registry.find("cloud.openai_compatible")
      blockers << "Valid request envelope was rejected" unless valid_request.valid?
      blockers << "Invalid request envelope was accepted" if invalid_request.valid?
      blockers << "Structured response format was not preserved" unless valid_request.response_format.dig("json_schema", "schema", "required") == ["message"]
      blockers << "Invalid response format was not rejected" unless invalid_request.validation_errors.any? { |error| error.include?("response_format") }
      blockers << "Response envelope was rejected" unless response.valid? && response.success?
      blockers << "Positive health probe failed" unless positive_probe.available?
      blockers << "Unavailable provider was not reported unavailable" unless unavailable_probe.status == "unavailable"
      blockers << "Slow provider did not time out" unless timeout_probe.status == "timeout"
      blockers << "Registry serialization exposed a credential value" if serialized_registry.include?("phase2-secret-value")

      {
        "ok" => blockers.empty?,
        "assessment" => "conversation_provider_foundation",
        "milestone" => "conversational_soul",
        "phase" => 2,
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "registry" => registry.summary,
        "valid_request" => {
          "valid" => valid_request.valid?,
          "errors" => valid_request.validation_errors,
          "envelope" => valid_request.to_h
        },
        "invalid_request" => {
          "valid" => invalid_request.valid?,
          "errors" => invalid_request.validation_errors
        },
        "response" => {
          "valid" => response.valid?,
          "success" => response.success?,
          "envelope" => response.to_h
        },
        "probes" => {
          "available" => positive_probe.to_h,
          "unavailable" => unavailable_probe.to_h,
          "timeout" => timeout_probe.to_h
        },
        "blockers" => blockers,
        "verification" => {
          "provider_registry_complete" => providers.length == 3,
          "local_openai_shape_present" => !registry.find("local.openai_compatible").nil?,
          "local_ollama_shape_present" => !registry.find("local.ollama").nil?,
          "cloud_shape_present_but_unconfigured" => registry.find("cloud.openai_compatible")&.configured? == false,
          "request_envelope_validates" => valid_request.valid?,
          "invalid_request_rejected" => !invalid_request.valid?,
          "structured_response_format_validates" => valid_request.response_format.dig("json_schema", "schema", "required") == ["message"],
          "invalid_response_format_rejected" => invalid_request.validation_errors.any? { |error| error.include?("response_format") },
          "response_envelope_validates" => response.valid? && response.success?,
          "available_probe_works" => positive_probe.available?,
          "unavailable_probe_works" => unavailable_probe.status == "unavailable",
          "timeout_probe_works" => timeout_probe.status == "timeout",
          "credential_values_not_serialized" => !serialized_registry.include?("phase2-secret-value")
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Conversation Provider Foundation Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Milestone: #{report['milestone']}"
      lines << "Phase: #{report['phase']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Providers"
      report.dig("registry", "providers").each do |provider|
        lines << "- #{provider['id']}"
        lines << "  transport: #{provider['transport']}"
        lines << "  privacy: #{provider['privacy_class']}"
        lines << "  configured: #{provider['configured']}"
      end
      lines << ""
      lines << "Probe checks"
      report.fetch("probes").each do |label, result|
        lines << "- #{label}: #{result['status']}"
      end
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end

    private

    def run_positive_probe
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      thread = Thread.new do
        socket = server.accept
        read_request(socket)
        body = JSON.generate({ object: "list", data: [] })
        socket.write(
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "Content-Length: #{body.bytesize}\r\n" \
          "Connection: close\r\n\r\n" \
          "#{body}"
        )
        socket.close
      rescue IOError, Errno::EBADF, Errno::EPIPE
        nil
      ensure
        socket&.close unless socket&.closed?
      end

      provider = Contract::ProviderDefinition.new(
        id: "assessment.available",
        label: "Assessment available provider",
        transport: "openai_compatible",
        endpoint: "http://127.0.0.1:#{port}/v1",
        model: "test-model",
        privacy_class: "local_only",
        capabilities: %w[chat],
        configured: true
      )

      ConversationProviderProbe.new.probe(provider, timeout_seconds: 0.5)
    ensure
      thread&.join(1)
      server&.close unless server&.closed?
    end

    def run_unavailable_probe
      reservation = TCPServer.new("127.0.0.1", 0)
      port = reservation.addr[1]
      reservation.close

      provider = Contract::ProviderDefinition.new(
        id: "assessment.unavailable",
        label: "Assessment unavailable provider",
        transport: "openai_compatible",
        endpoint: "http://127.0.0.1:#{port}/v1",
        model: "test-model",
        privacy_class: "local_only",
        capabilities: %w[chat],
        configured: true
      )

      ConversationProviderProbe.new.probe(provider, timeout_seconds: 0.1)
    end

    def run_timeout_probe
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      thread = Thread.new do
        socket = server.accept
        read_request(socket)
        sleep 0.2
      rescue IOError, Errno::EBADF, Errno::EPIPE
        nil
      ensure
        socket&.close unless socket&.closed?
      end

      provider = Contract::ProviderDefinition.new(
        id: "assessment.timeout",
        label: "Assessment timeout provider",
        transport: "ollama",
        endpoint: "http://127.0.0.1:#{port}",
        model: "test-model",
        privacy_class: "local_only",
        capabilities: %w[chat],
        configured: true
      )

      ConversationProviderProbe.new.probe(provider, timeout_seconds: 0.05)
    ensure
      thread&.join(1)
      server&.close unless server&.closed?
    end

    def read_request(socket)
      while (line = socket.gets)
        break if line == "\r\n"
      end
    end
  end
end
