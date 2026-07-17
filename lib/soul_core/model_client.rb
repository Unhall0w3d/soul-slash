# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module SoulCore
  class ModelClient
    DEFAULT_BASE_URL = "http://127.0.0.1:8082/v1"
    DEFAULT_MODEL = "soul-local-chat"

    def initialize(base_url: ENV.fetch("SOUL_OPENAI_BASE_URL", DEFAULT_BASE_URL),
                   model: ENV.fetch("SOUL_MODEL_ALIAS", DEFAULT_MODEL))
      @base_url = base_url.sub(%r{/?$}, "")
      @model = model
    end

    attr_reader :base_url, :model

    def chat(prompt, mode: :fast, max_tokens: nil, temperature: nil)
      mode = mode.to_sym
      case mode
      when :fast
        prompt = "/no_think\n#{prompt}"
        max_tokens ||= 768
        temperature ||= 0.2
        system = "You are the local Soul/ runtime. Answer plainly and briefly. Do not explain your reasoning."
      when :think
        max_tokens ||= 2048
        temperature ||= 0.4
        system = "You are the local Soul/ runtime. You may reason internally, but your final answer must be concise and useful."
      else
        raise ArgumentError, "unknown mode: #{mode}"
      end

      payload = {
        model: @model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: prompt }
        ],
        max_tokens: max_tokens,
        temperature: temperature
      }

      post_json("#{@base_url}/chat/completions", payload)
    end

    def models
      get_json("#{@base_url}/models")
    end

    private

    def get_json(url)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
      JSON.parse(res.body)
    end

    def post_json(url, payload)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(payload)

      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 120) do |http|
        http.request(req)
      end

      data = JSON.parse(res.body)
      message = data.fetch("choices", [{}])[0].fetch("message", {})
      {
        ok: res.is_a?(Net::HTTPSuccess),
        http_code: res.code.to_i,
        content: message["content"].to_s,
        reasoning_content: message["reasoning_content"].to_s,
        raw: data
      }
    rescue StandardError => e
      {
        ok: false,
        http_code: nil,
        content: "",
        reasoning_content: "",
        error: "#{e.class}: #{e.message}"
      }
    end
  end
end
