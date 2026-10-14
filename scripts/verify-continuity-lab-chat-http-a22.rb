#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/continuity_lab/chat_application"

module VerifyContinuityLabChatHttpA22
  TOKEN = "a22-test-token-with-more-than-thirty-two-bytes".freeze
  ID = "conversation_1".freeze

  class FakeBackend
    attr_reader :calls

    def initialize(result: nil, error: nil)
      @calls = []
      @result = result || { "id" => "chatcmpl-test_1", "created" => 1, "content" => "A reply.", "soul" => { "state" => "complete" } }
      @error = error
    end

    def complete(**arguments)
      @calls << arguments
      raise @error if @error

      @result
    end
  end

  def self.check(condition, label)
    raise "FAIL: #{label}" unless condition

    puts "PASS: #{label}"
  end

  def self.request(app, payload, headers: {}, method: "POST", target: "/v1/chat/completions")
    app.call(method: method, target: target, headers: { "Authorization" => "Bearer #{TOKEN}", "X-Soul-Conversation-ID" => ID }.merge(headers),
             body: payload.is_a?(String) ? payload : JSON.generate(payload))
  end

  def self.payload(messages: [{ "role" => "user", "content" => "Question?" }], **extra)
    { "model" => SoulCore::ContinuityLab::ChatApplication::MODEL, "messages" => messages }.merge(extra)
  end

  def self.status(app, payload, expected, headers: {})
    request(app, payload, headers: headers).status == expected
  end

  def self.run
    lab = SoulCore::ContinuityLab
    backend = FakeBackend.new
    app = lab::ChatApplication.new(backend: backend, bearer_token: TOKEN)

    short_token_rejected = begin
      lab::ChatApplication.new(backend: backend, bearer_token: "x" * 31)
      false
    rescue lab::ValidationError
      true
    end
    check(short_token_rejected, "constructor rejects short bearer token")
    invalid_tokens = ["x" * 257, "x" * 31 + " "]
    check(invalid_tokens.all? do |token|
      begin
        lab::ChatApplication.new(backend: backend, bearer_token: token)
        false
      rescue lab::ValidationError
        true
      end
    end, "constructor rejects long or space-containing bearer tokens")
    unauthorized = app.call(method: "GET", target: "/v1/models", headers: { "authorization" => "Bearer wrong-token" })
    check(unauthorized.status == 401 && !unauthorized.body.include?("wrong-token"), "auth runs before routes without echoing credentials")
    oversized_auth = app.call(method: "GET", target: "/v1/models", headers: { "authorization" => "Bearer #{'x' * 2048}" })
    check(oversized_auth.status == 401, "oversize supplied bearer token is rejected before hashing")
    origin = app.call(method: "GET", target: "/v1/models", headers: { "AUTHORIZATION" => "Bearer #{TOKEN}", "Origin" => "null" })
    check(origin.status == 403 && backend.calls.empty?, "any Origin is rejected before backend")

    models = app.call(method: "GET", target: "/v1/models", headers: { "Authorization" => "Bearer #{TOKEN}" })
    models_data = JSON.parse(models.body)
    check(models.status == 200 && models_data.dig("data", 0, "id") == lab::ChatApplication::MODEL && models_data.dig("data", 0, "owned_by") == "local", "model listing is local and OpenAI shaped")
    health = app.call(method: "GET", target: "/health", headers: { "Authorization" => "Bearer #{TOKEN}" })
    check(health.status == 200 && JSON.parse(health.body)["backend_health_checked"] == false && backend.calls.empty?, "health reports adapter configuration without probing backend")
    check(app.call(method: "GET", target: "/unlisted", headers: { "Authorization" => "Bearer #{TOKEN}" }).status == 404, "unknown route is not exposed")

    before = backend.calls.length
    invalid = [
      [payload(model: "another-model"), 422, "unknown model"],
      [payload(messages: [{ "role" => "system", "content" => "x" }, { "role" => "user", "content" => "y" }]), 422, "system role rejected"],
      [payload(messages: [{ "role" => "user", "content" => "x" }, { "role" => "user", "content" => "y" }]), 422, "nonalternating roles rejected"],
      [payload(messages: [{ "role" => "assistant", "content" => "x" }]), 422, "history ending assistant rejected"],
      [payload(temperature: 0.7), 422, "unsupported temperature rejected"],
      [payload(top_p: 0.5), 422, "unsupported top_p rejected"],
      [payload(max_tokens: 769), 422, "unsupported token limit rejected"],
      [payload(max_tokens: 768.0), 422, "fractional token limit rejected"],
      [payload(stream_options: { "include_usage" => true }), 422, "usage request rejected"],
      [payload(stream_options: { "include_usage" => false, "extra" => false }), 422, "extra stream option rejected"],
      [payload(user: "u" * 257), 422, "oversize user hint rejected"],
      [payload(messages: [{ "role" => "user", "content" => "m" * 16_385 }]), 422, "oversize message rejected"],
      [payload.merge("tools" => []), 422, "tool keys rejected"],
      ["{\"model\":\"soul-continuity-qwen\",\"model\":\"soul-continuity-qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"x\"}]}", 422, "duplicate JSON keys rejected"],
      ["not json", 422, "malformed JSON rejected"]
    ]
    invalid.each { |body, expected, label| check(status(app, body, expected), label) }
    check(backend.calls.length == before, "invalid requests never invoke backend")

    bad_utf8 = "{\"model\":\"soul-continuity-qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"\xFF\"}]}".dup.force_encoding(Encoding::UTF_8)
    check(status(app, bad_utf8, 422), "invalid UTF-8 rejected")
    binary_body = JSON.generate(payload(messages: [{ "role" => "user", "content" => "café ☺" }])).b
    original_binary_body = binary_body.dup
    binary_response = request(app, binary_body)
    check(binary_response.status == 200 && backend.calls.last[:messages].first["content"] == "café ☺" && binary_body == original_binary_body && binary_body.encoding == Encoding::ASCII_8BIT,
          "valid binary encoded UTF-8 JSON is parsed from a private copy")
    invalid_binary_body = "{\"model\":\"soul-continuity-qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"\xFF\"}]}".b
    check(status(app, invalid_binary_body, 422), "invalid UTF-8 bytes in binary body rejected")
    oversized = " " * (lab::ChatApplication::MAX_BODY_BYTES + 1)
    check(status(app, oversized, 422), "body ceiling enforced")
    aggregate = payload(messages: 63.times.map { |i| { "role" => i.even? ? "user" : "assistant", "content" => "x" * 3000 } })
    check(status(app, aggregate, 422), "aggregate body ceiling enforced")
    ["new", "null", "undefined", "bad/id", "x" * 129].each do |conversation_id|
      check(status(app, payload, 422, headers: { "X-Soul-Conversation-ID" => conversation_id }), "invalid conversation identifier #{conversation_id.length} rejected")
    end
    invalid_id_encoding = "\xFF".dup.force_encoding(Encoding::UTF_8)
    check(status(app, payload, 422, headers: { "X-Soul-Conversation-ID" => invalid_id_encoding }), "invalid UTF-8 conversation identifier rejected")
    check(status(app, payload, 422, headers: { "X-Soul-Conversation-ID" => "undefined" }), "reserved placeholder ID rejected")

    backend_error_cases = [
      [lab::ValidationError.new("private validation"), 422, "invalid_request"],
      [lab::Conflict.new("private conflict"), 409, "history_conflict"],
      [lab::Busy.new("private busy"), 429, "busy"],
      [lab::QuotaExceeded.new("private quota"), 429, "quota_exceeded"],
      [lab::IntegrityError.new("private integrity"), 503, "continuity_unavailable"],
      [RuntimeError.new("secret detail"), 500, "internal_error"]
    ]
    backend_error_cases.each do |error, expected, code|
      failing_app = lab::ChatApplication.new(backend: FakeBackend.new(error: error), bearer_token: TOKEN)
      response = request(failing_app, payload)
      check(response.status == expected && JSON.parse(response.body).dig("error", "code") == code && !response.body.include?(error.message), "#{error.class} maps to generic HTTP #{expected}")
    end

    json = request(app, payload(messages: [{ "role" => "user", "content" => "Q" }, { "role" => "assistant", "content" => "A" }, { "role" => "user", "content" => "Next?" }], user: "display label"))
    json_data = JSON.parse(json.body)
    check(json.status == 200 && json_data["object"] == "chat.completion" && json_data.dig("choices", 0, "message", "content") == "A reply." && json_data.dig("soul", "state") == "complete", "JSON completion carries content and separate Soul metadata")
    check(backend.calls.last[:conversation_id] == ID && backend.calls.last[:messages].length == 3 && !backend.calls.last.key?(:user), "backend receives only conversation ID and validated history")

    sse = request(app, payload(stream: true, stream_options: { "include_usage" => false }))
    frames = sse.body.split("\n\n").reject(&:empty?)
    parsed_frames = frames[0...-1].map { |frame| JSON.parse(frame.delete_prefix("data: ")) }
    check(sse.status == 200 && sse.headers["content-type"].start_with?("text/event-stream") && sse.headers["cache-control"] == "no-store" && sse.headers["connection"] == "close", "SSE response is buffered and noncacheable")
    check(frames.last == "data: [DONE]" && parsed_frames.length == 3 && parsed_frames[0].dig("choices", 0, "delta", "role") == "assistant" && parsed_frames[1].dig("choices", 0, "delta", "content") == "A reply." && parsed_frames[2].dig("choices", 0, "finish_reason") == "stop" && parsed_frames[2]["soul"] == { "state" => "complete" }, "SSE includes role, full buffered content, stop, metadata, then DONE")
    check(parsed_frames.none? { |frame| frame.key?("usage") }, "usage is omitted from SSE")

    puts "A22 pure chat HTTP verifier passed."
  end
end

VerifyContinuityLabChatHttpA22.run
