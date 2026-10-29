# frozen_string_literal: true

require "digest"
require "openssl"
require_relative "config"

module SoulCore
  module ContinuityLab
    # Pure OpenAI-compatible request adapter. The injected backend owns all
    # conversation identity, history validation, and durable completion work.
    class ChatApplication
      MODEL = "soul-continuity-qwen".freeze
      MAX_BODY_BYTES = 131_072
      MAX_MESSAGE_BYTES = 16_384
      MAX_MESSAGES = 63
      CONVERSATION_ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/.freeze
      Response = Struct.new(:status, :headers, :body, keyword_init: true)

      def initialize(backend:, bearer_token:)
        unless bearer_token.is_a?(String) && bearer_token.bytesize.between?(32, 256) &&
               bearer_token.ascii_only? && bearer_token.match?(/\A[!-~]+\z/)
          raise ValidationError, "invalid bearer token configuration"
        end
        raise ValidationError, "backend must provide complete" unless backend.respond_to?(:complete)

        @backend = backend
        @token_digest = Digest::SHA256.digest(bearer_token).freeze
      end

      def call(method:, target:, headers:, body: nil, cancel: -> { false })
        normalized = normalize_headers(headers)
        return error_response(403, "origin_forbidden", "Cross-origin requests are not supported.") if normalized.key?("origin")
        return error_response(401, "unauthorized", "A valid bearer token is required.") unless authenticated?(normalized["authorization"])

        case [method, target]
        when ["GET", "/v1/models"] then models_response
        when ["GET", "/health"] then health_response
        when ["POST", "/v1/chat/completions"] then completion_response(normalized, body, cancel: cancel)
        else error_response(404, "not_found", "The requested route is not available.")
        end
      rescue ValidationError
        error_response(422, "invalid_request", "The request is invalid. Check the supported text-only chat format and bounds.")
      rescue JSON::ParserError, JSON::NestingError
        error_response(422, "invalid_request", "The request body must be valid, bounded JSON.")
      rescue Conflict
        error_response(409, "history_conflict", "Conversation history conflicts with its saved replies. Restore the exact prior history or start a new conversation.")
      rescue Busy
        error_response(429, "busy", "This conversation cannot be processed right now. Retry after the current operation finishes.")
      rescue QuotaExceeded
        error_response(429, "quota_exceeded", "A configured conversation or request limit was reached.")
      rescue Error
        error_response(503, "continuity_unavailable", "Continuity could not complete this request. Retry only after checking its saved state.")
      rescue StandardError
        error_response(500, "internal_error", "The request could not be completed.")
      end

      private

      def normalize_headers(headers)
        raise ValidationError, "invalid headers" unless headers.is_a?(Hash)
        headers.each_with_object({}) do |(key, value), result|
          raise ValidationError, "invalid header" unless key.is_a?(String) && value.is_a?(String)
          name = key.downcase
          raise ValidationError, "duplicate header" if result.key?(name)
          result[name] = value
        end
      end

      def authenticated?(authorization)
        return false unless authorization.is_a?(String) && authorization.bytesize.between?(39, 263) && authorization.start_with?("Bearer ")

        supplied = authorization.delete_prefix("Bearer ")
        return false unless supplied.bytesize.between?(32, 256) && supplied.ascii_only? && supplied.match?(/\A[!-~]+\z/)

        OpenSSL.fixed_length_secure_compare(@token_digest, Digest::SHA256.digest(supplied))
      end

      def models_response
        json_response(200, { "object" => "list", "data" => supported_models.map { |id| { "id" => id, "object" => "model", "owned_by" => "local" } } })
      end

      def supported_models = [MODEL]
      def completion_model(result) = MODEL
      def generation_parameters = { "max_tokens" => 768, "temperature" => 0.6, "top_p" => 0.95 }
      def valid_temperature?(value) = value.instance_of?(Float) && value == generation_parameters.fetch("temperature")

      def backend_complete(conversation_id, request, messages, cancel)
        @backend.complete(conversation_id: conversation_id, messages: messages)
      end

      def health_response
        json_response(200, { "status" => "available", "backend_health_checked" => false })
      end

      def completion_response(headers, body, cancel:)
        raise ValidationError, "missing conversation identifier" unless headers.key?("x-soul-conversation-id")
        conversation_id = headers.fetch("x-soul-conversation-id")
        unless conversation_id.is_a?(String) && conversation_id.ascii_only? &&
               CONVERSATION_ID.match?(conversation_id) && !%w[new null undefined].include?(conversation_id.downcase)
          raise ValidationError, "invalid conversation identifier"
        end
        raise ValidationError, "invalid body" unless body.is_a?(String)
        request_body = body.dup
        request_body.force_encoding(Encoding::UTF_8) if request_body.encoding == Encoding::ASCII_8BIT
        raise ValidationError, "invalid body" unless request_body.encoding == Encoding::UTF_8 && request_body.valid_encoding?
        raise ValidationError, "body too large" if body.bytesize > MAX_BODY_BYTES

        request = ContinuityLab.parse(request_body)
        messages, stream = validate_completion!(request)
        result = backend_complete(conversation_id, request, messages, cancel)
        validate_backend_result!(result)
        stream ? stream_response(result) : completion_json(result)
      end

      def validate_completion!(request)
        allowed = %w[model messages stream user max_tokens temperature top_p stream_options]
        raise ValidationError, "invalid completion object" unless request.is_a?(Hash) && (request.keys - allowed).empty?
        raise ValidationError, "unsupported model" unless supported_models.include?(request["model"])
        raise ValidationError, "invalid messages" unless request["messages"].is_a?(Array) && request["messages"].length.between?(1, MAX_MESSAGES)
        raise ValidationError, "invalid stream flag" if request.key?("stream") && ![true, false].include?(request["stream"])
        raise ValidationError, "invalid user field" if request.key?("user") && !bounded_text?(request["user"], 256, allow_empty: false)
        if request.key?("max_tokens") && !(request["max_tokens"].instance_of?(Integer) && request["max_tokens"] == generation_parameters.fetch("max_tokens"))
          raise ValidationError, "invalid max_tokens"
        end
        if request.key?("temperature") && !valid_temperature?(request["temperature"])
          raise ValidationError, "invalid temperature"
        end
        if request.key?("top_p") && !(request["top_p"].instance_of?(Float) && request["top_p"] == generation_parameters.fetch("top_p"))
          raise ValidationError, "invalid top_p"
        end
        if request.key?("stream_options")
          options = request["stream_options"]
          raise ValidationError, "invalid stream options" unless options == { "include_usage" => false }
        end

        messages = request.fetch("messages")
        prior_role = "assistant"
        messages.each do |message|
          raise ValidationError, "invalid message" unless message.is_a?(Hash) && message.keys.sort == %w[content role]
          role = message["role"]
          raise ValidationError, "invalid message role" unless %w[user assistant].include?(role)
          raise ValidationError, "messages must alternate" if role == prior_role
          raise ValidationError, "invalid message content" unless bounded_text?(message["content"], MAX_MESSAGE_BYTES, allow_empty: false)
          prior_role = role
        end
        raise ValidationError, "history must end with user" unless prior_role == "user"

        [messages, request.fetch("stream", false)]
      end

      def bounded_text?(value, max_bytes, allow_empty:)
        value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? &&
          (allow_empty || !value.empty?) && value.bytesize <= max_bytes
      end

      def validate_backend_result!(result)
        unless result.is_a?(Hash) && result["id"].is_a?(String) && result["id"].match?(/\Achatcmpl-[A-Za-z0-9_-]{1,128}\z/) &&
               result["created"].is_a?(Integer) && result["content"].is_a?(String) && result["content"].encoding == Encoding::UTF_8 &&
               result["content"].valid_encoding? && result["soul"].is_a?(Hash)
          raise Error, "invalid completion result"
        end
      end

      def completion_json(result)
        json_response(200, {
          "id" => result.fetch("id"), "object" => "chat.completion", "created" => result.fetch("created"),
          "model" => completion_model(result), "choices" => [{ "index" => 0, "message" => { "role" => "assistant", "content" => result.fetch("content") }, "finish_reason" => "stop" }],
          "soul" => result.fetch("soul")
        })
      end

      def stream_response(result)
        id = result.fetch("id")
        base = { "id" => id, "object" => "chat.completion.chunk", "created" => result.fetch("created"), "model" => completion_model(result) }
        frames = []
        frames << sse_frame(base.merge("choices" => [{ "index" => 0, "delta" => { "role" => "assistant" }, "finish_reason" => nil }]))
        frames << sse_frame(base.merge("choices" => [{ "index" => 0, "delta" => { "content" => result.fetch("content") }, "finish_reason" => nil }]))
        frames << sse_frame(base.merge("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }], "soul" => result.fetch("soul")))
        frames << "data: [DONE]\n\n"
        Response.new(status: 200, headers: { "content-type" => "text/event-stream; charset=utf-8", "cache-control" => "no-store", "connection" => "close" }, body: frames.join)
      end

      def sse_frame(data)
        "data: #{JSON.generate(data)}\n\n"
      end

      def error_response(status, code, message)
        json_response(status, { "error" => { "message" => message, "type" => "invalid_request_error", "code" => code } })
      end

      def json_response(status, value)
        Response.new(status: status, headers: { "content-type" => "application/json; charset=utf-8", "cache-control" => "no-store" }, body: JSON.generate(value))
      end
    end
  end
end
