# frozen_string_literal: true

require "digest"
require "json"
require_relative "application_contract"
require_relative "application_request_receipt_store"

module SoulCore
  class ApplicationChatService
    def initialize(root:, store:, runtime:, receipt_store: nil)
      @root = File.expand_path(root)
      @store = store
      @runtime = runtime
      @receipt_store = receipt_store || ApplicationRequestReceiptStore.new(root: @root)
    end

    def send(chat_id:, message:, request_id:, interface: "internal")
      raise ArgumentError, "invalid application request ID" unless request_id.to_s.match?(ApplicationContract::REQUEST_ID)
      raise ArgumentError, "invalid canonical chat ID" unless chat_id.to_s.match?(ApplicationContract::CHAT_ID)
      chat = @store.chat(chat_id)
      return awaiting("unknown chat ID: #{chat_id}") unless chat

      text = message.to_s
      return awaiting("message is required") if text.strip.empty?
      raise ArgumentError, "message must be valid UTF-8" unless text.valid_encoding?
      raise ArgumentError, "message exceeds #{ApplicationContract::MAX_STRING_BYTES} bytes" if text.bytesize > ApplicationContract::MAX_STRING_BYTES

      digest = Digest::SHA256.hexdigest(JSON.generate({ "chat_id" => chat_id.to_s, "message" => text }))
      reservation = @receipt_store.reserve(
        request_id: request_id,
        operation: "chats.send",
        identity: chat_id,
        input_digest: digest
      )
      case reservation.fetch("status")
      when "replay"
        return replay(reservation.fetch("receipt"))
      when "conflict", "reserved", "failed"
        return blocked("application request ID conflicts with an existing or incomplete chat send") unless reservation.fetch("status") == "reserved"
      end

      user_message = @store.add_message(
        chat_id,
        role: "user",
        content: text,
        metadata: application_metadata(request_id, interface)
      )
      result = @runtime.respond(chat_id: chat_id, message: text)
      assistant_message = @store.add_message(
        chat_id,
        role: "assistant",
        content: result.content,
        metadata: application_metadata(request_id, interface).merge(
          "responder" => "conversational_soul_phase12b",
          "mode" => result.mode,
          "provider_id" => result.provider_id,
          "fallback_reason" => result.fallback_reason,
          "runtime" => result.metadata
        ).reject { |_key, value| value.nil? }
      )
      @receipt_store.complete(
        request_id: request_id,
        user_message_id: user_message.fetch("id"),
        assistant_message_id: assistant_message.fetch("id")
      )
      success(user_message, assistant_message, result, replay: false)
    rescue ArgumentError => error
      safe_fail(request_id, "invalid_input")
      failure(error.message)
    rescue RuntimeError => error
      safe_fail(request_id, "runtime_error")
      blocked(error.message)
    rescue StandardError => error
      safe_fail(request_id, "dependency_failure")
      failure("chat exchange failed safely: #{error.class}")
    end

    private

    def replay(receipt)
      user_message = @store.message(receipt.fetch("identity"), receipt.fetch("user_message_id"))
      assistant_message = @store.message(receipt.fetch("identity"), receipt.fetch("assistant_message_id"))
      return blocked("idempotent chat receipt references unavailable messages") unless user_message && assistant_message

      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "user_message" => user_message,
        "assistant_message" => assistant_message,
        "result" => result_projection(assistant_message),
        "idempotent_replay" => true,
        "mutation" => "none"
      }
    end

    def success(user_message, assistant_message, result, replay:)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "user_message" => user_message,
        "assistant_message" => assistant_message,
        "result" => result.respond_to?(:to_h) ? result.to_h : result,
        "idempotent_replay" => replay,
        "mutation" => "chat_exchange_appended"
      }
    end

    def result_projection(assistant_message)
      metadata = assistant_message.fetch("metadata", {})
      {
        "content" => assistant_message.fetch("content"),
        "mode" => metadata["mode"],
        "provider_id" => metadata["provider_id"],
        "fallback_reason" => metadata["fallback_reason"],
        "metadata" => metadata["runtime"] || {}
      }.compact
    end

    def application_metadata(request_id, interface)
      {
        "application_request_id" => request_id.to_s,
        "application_schema_version" => "soul.application.v1",
        "interface" => interface.to_s
      }
    end

    def safe_fail(request_id, category)
      @receipt_store.fail(request_id: request_id, category: category)
    rescue StandardError
      nil
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none" }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => safe_reason(reason), "mutation" => "none" }
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed", "reason" => safe_reason(reason), "mutation" => "none" }
    end

    def safe_reason(reason)
      reason.to_s.gsub(@root, "[PROJECT_ROOT]").gsub(%r{(?:/[A-Za-z0-9._-]+){2,}}, "[REDACTED_PATH]")[0, 300]
    end
  end
end
