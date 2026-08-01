# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "time"
require "uri"
require_relative "dev_core_task_orchestrator"

module SoulCore
  class LocalDevelopmentModelClient
    DEFAULT_TIMEOUT_SECONDS = 300
    MAX_RESPONSE_BYTES = 512 * 1024
    MODEL = DevModelRuntimeCoordinator::DEFAULT_MODEL

    Response = Struct.new(
      :provider, :model, :status, :http_status, :content, :structured,
      :error_message, :duration_seconds, :runtime_receipt,
      keyword_init: true
    ) do
      def ok? = status == "ok"
      def text = content.to_s
      def to_h
        {
          "provider" => provider, "model" => model, "status" => status,
          "http_status" => http_status, "text_present" => !content.to_s.empty?,
          "structured_output" => structured.is_a?(Hash),
          "error_message" => error_message, "duration_seconds" => duration_seconds,
          "runtime_receipt" => runtime_receipt
        }
      end
    end

    def initialize(root: Dir.pwd, env: ENV, task_orchestrator: nil, http_post: nil)
      @root = File.expand_path(root)
      @task_orchestrator = task_orchestrator || DevCoreTaskOrchestrator.new(root: @root, env: env)
      @http_post = http_post || method(:bounded_http_post)
    end

    def chat(messages:, purpose:, response_schema: nil, temperature: 0.1,
             max_tokens: 4_096, reasoning: true, on_progress: nil, request_id: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      identifier = request_id.to_s.empty? ? "dev_#{SecureRandom.hex(12)}" : request_id.to_s
      result, runtime_receipt = @task_orchestrator.with_task(
        request_id: identifier, purpose: purpose, on_progress: on_progress
      ) do |runtime|
        payload = {
          "model" => runtime.fetch("model"),
          "messages" => normalize_messages(messages),
          "stream" => false,
          "think" => reasoning,
          "keep_alive" => active_core_id == "dev" ? -1 : "30m",
          "options" => {
            "temperature" => Float(temperature).clamp(0.0, 1.0),
            "num_predict" => Integer(max_tokens).clamp(1, 8_192),
            "num_ctx" => 16_384
          }
        }
        payload["format"] = response_schema if response_schema
        @http_post.call(URI.join(runtime.fetch("endpoint") + "/", "api/chat"), payload)
      end

      parsed = JSON.parse(result.fetch(:body).to_s)
      content = parsed.dig("message", "content").to_s.strip
      structured = response_schema ? JSON.parse(content) : nil
      ok = result.fetch(:status).to_i.between?(200, 299) && !content.empty? && (!response_schema || structured.is_a?(Hash))
      Response.new(
        provider: "local.dev", model: MODEL, status: ok ? "ok" : "error",
        http_status: result.fetch(:status).to_i, content: content,
        structured: structured, error_message: ok ? nil : provider_error(parsed, result),
        duration_seconds: elapsed(started), runtime_receipt: runtime_receipt
      )
    rescue DevCoreTaskOrchestrator::Unavailable => error
      failure(error.message, started, lifecycle: error.lifecycle_state, runtime_receipt: error.receipt)
    rescue JSON::ParserError => error
      failure("Dev model returned invalid structured output: #{error.class}", started)
    rescue StandardError => error
      failure("Dev model request failed safely: #{error.class}: #{error.message}", started)
    end

    private

    def normalize_messages(messages)
      values = Array(messages).first(32).map do |message|
        role = message.to_h["role"].to_s
        content = message.to_h["content"].to_s
        raise ArgumentError, "Dev message role is invalid" unless %w[system user assistant].include?(role)
        raise ArgumentError, "Dev message content is empty" if content.empty?
        raise ArgumentError, "Dev message exceeds 128 KiB" if content.bytesize > 128 * 1024
        { "role" => role, "content" => content }
      end
      raise ArgumentError, "Dev request requires at least one message" if values.empty?
      values
    end

    def active_core_id
      path = File.join(@root, "Soul", "runtime", "model_runtime", "core_selection.json")
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 4 * 1024
      JSON.parse(File.binread(path, 4 * 1024))["active_core_id"].to_s
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def bounded_http_post(uri, payload)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = JSON.generate(payload)
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: DEFAULT_TIMEOUT_SECONDS) { |http| http.request(request) }
      { status: response.code.to_i, body: response.body.to_s.byteslice(0, MAX_RESPONSE_BYTES) }
    end

    def provider_error(parsed, result)
      parsed.dig("error") || parsed.dig("message", "error") || "HTTP #{result.fetch(:status)} or empty response"
    end

    def failure(message, started, lifecycle: "failed", runtime_receipt: nil)
      Response.new(
        provider: "local.dev", model: MODEL, status: lifecycle,
        http_status: nil, content: "", structured: nil,
        error_message: message, duration_seconds: elapsed(started), runtime_receipt: runtime_receipt
      )
    end

    def elapsed(started)
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
    end
  end
end
