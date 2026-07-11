# frozen_string_literal: true

require "json"
require "net/http"
require "time"
require "uri"

module SoulCore
  class ConversationProviderProbe
    Result = Struct.new(
      :provider_id,
      :status,
      :available,
      :endpoint,
      :probe_uri,
      :http_status,
      :latency_ms,
      :error_class,
      :error_message,
      :checked_at,
      keyword_init: true
    ) do
      def available?
        available == true
      end

      def to_h
        {
          "provider_id" => provider_id,
          "status" => status,
          "available" => available?,
          "endpoint" => endpoint,
          "probe_uri" => probe_uri,
          "http_status" => http_status,
          "latency_ms" => latency_ms,
          "error_class" => error_class,
          "error_message" => error_message,
          "checked_at" => checked_at
        }.reject { |_key, value| value.nil? }
      end
    end

    def initialize(
      env: ENV,
      clock: -> { Time.now },
      monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @env = env
      @clock = clock
      @monotonic_clock = monotonic_clock
    end

    def probe(provider, timeout_seconds: 2.0)
      return misconfigured(provider, "provider endpoint is not configured") if provider.endpoint.to_s.empty?
      return misconfigured(provider, "provider model is not configured") if provider.model.to_s.empty?

      uri = build_probe_uri(provider)
      started = @monotonic_clock.call
      request = Net::HTTP::Get.new(uri.request_uri)
      apply_credential(request, provider)

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.is_a?(URI::HTTPS),
        open_timeout: timeout_seconds,
        read_timeout: timeout_seconds,
        write_timeout: timeout_seconds
      ) do |http|
        http.request(request)
      end

      latency = elapsed_ms(started)
      available = response.code.to_i.between?(200, 299)

      Result.new(
        provider_id: provider.id,
        status: available ? "available" : "unhealthy",
        available: available,
        endpoint: provider.endpoint,
        probe_uri: uri.to_s,
        http_status: response.code.to_i,
        latency_ms: latency,
        checked_at: @clock.call.iso8601
      )
    rescue URI::InvalidURIError, ArgumentError => error
      failure(provider, "misconfigured", error, started)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => error
      failure(provider, "timeout", error, started)
    rescue StandardError => error
      failure(provider, "unavailable", error, started)
    end

    private

    def build_probe_uri(provider)
      base = URI.parse(provider.endpoint)

      unless base.is_a?(URI::HTTP)
        raise ArgumentError, "provider endpoint must use http or https"
      end

      uri = base.dup
      uri.path =
        case provider.transport
        when "openai_compatible"
          openai_models_path(base.path)
        when "ollama"
          "/api/tags"
        else
          raise ArgumentError, "unsupported provider transport: #{provider.transport}"
        end
      uri.query = nil
      uri.fragment = nil
      uri
    end

    def openai_models_path(path)
      normalized = path.to_s.sub(%r{/+\z}, "")
      return "/v1/models" if normalized.empty? || normalized == "/"
      return "#{normalized}/models" if normalized.end_with?("/v1")
      return normalized if normalized.end_with?("/models")

      "#{normalized}/v1/models"
    end

    def apply_credential(request, provider)
      return if provider.credential_env.to_s.empty?

      credential = @env[provider.credential_env].to_s
      request["Authorization"] = "Bearer #{credential}" unless credential.empty?
    end

    def elapsed_ms(started)
      return nil unless started

      ((@monotonic_clock.call - started) * 1000).round(2)
    end

    def misconfigured(provider, message)
      Result.new(
        provider_id: provider.id,
        status: "misconfigured",
        available: false,
        endpoint: provider.endpoint,
        error_message: message,
        checked_at: @clock.call.iso8601
      )
    end

    def failure(provider, status, error, started)
      Result.new(
        provider_id: provider.id,
        status: status,
        available: false,
        endpoint: provider.endpoint,
        latency_ms: elapsed_ms(started),
        error_class: error.class.name,
        error_message: error.message,
        checked_at: @clock.call.iso8601
      )
    end
  end
end
