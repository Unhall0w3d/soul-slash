# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "time"

module SoulCore
  # CloudLLMClient is intentionally small. It supports the first serious
  # provider path for cloud-assisted artifacts without pretending to be a
  # universal AI abstraction. Such restraint. In software. Imagine.
  class CloudLLMClient
    DEFAULT_TIMEOUT_SECONDS = 60

    Response = Struct.new(
      :provider,
      :model,
      :status,
      :http_status,
      :text,
      :raw,
      :error_message,
      :duration_seconds,
      keyword_init: true
    ) do
      def ok?
        status == "ok"
      end

      def to_h
        {
          "provider" => provider,
          "model" => model,
          "status" => status,
          "http_status" => http_status,
          "text_present" => !text.to_s.empty?,
          "error_message" => error_message,
          "duration_seconds" => duration_seconds
        }
      end
    end

    def initialize(provider)
      @provider = provider
    end

    def chat(messages:, temperature: 0.2, max_tokens: 1800, model: nil)
      case @provider.name
      when "mistral"
        mistral_chat(messages: messages, temperature: temperature, max_tokens: max_tokens, model: model)
      else
        Response.new(
          provider: @provider.name,
          model: model || @provider.default_model,
          status: "error",
          http_status: nil,
          text: "",
          raw: {},
          error_message: "Provider #{@provider.name} is not implemented by CloudLLMClient.",
          duration_seconds: 0
        )
      end
    end

    private

    def mistral_chat(messages:, temperature:, max_tokens:, model:)
      started = Time.now
      selected_model = model || @provider.default_model

      return config_error("Mistral model is missing.", selected_model, started) if selected_model.to_s.strip.empty?
      return config_error("Mistral base_url is missing.", selected_model, started) if @provider.base_url.to_s.strip.empty?
      return config_error("Mistral api_key_env is missing.", selected_model, started) if @provider.api_key_env.to_s.strip.empty?
      return config_error("Mistral API key environment variable is not present.", selected_model, started) unless @provider.api_key_present?

      uri = URI(join_url(@provider.base_url, "/chat/completions"))
      body = {
        "model" => selected_model,
        "messages" => messages,
        "temperature" => temperature,
        "max_tokens" => max_tokens
      }

      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: DEFAULT_TIMEOUT_SECONDS, open_timeout: DEFAULT_TIMEOUT_SECONDS) do |http|
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{ENV.fetch(@provider.api_key_env)}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(body)
        response = http.request(request)
      end

      parsed = parse_json(response.body)
      text = parsed.dig("choices", 0, "message", "content").to_s.strip
      ok_http = response.code.to_i.between?(200, 299)

      Response.new(
        provider: @provider.name,
        model: selected_model,
        status: ok_http && !text.empty? ? "ok" : "error",
        http_status: response.code.to_i,
        text: text,
        raw: parsed,
        error_message: ok_http ? nil : error_from(parsed, response),
        duration_seconds: (Time.now - started).round(3)
      )
    rescue StandardError => e
      Response.new(
        provider: @provider.name,
        model: selected_model,
        status: "error",
        http_status: nil,
        text: "",
        raw: {},
        error_message: "#{e.class}: #{e.message}",
        duration_seconds: (Time.now - started).round(3)
      )
    end

    def config_error(message, model, started)
      Response.new(
        provider: @provider.name,
        model: model,
        status: "error",
        http_status: nil,
        text: "",
        raw: {},
        error_message: message,
        duration_seconds: (Time.now - started).round(3)
      )
    end

    def join_url(base, suffix)
      base.to_s.sub(%r{/\z}, "") + suffix
    end

    def parse_json(text)
      JSON.parse(text.to_s)
    rescue JSON::ParserError
      {}
    end

    def error_from(parsed, response)
      parsed.dig("message") ||
        parsed.dig("error", "message") ||
        parsed.dig("detail") ||
        "HTTP #{response.code}"
    end
  end
end
