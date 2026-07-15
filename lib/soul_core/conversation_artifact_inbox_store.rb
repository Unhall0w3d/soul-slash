# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ConversationArtifactInboxStore
    DEFAULT_RELATIVE_PATH = "Soul/runtime/artifact_inbox/events.jsonl"
    EVENT_TYPES = %w[delivered state_changed].freeze
    DELIVERY_STATES = %w[new seen dismissed].freeze
    MAX_RECORDS = 50

    attr_reader :root, :path

    def initialize(root:, path: nil, clock: nil)
      @root = File.expand_path(root)
      @path = File.expand_path(path || File.join(@root, DEFAULT_RELATIVE_PATH))
      @clock = clock || -> { Time.now.utc }
    end

    def deliver(artifact:, originating_chat_id:, recipient_chat_id:, reason:)
      snapshot = delivery_snapshot(
        artifact,
        originating_chat_id: originating_chat_id,
        recipient_chat_id: recipient_chat_id,
        reason: reason
      )

      with_locked_file do |file|
        current = records_from(read_events(file)).values.find do |record|
          idempotency_key(record) == idempotency_key(snapshot)
        end
        return current.merge("idempotent" => true) if current

        delivery_id = delivery_id_for
        append_locked(
          file,
          event_type: "delivered",
          delivery_id: delivery_id,
          payload: snapshot.merge(
            "delivery_id" => delivery_id,
            "latest_delivery_state" => "new",
            "latest_state_at" => timestamp
          )
        )
        records_from(read_events(file)).fetch(delivery_id).merge("idempotent" => false)
      end
    end

    def change_state(delivery_id, chat_id:, state:)
      target_state = state.to_s
      raise ArgumentError, "Unsupported inbox delivery state: #{target_state}" unless DELIVERY_STATES.include?(target_state)

      with_locked_file do |file|
        record = records_from(read_events(file))[delivery_id.to_s]
        raise ArgumentError, "Unknown delivery ID: #{delivery_id}" unless record
        unless record.fetch("recipient_chat_id") == require_chat_id(chat_id)
          raise ArgumentError, "Delivery belongs to another chat"
        end
        return record.merge("idempotent" => true) if record.fetch("latest_delivery_state") == target_state

        append_locked(
          file,
          event_type: "state_changed",
          delivery_id: record.fetch("delivery_id"),
          payload: { "state" => target_state, "chat_id" => chat_id.to_s }
        )
        records_from(read_events(file)).fetch(record.fetch("delivery_id")).merge("idempotent" => false)
      end
    end

    def find(delivery_id)
      records[delivery_id.to_s]
    end

    def list(chat_id: nil, state: nil, limit: MAX_RECORDS)
      selected = records.values
      unless chat_id.to_s.strip.empty?
        selected = selected.select { |record| record["recipient_chat_id"] == chat_id.to_s.strip }
      end
      unless state.to_s.strip.empty?
        normalized = state.to_s.strip
        raise ArgumentError, "Unsupported inbox delivery state: #{normalized}" unless DELIVERY_STATES.include?(normalized)

        selected = selected.select { |record| record["latest_delivery_state"] == normalized }
      end
      selected
        .sort_by { |record| [record["latest_state_at"].to_s, record["delivery_id"].to_s] }
        .reverse
        .first(normalize_limit(limit))
    end

    def events
      return [] unless File.file?(path)

      File.open(path, File::RDONLY) do |file|
        file.flock(File::LOCK_SH)
        read_events(file)
      ensure
        file.flock(File::LOCK_UN)
      end
    end

    def records
      records_from(events)
    end

    private

    def delivery_snapshot(artifact, originating_chat_id:, recipient_chat_id:, reason:)
      record = artifact.is_a?(Hash) ? artifact : {}
      artifact_id = record["artifact_id"].to_s
      raise ArgumentError, "A registered artifact ID is required" unless artifact_id.match?(/\Aart_[a-zA-Z0-9_]+\z/)
      raise ArgumentError, "Only active artifacts may be delivered" unless record["lifecycle"] == "active"

      {
        "artifact_id" => artifact_id,
        "originating_chat_id" => require_chat_id(originating_chat_id),
        "recipient_chat_id" => require_chat_id(recipient_chat_id),
        "delivery_reason" => require_reason(reason),
        "artifact_lifecycle_at_delivery" => record.fetch("lifecycle"),
        "privacy" => record.fetch("privacy"),
        "size_bytes" => Integer(record.fetch("size_bytes")),
        "sha256" => record.fetch("sha256").to_s,
        "created_at" => timestamp
      }
    end

    def with_locked_file
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        result = yield(file)
        file.flush
        file.fsync
        result
      ensure
        file.flock(File::LOCK_UN)
      end
    ensure
      File.chmod(0o600, path) if File.exist?(path)
    end

    def append_locked(file, event_type:, delivery_id:, payload:)
      raise ArgumentError, "Unsupported inbox event: #{event_type}" unless EVENT_TYPES.include?(event_type)

      event = {
        "event_id" => "inboxev_#{timestamp.delete('^0-9')}_#{SecureRandom.hex(4)}",
        "event_type" => event_type,
        "delivery_id" => delivery_id,
        "payload" => payload,
        "created_at" => timestamp
      }
      file.seek(0, IO::SEEK_END)
      file.write(JSON.generate(event) + "\n")
      file.flush
      event
    end

    def read_events(file)
      file.rewind
      file.each_line.filter_map do |line|
        next if line.strip.empty?

        event = JSON.parse(line)
        validate_event!(event)
        event
      end
    end

    def records_from(events)
      events.each_with_object({}) do |event, state|
        delivery_id = event.fetch("delivery_id")
        case event.fetch("event_type")
        when "delivered"
          raise RuntimeError, "Duplicate inbox delivery ID: #{delivery_id}" if state.key?(delivery_id)

          state[delivery_id] = deep_copy(event.fetch("payload"))
        when "state_changed"
          record = state.fetch(delivery_id) { raise RuntimeError, "Inbox state references unknown delivery #{delivery_id}" }
          target = event.dig("payload", "state").to_s
          raise RuntimeError, "Inbox state is invalid: #{target}" unless DELIVERY_STATES.include?(target)

          record["latest_delivery_state"] = target
          record["latest_state_at"] = event.fetch("created_at")
        end
      end
    end

    def validate_event!(event)
      raise RuntimeError, "Inbox event must be an object" unless event.is_a?(Hash)
      raise RuntimeError, "Inbox event type is invalid" unless EVENT_TYPES.include?(event["event_type"])
      raise RuntimeError, "Inbox event ID is missing" if event["event_id"].to_s.empty?
      raise RuntimeError, "Delivery ID is missing" unless event["delivery_id"].to_s.match?(/\Adel_[a-zA-Z0-9_]+\z/)
      raise RuntimeError, "Inbox event payload is missing" unless event["payload"].is_a?(Hash)
      raise RuntimeError, "Inbox event timestamp is missing" if event["created_at"].to_s.empty?
    end

    def idempotency_key(record)
      %w[artifact_id originating_chat_id recipient_chat_id delivery_reason].map { |key| record.fetch(key).to_s }
    end

    def delivery_id_for
      "del_#{timestamp.delete('^0-9')}_#{SecureRandom.hex(4)}"
    end

    def timestamp
      @clock.call.utc.iso8601(6)
    end

    def require_chat_id(chat_id)
      value = chat_id.to_s.strip
      raise ArgumentError, "A chat ID is required for inbox delivery" if value.empty?

      value
    end

    def require_reason(reason)
      value = reason.to_s.strip
      raise ArgumentError, "A delivery reason is required" if value.empty?

      value[0, 120]
    end

    def normalize_limit(value)
      number = value.to_i
      number = MAX_RECORDS unless number.positive?
      [number, MAX_RECORDS].min
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
