# frozen_string_literal: true
require "thread"
require_relative "roster_admission_busy"

module SoulCore
  # Ephemeral transport acknowledgment, never journal authority. Restart loses
  # these receipts: absence means unknown, not canceled or safe to retry.
  class RosterRequestControl
    ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
    LIMIT = 64

    def initialize
      @mutex = Mutex.new
      @active = nil
      @terminal = {}
    end

    def run(conversation_id:, request_id:, cancel:, released:)
      key = identity(conversation_id, request_id)
      entry = { key: key, requested: false }
      @mutex.synchronize do
        raise RosterAdmissionBusy, "request control busy" if @active
        @terminal.delete(key)
        @active = entry
      end
      owned = true
      signal = -> { @mutex.synchronize { entry[:requested] } || cancel.call }
      result = yield signal
      finish(entry, "completed")
      result
    rescue StandardError
      if owned
        # The wrapped backend returns/raises only after its owner cleanup path.
        # Failure or inability to inspect release must never become confirmation.
        clean = begin
          released.call == true
        rescue StandardError
          false
        end
        requested = @mutex.synchronize { entry[:requested] }
        finish(entry, requested && clean ? "canceled_released" : "failed_unconfirmed")
      end
      raise
    ensure
      @mutex.synchronize { @active = nil if @active.equal?(entry) } if owned
    end

    def cancel(conversation_id:, request_id:)
      key = identity(conversation_id, request_id)
      @mutex.synchronize do
        if @active && @active[:key] == key
          @active[:requested] = true
          projection(key, "cancel_requested")
        else
          projection(key, @terminal[key] || "unknown")
        end
      end
    end

    def status(conversation_id:, request_id:)
      key = identity(conversation_id, request_id)
      @mutex.synchronize do
        state = if @active && @active[:key] == key
          @active[:requested] ? "cancel_requested" : "running"
        else
          @terminal[key] || "unknown"
        end
        projection(key, state)
      end
    end

    private

    def identity(conversation_id, request_id)
      values = [conversation_id, request_id]
      raise ArgumentError, "invalid request identity" unless values.all? { |v| v.is_a?(String) && ID.match?(v) }
      values.map { |v| v.dup.freeze }.freeze
    end

    def finish(entry, state)
      @mutex.synchronize do
        @terminal[entry[:key]] = state
        @terminal.shift while @terminal.length > LIMIT
        @active = nil if @active.equal?(entry)
      end
    end

    def projection(key, state)
      { "conversation_id" => key[0], "request_id" => key[1], "state" => state,
        "cleanup_confirmed" => state == "canceled_released", "durable" => false }
    end
  end
end
