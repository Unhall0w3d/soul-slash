# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module SoulCore
  class ApplicationRequestReceiptStore
    DEFAULT_PATH = File.join("Soul", "runtime", "application", "request_receipts.jsonl")
    MAX_EVENTS = 5_000
    MAX_BYTES = 2 * 1024 * 1024

    def initialize(root:, path: DEFAULT_PATH, clock: -> { Time.now })
      @root = File.expand_path(root)
      @path = File.expand_path(path, @root)
      @clock = clock
    end

    attr_reader :path

    def reserve(request_id:, operation:, identity:, input_digest:)
      with_locked_file do |file|
        current = replay(file).fetch(request_id.to_s, nil)
        if current
          same = current["operation"] == operation.to_s &&
                 current["identity"] == identity.to_s &&
                 current["input_digest"] == input_digest.to_s
          return { "status" => "conflict", "receipt" => public_receipt(current) } unless same
          return { "status" => "replay", "receipt" => public_receipt(current) } if current["status"] == "complete"

          return { "status" => current["status"], "receipt" => public_receipt(current) }
        end

        event = {
          "event_type" => "reserved",
          "request_id" => request_id.to_s,
          "operation" => operation.to_s,
          "identity" => identity.to_s,
          "input_digest" => input_digest.to_s,
          "status" => "reserved",
          "created_at" => @clock.call.iso8601
        }
        append!(file, event)
        { "status" => "reserved", "receipt" => public_receipt(event) }
      end
    end

    def complete(request_id:, user_message_id:, assistant_message_id:)
      transition(
        request_id,
        "completed",
        "complete",
        "user_message_id" => user_message_id.to_s,
        "assistant_message_id" => assistant_message_id.to_s
      )
    end

    def fail(request_id:, category:)
      transition(request_id, "failed", "failed", "failure_category" => category.to_s[0, 120])
    end

    def find(request_id)
      return nil unless File.exist?(@path)

      File.open(@path, File::RDONLY) do |file|
        file.flock(File::LOCK_SH)
        public_receipt(replay(file)[request_id.to_s])
      ensure
        file&.flock(File::LOCK_UN)
      end
    rescue Errno::ENOENT
      nil
    end

    private

    def transition(request_id, event_type, status, fields)
      with_locked_file do |file|
        current = replay(file)[request_id.to_s]
        raise ArgumentError, "unknown application request ID" unless current
        return public_receipt(current) if current["status"] == status
        raise RuntimeError, "application request is already terminal" if %w[complete failed].include?(current["status"])

        event = {
          "event_type" => event_type,
          "request_id" => request_id.to_s,
          "status" => status,
          "created_at" => @clock.call.iso8601
        }.merge(fields)
        append!(file, event)
        public_receipt(current.merge(event))
      end
    end

    def with_locked_file
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        file.chmod(0o600)
        file.flock(File::LOCK_EX)
        yield file
      ensure
        file&.flock(File::LOCK_UN)
      end
    end

    def replay(file)
      file.rewind
      state = {}
      event_count = 0
      file.each_line do |line|
        event_count += 1
        raise RuntimeError, "application request receipt history exceeds #{MAX_EVENTS} events" if event_count > MAX_EVENTS

        event = JSON.parse(line)
        request_id = event.fetch("request_id")
        state[request_id] = (state[request_id] || {}).merge(event)
      rescue JSON::ParserError, KeyError
        raise RuntimeError, "application request receipt history is corrupt"
      end
      state
    end

    def append!(file, event)
      payload = "#{JSON.generate(event)}\n"
      raise RuntimeError, "application request receipt history is full" if file.size + payload.bytesize > MAX_BYTES
      file.rewind
      raise RuntimeError, "application request receipt history is full" if file.each_line.count >= MAX_EVENTS

      file.seek(0, IO::SEEK_END)
      file.write(payload)
      file.flush
      file.fsync
    end

    def public_receipt(record)
      return nil unless record

      record.slice(
        "request_id",
        "operation",
        "identity",
        "input_digest",
        "status",
        "user_message_id",
        "assistant_message_id",
        "failure_category",
        "created_at"
      )
    end
  end
end
