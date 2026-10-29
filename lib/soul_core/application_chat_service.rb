# frozen_string_literal: true

require "digest"
require "json"
require_relative "application_contract"
require_relative "application_request_receipt_store"
require_relative "conversation_observation_store"
require_relative "chat_cancellation"
require_relative "roster_admission_busy"

module SoulCore
  class ApplicationChatService
    def initialize(root:, store:, runtime:, receipt_store: nil, observation_store: nil, member_runtime: nil, runtime_resolver: nil)
      @root = File.expand_path(root)
      @store = store
      @runtime = runtime
      @member_runtime = member_runtime
      @runtime_resolver = runtime_resolver
      @receipt_store = receipt_store || ApplicationRequestReceiptStore.new(root: @root)
      @observation_store = observation_store || ConversationObservationStore.new(root: @root)
      @active_mutex = Mutex.new
      @active = {}
    end

    def send(chat_id:, message:, request_id:, interface: "internal", progress: nil)
      raise ArgumentError, "invalid application request ID" unless request_id.to_s.match?(ApplicationContract::REQUEST_ID)
      raise ArgumentError, "invalid canonical chat ID" unless chat_id.to_s.match?(ApplicationContract::CHAT_ID)
      chat = @store.chat(chat_id)
      return awaiting("unknown chat ID: #{chat_id}") unless chat
      runtime = chat.dig("metadata", "roster_member") ? @member_runtime : (@runtime || @runtime_resolver&.call)
      return blocked("roster runtime unavailable; no legacy fallback") unless runtime

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
        return blocked("application request ID conflicts with an existing or incomplete chat send") unless reservation["acquired"] == true
      end

      owns_reservation = true
      if runtime.respond_to?(:supports_chat_cancellation?) && runtime.supports_chat_cancellation? == true
        token = ChatCancellation::Token.new
        @active_mutex.synchronize { @active[request_id] = [chat_id, token] }
      end

      progress_sink = request_progress(request_id, progress)
      user_message = @store.add_message(
        chat_id,
        role: "user",
        content: text,
        metadata: application_metadata(request_id, interface)
      )
      emit(progress_sink, "received", "Transmission received and written to local continuity.")
      runtime_options = { chat_id: chat_id, message: text }
      runtime_options[:interface] = interface if runtime_accepts_interface?(runtime)
      runtime_options[:progress] = progress_sink if runtime_accepts_progress?(runtime)
      runtime_options[:cancel] = token if token
      result = runtime.respond(**runtime_options)
      # A runtime returning normally after Stop has not confirmed cancellation.
      # Do not publish its answer or fabricate a successful cleanup receipt.
      raise RuntimeError, "runtime returned after cancellation; inspect retained state" if token&.seal
      emit(progress_sink, "finalizing", "Sealing the response into this transmission.")
      assistant_message = @store.add_message(
        chat_id,
        role: "assistant",
        content: result.content,
        metadata: application_metadata(request_id, interface).merge(
          "responder" => result.provider_id == "deterministic.maintenance" ? "soul_maintenance_workflow" : chat.dig("metadata", "roster_member") ? "soul_roster_member" : "conversational_soul_phase12b",
          "mode" => result.mode,
          "provider_id" => result.provider_id,
          "fallback_reason" => result.fallback_reason,
          "runtime" => result.metadata
        ).reject { |_key, value| value.nil? }
      )
      observation_capture = capture_observations(
        user_message: user_message,
        assistant_message: assistant_message,
        request_id: request_id,
        interface: interface
      )
      @receipt_store.complete(
        request_id: request_id,
        user_message_id: user_message.fetch("id"),
        assistant_message_id: assistant_message.fetch("id")
      )
      emit(progress_sink, "complete", "Response complete.")
      success(user_message, assistant_message, result, replay: false, observation_capture: observation_capture)
    rescue RosterAdmissionBusy
      begin
        raise "unowned busy refusal" unless owns_reservation
        @receipt_store.fail(request_id: request_id, category: "roster_busy_not_admitted")
      rescue StandardError
        return blocked("busy refusal could not be recorded; retained state requires review")
      end
      awaiting(RosterAdmissionBusy::MESSAGE).merge("code"=>"roster_busy", "request_admitted"=>false,
        "mutation"=>"unadmitted_user_message_retained")
    rescue ChatCancellation::Confirmed
      unless token&.call
        safe_fail(request_id, "unexpected_cancellation_confirmation") if owns_reservation
        return blocked("runtime reported cancellation without a matching Stop request")
      end
      safe_fail(request_id, "canceled") if owns_reservation
      { "ok" => false, "lifecycle_state" => "canceled", "reason" => "runtime confirmed cancellation and cleanup", "mutation" => "accepted_exchange_canceled" }
    rescue ArgumentError => error
      safe_fail(request_id, "invalid_input") if owns_reservation
      failure(error.message)
    rescue RuntimeError => error
      safe_fail(request_id, "runtime_error") if owns_reservation
      blocked(error.message)
    rescue StandardError => error
      safe_fail(request_id, "dependency_failure") if owns_reservation
      failure("chat exchange failed safely: #{error.class}")
    ensure
      if token
        token.seal
        @active_mutex.synchronize { @active.delete(request_id) if @active[request_id]&.last.equal?(token) }
      end
    end

    def cancel(chat_id:, target_request_id:)
      raise ArgumentError, "invalid canonical chat ID" unless chat_id.to_s.match?(ApplicationContract::CHAT_ID)
      raise ArgumentError, "invalid target request ID" unless target_request_id.to_s.match?(ApplicationContract::REQUEST_ID)
      accepted = @active_mutex.synchronize do
        entry = @active[target_request_id]
        entry && entry.first == chat_id && entry.last.request
      end
      { "ok" => !!accepted, "lifecycle_state" => accepted ? "complete" : "awaiting_input",
        "data" => { "cancellation_requested" => !!accepted, "generation_stopped" => false },
        "reason" => accepted ? "Stop requested; await runtime cleanup confirmation" : "No matching cancellable request is active",
        "mutation" => accepted ? "chat_cancellation_requested" : "none" }
    rescue ArgumentError => error
      failure(error.message)
    end

    def progress(chat_id: nil, limit: ApplicationRequestReceiptStore::MAX_ACTIVE)
      if chat_id
        raise ArgumentError, "invalid canonical chat ID" unless chat_id.to_s.match?(ApplicationContract::CHAT_ID)
        return awaiting("unknown chat ID: #{chat_id}") unless @store.chat(chat_id)
      end

      records = @receipt_store.active(operation: "chats.send", identity: chat_id, limit: limit)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "data" => {"records" => records, "count" => records.length},
        "mutation" => "none"
      }
    rescue ArgumentError => error
      failure(error.message)
    rescue StandardError => error
      failure("chat progress failed safely: #{error.class}")
    end

    private

    def runtime_accepts_progress?(runtime = @runtime)
      runtime.method(:respond).parameters.any? do |kind, name|
        kind == :keyrest || %i[key keyreq].include?(kind) && name == :progress
      end
    rescue NameError
      false
    end

    def runtime_accepts_interface?(runtime = @runtime)
      runtime.method(:respond).parameters.any? do |kind, name|
        kind == :keyrest || %i[key keyreq].include?(kind) && name == :interface
      end
    rescue NameError
      false
    end

    def request_progress(request_id, external)
      lambda do |event|
        state = event.to_h.fetch("state")
        summary = event.to_h.fetch("summary")
        begin
          @receipt_store.progress(request_id: request_id, state: state, summary: summary)
        rescue StandardError
          nil
        end
        begin
          external&.call({"state" => state, "summary" => summary})
        rescue StandardError
          nil
        end
      end
    end

    def emit(progress, state, summary)
      progress&.call({ "state" => state, "summary" => summary })
    rescue StandardError
      nil
    end

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
        "observation_capture" => capture_observations(
          user_message: user_message,
          assistant_message: assistant_message,
          request_id: receipt.fetch("request_id"),
          interface: user_message.dig("metadata", "interface") || "internal"
        ),
        "idempotent_replay" => true,
        "mutation" => "none"
      }
    end

    def success(user_message, assistant_message, result, replay:, observation_capture:)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "user_message" => user_message,
        "assistant_message" => assistant_message,
        "result" => result.respond_to?(:to_h) ? result.to_h : result,
        "observation_capture" => observation_capture,
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

    def capture_observations(user_message:, assistant_message:, request_id:, interface:)
      @observation_store.capture_exchange(
        user_message: user_message,
        assistant_message: assistant_message,
        request_id: request_id,
        interface: interface
      )
    rescue StandardError => error
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "reason" => "conversation observation capture failed safely: #{error.class}",
        "content_included" => false
      }
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
