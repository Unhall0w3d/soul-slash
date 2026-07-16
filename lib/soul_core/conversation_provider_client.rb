# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "conversation_provider_contract"
require_relative "model_runtime_lease_store"

module SoulCore
  class ConversationProviderClient
    Contract = ConversationProviderContract

    def initialize(env: ENV, root: Dir.pwd, lease_store: nil)
      @env = env
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: root)
    end

    def chat(provider:, request:, timeout_seconds: 120)
      validation_errors = request.validation_errors
      unless validation_errors.empty?
        return error_response(
          provider: provider,
          request: request,
          type: "invalid_request",
          message: validation_errors.join("; ")
        )
      end

      if request.response_format && !provider.supports?("structured_output")
        return error_response(
          provider: provider,
          request: request,
          type: "unsupported_capability",
          message: "Provider #{provider.id} does not declare structured_output support"
        )
      end

      if !request.tools.empty? && !provider.supports?("tools")
        return error_response(
          provider: provider,
          request: request,
          type: "unsupported_capability",
          message: "Provider #{provider.id} does not declare tools support"
        )
      end

      if request.reasoning_mode == "disabled" && !provider.supports?("reasoning_control")
        return error_response(
          provider: provider,
          request: request,
          type: "unsupported_capability",
          message: "Provider #{provider.id} does not declare reasoning_control support"
        )
      end

      with_runtime_lease(provider, request, timeout_seconds) do
        case provider.transport
        when "openai_compatible"
          openai_chat(provider, request, timeout_seconds)
        when "ollama"
          ollama_chat(provider, request, timeout_seconds)
        else
          error_response(
            provider: provider,
            request: request,
            type: "unsupported_transport",
            message: "Unsupported provider transport: #{provider.transport}"
          )
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => error
      error_response(
        provider: provider,
        request: request,
        type: "timeout",
        message: "#{error.class}: #{error.message}"
      )
    rescue JSON::ParserError => error
      error_response(
        provider: provider,
        request: request,
        type: "invalid_response",
        message: "#{error.class}: #{error.message}"
      )
    rescue StandardError => error
      error_response(
        provider: provider,
        request: request,
        type: "provider_failure",
        message: "#{error.class}: #{error.message}"
      )
    end

    private

    def with_runtime_lease(provider, request, timeout_seconds, &block)
      return yield unless %w[local_only local_network].include?(provider.privacy_class)

      @lease_store.with_lease(
        provider_id: provider.id,
        model_id: request.model.to_s.empty? ? provider.model : request.model,
        request_id: request.request_id,
        conversation_id: request.conversation_id,
        timeout_seconds: timeout_seconds,
        &block
      )
    end

    def openai_chat(provider, request, timeout_seconds)
      uri = endpoint_uri(provider, "chat/completions")
      payload = {
        "model" => request.model.to_s.empty? ? provider.model : request.model,
        "messages" => request.messages,
        "temperature" => request.temperature,
        "max_tokens" => request.max_output_tokens
      }.reject { |_key, value| value.nil? }

      payload["tools"] = request.tools unless request.tools.empty?
      payload["tool_choice"] = request.tool_choice if request.tool_choice
      payload["parallel_tool_calls"] = false if request.tool_choice == "required"
      payload["response_format"] = request.response_format if request.response_format
      if request.reasoning_mode == "disabled"
        payload["chat_template_kwargs"] = { "enable_thinking" => false }
      end

      response, latency_ms = post_json(
        uri,
        payload,
        provider: provider,
        timeout_seconds: timeout_seconds
      )
      data = JSON.parse(response.body)
      message = data.fetch("choices", [{}]).first.fetch("message", {})

      normalized_response(
        provider: provider,
        request: request,
        response: response,
        latency_ms: latency_ms,
        content: message["content"].to_s,
        finish_reason: data.fetch("choices", [{}]).first["finish_reason"],
        usage: data["usage"] || {},
        tool_calls: message["tool_calls"] || [],
        raw_metadata: {
          "transport" => provider.transport,
          "response_object" => data["object"]
        }
      )
    end

    def ollama_chat(provider, request, timeout_seconds)
      uri = endpoint_uri(provider, "api/chat", force_root: true)
      payload = {
        "model" => request.model.to_s.empty? ? provider.model : request.model,
        "messages" => request.messages,
        "stream" => false,
        "options" => {
          "temperature" => request.temperature,
          "num_predict" => request.max_output_tokens
        }.reject { |_key, value| value.nil? }
      }
      if request.response_format
        format = ollama_response_format(request.response_format)
        payload["format"] = format if format
      end
      payload["think"] = false if request.reasoning_mode == "disabled"

      response, latency_ms = post_json(
        uri,
        payload,
        provider: provider,
        timeout_seconds: timeout_seconds
      )
      data = JSON.parse(response.body)
      message = data["message"] || {}

      normalized_response(
        provider: provider,
        request: request,
        response: response,
        latency_ms: latency_ms,
        content: message["content"].to_s,
        finish_reason: data["done_reason"] || (data["done"] ? "stop" : nil),
        usage: {
          "input_tokens" => data["prompt_eval_count"],
          "output_tokens" => data["eval_count"]
        }.reject { |_key, value| value.nil? },
        tool_calls: message["tool_calls"] || [],
        raw_metadata: {
          "transport" => provider.transport,
          "done" => data["done"]
        }
      )
    end

    def post_json(uri, payload, provider:, timeout_seconds:)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      apply_credential(request, provider)
      request.body = JSON.generate(payload)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.is_a?(URI::HTTPS),
        open_timeout: [timeout_seconds.to_f, 10.0].min,
        read_timeout: timeout_seconds.to_f,
        write_timeout: [timeout_seconds.to_f, 30.0].min
      ) do |http|
        http.request(request)
      end
      latency_ms = (
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      ).round(2)

      [response, latency_ms]
    end

    def ollama_response_format(response_format)
      case response_format.fetch("type")
      when "json_object"
        response_format["schema"] || "json"
      when "json_schema"
        response_format.fetch("json_schema").fetch("schema")
      when "text"
        nil
      end
    end

    def normalized_response(
      provider:,
      request:,
      response:,
      latency_ms:,
      content:,
      finish_reason:,
      usage:,
      tool_calls:,
      raw_metadata:
    )
      error =
        unless response.code.to_i.between?(200, 299)
          {
            "type" => "http_error",
            "http_status" => response.code.to_i,
            "message" => "Provider returned HTTP #{response.code}"
          }
        end

      Contract::ResponseEnvelope.new(
        request_id: request.request_id,
        provider_id: provider.id,
        model: request.model.to_s.empty? ? provider.model : request.model,
        content: content,
        finish_reason: finish_reason,
        usage: usage,
        tool_calls: tool_calls,
        latency_ms: latency_ms,
        error: error,
        metadata: raw_metadata.merge("http_status" => response.code.to_i)
      )
    end

    def error_response(provider:, request:, type:, message:)
      Contract::ResponseEnvelope.new(
        request_id: request.request_id,
        provider_id: provider.id,
        model: request.model.to_s.empty? ? provider.model : request.model,
        content: "",
        error: {
          "type" => type,
          "message" => message
        },
        metadata: {
          "transport" => provider.transport
        }
      )
    end

    def endpoint_uri(provider, suffix, force_root: false)
      base = URI.parse(provider.endpoint)
      raise ArgumentError, "Provider endpoint must use HTTP or HTTPS" unless base.is_a?(URI::HTTP)

      path = base.path.to_s.sub(%r{/+\z}, "")
      path = "" if force_root

      if suffix == "chat/completions"
        path =
          if path.end_with?("/chat/completions")
            path
          elsif path.end_with?("/v1")
            "#{path}/chat/completions"
          elsif path.empty?
            "/v1/chat/completions"
          else
            "#{path}/v1/chat/completions"
          end
      else
        path = "/#{suffix.sub(%r{\A/+}, '')}"
      end

      uri = base.dup
      uri.path = path
      uri.query = nil
      uri.fragment = nil
      uri
    end

    def apply_credential(request, provider)
      return if provider.credential_env.to_s.empty?

      credential = @env[provider.credential_env].to_s
      request["Authorization"] = "Bearer #{credential}" unless credential.empty?
    end
  end
end
