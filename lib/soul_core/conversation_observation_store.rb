# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "memory_paths"

module SoulCore
  # Owner-private source observations are evidence, not retrieval-active memory.
  class ConversationObservationStore
    SCHEMA = "soul.conversation_observation.v1"
    FILE_NAME = "conversation_observations.jsonl"
    MAX_LEDGER_BYTES = 256 * 1024 * 1024
    MAX_EVENTS = 200_000
    MAX_CONTENT_BYTES = 65_536
    ROLES = %w[user assistant].freeze
    IDENTITY_KEYS = %w[message_id chat_id role content created_at request_id interface].freeze

    attr_reader :path

    def initialize(root: Dir.pwd, path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @path = File.expand_path(path || MemoryPaths.new(root: @root).write_path(FILE_NAME), @root)
      @clock = clock
      ensure_safe_path!
    end

    def capture_exchange(user_message:, assistant_message:, request_id:, interface:)
      candidates = [
        normalize_message(user_message, expected_role: "user", request_id: request_id, interface: interface),
        normalize_message(assistant_message, expected_role: "assistant", request_id: request_id, interface: interface)
      ]
      raise ArgumentError, "conversation messages must belong to one chat" unless candidates.map { |item| item["chat_id"] }.uniq.length == 1

      ensure_safe_path!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a+b") do |file|
        file.flock(File::LOCK_EX)
        ensure_safe_path!
        file.rewind
        raw = file.read.to_s
        events = parse_and_verify(raw)
        existing = events.select { |event| candidates.any? { |candidate| candidate["message_id"] == event["message_id"] } }
        unless existing.empty?
          return idempotent_receipt(existing, candidates) if exact_exchange?(existing, candidates)

          raise ArgumentError, "conversation observation identity conflicts with retained evidence"
        end
        raise ArgumentError, "conversation observation ledger exceeds event limit" if events.length + candidates.length > MAX_EVENTS

        previous = events.last && events.last["event_sha256"]
        captured_at = @clock.call.iso8601(6)
        staged = candidates.map do |candidate|
          event = {
            "schema" => SCHEMA,
            "observation_id" => observation_id(candidate.fetch("message_id")),
            "message_id" => candidate.fetch("message_id"),
            "chat_id" => candidate.fetch("chat_id"),
            "role" => candidate.fetch("role"),
            "content" => candidate.fetch("content"),
            "created_at" => candidate.fetch("created_at"),
            "captured_at" => captured_at,
            "request_id" => candidate.fetch("request_id"),
            "interface" => candidate.fetch("interface"),
            "content_sha256" => Digest::SHA256.hexdigest(candidate.fetch("content")),
            "previous_event_sha256" => previous
          }
          event["event_sha256"] = event_digest(event)
          previous = event["event_sha256"]
          event
        end
        encoded = staged.map { |event| JSON.generate(event) + "\n" }.join
        raise ArgumentError, "conversation observation ledger exceeds size limit" if raw.bytesize + encoded.bytesize > MAX_LEDGER_BYTES

        file.seek(0, IO::SEEK_END)
        file.write(encoded)
        file.flush
        file.fsync
        receipt(staged, idempotent: false, total_events: events.length + staged.length)
      end
    rescue JSON::ParserError
      failure("conversation observation ledger contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT => error
      failure(error.message)
    end

    def integrity
      ensure_safe_path!
      raw = File.file?(@path) ? File.binread(@path) : ""
      events = parse_and_verify(raw)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "schema" => SCHEMA,
        "event_count" => events.length,
        "chain_head_sha256" => events.last && events.last["event_sha256"],
        "content_included" => false
      }
    rescue JSON::ParserError
      failure("conversation observation ledger contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    private

    def normalize_message(message, expected_role:, request_id:, interface:)
      raise ArgumentError, "conversation message must be an object" unless message.is_a?(Hash)
      value = message.transform_keys(&:to_s)
      role = value["role"].to_s
      raise ArgumentError, "conversation message role is invalid" unless role == expected_role && ROLES.include?(role)
      content = value["content"].to_s
      raise ArgumentError, "conversation message content must not be empty" if content.empty?
      raise ArgumentError, "conversation message content exceeds limit" if content.bytesize > MAX_CONTENT_BYTES
      raise ArgumentError, "conversation message content must be valid UTF-8" unless content.valid_encoding?
      created_at = value["created_at"].to_s
      Time.iso8601(created_at)
      normalized = {
        "message_id" => bounded_identity(value["id"], "message ID"),
        "chat_id" => bounded_identity(value["chat_id"], "chat ID"),
        "role" => role,
        "content" => content,
        "created_at" => created_at,
        "request_id" => bounded_identity(request_id, "request ID"),
        "interface" => bounded_identity(interface, "interface")
      }
      normalized
    end

    def bounded_identity(value, label)
      text = value.to_s
      raise ArgumentError, "#{label} is required" if text.empty?
      raise ArgumentError, "#{label} exceeds limit" if text.bytesize > 160
      raise ArgumentError, "#{label} contains unsupported characters" unless text.match?(/\A[A-Za-z0-9_.:-]+\z/)
      text
    end

    def parse_and_verify(raw)
      raise ArgumentError, "conversation observation ledger exceeds size limit" if raw.bytesize > MAX_LEDGER_BYTES
      raise ArgumentError, "conversation observation ledger has a partial final write" unless raw.empty? || raw.end_with?("\n")
      lines = raw.lines
      raise ArgumentError, "conversation observation ledger exceeds event limit" if lines.length > MAX_EVENTS
      events = lines.each_with_index.filter_map do |line, index|
        next if line.strip.empty?
        event = JSON.parse(line)
        raise ArgumentError, "conversation observation event #{index + 1} is not an object" unless event.is_a?(Hash)
        event
      end
      ids = events.map { |event| event["observation_id"].to_s }
      messages = events.map { |event| event["message_id"].to_s }
      raise ArgumentError, "conversation observation identity is invalid" if ids.any?(&:empty?) || messages.any?(&:empty?) || ids.uniq.length != ids.length || messages.uniq.length != messages.length
      previous = nil
      events.each do |event|
        raise ArgumentError, "conversation observation schema is unsupported" unless event["schema"] == SCHEMA
        raise ArgumentError, "conversation observation role is invalid" unless ROLES.include?(event["role"].to_s)
        raise ArgumentError, "conversation observation identity is invalid" unless
          observation_id(event["message_id"].to_s) == event["observation_id"].to_s &&
          %w[message_id chat_id request_id interface].all? { |key| !event[key].to_s.empty? && event[key].to_s.bytesize <= 160 }
        raise ArgumentError, "conversation observation content is invalid" unless
          event["content"].is_a?(String) && event["content"].valid_encoding? &&
          !event["content"].empty? && event["content"].bytesize <= MAX_CONTENT_BYTES
        Time.iso8601(event["created_at"].to_s)
        Time.iso8601(event["captured_at"].to_s)
        raise ArgumentError, "conversation observation chain is broken" unless event["previous_event_sha256"] == previous
        raise ArgumentError, "conversation observation content digest is invalid" unless event["content_sha256"] == Digest::SHA256.hexdigest(event["content"].to_s)
        raise ArgumentError, "conversation observation event digest is invalid" unless event["event_sha256"] == event_digest(event)
        previous = event["event_sha256"]
      end
      events
    end

    def exact_exchange?(existing, candidates)
      return false unless existing.length == candidates.length
      by_message = existing.to_h { |event| [event["message_id"], event] }
      candidates.all? do |candidate|
        event = by_message[candidate["message_id"]]
        event && IDENTITY_KEYS.all? { |key| event[key] == candidate[key] }
      end
    end

    def idempotent_receipt(existing, candidates)
      raise ArgumentError, "conversation observation exchange is only partially retained" unless existing.length == candidates.length
      receipt(existing, idempotent: true, total_events: nil)
    end

    def observation_id(message_id)
      "obs_#{Digest::SHA256.hexdigest(message_id)[0, 24]}"
    end

    def event_digest(event)
      Digest::SHA256.hexdigest(JSON.generate(event.reject { |key, _value| key == "event_sha256" }) + "\n")
    end

    def receipt(events, idempotent:, total_events:)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "idempotent" => idempotent,
        "observation_ids" => events.map { |event| event["observation_id"] },
        "message_ids" => events.map { |event| event["message_id"] },
        "event_count" => events.length,
        "ledger_event_count" => total_events,
        "chain_head_sha256" => events.last && events.last["event_sha256"],
        "content_included" => false
      }.compact
    end

    def failure(reason)
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 300],
        "content_included" => false
      }
    end

    def ensure_safe_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "conversation observation path escapes project" unless @path.start_with?(prefix)
      raise ArgumentError, "conversation observation ledger must not be a symlink" if File.symlink?(@path)
      parent = File.dirname(@path)
      while parent.start_with?(prefix)
        raise ArgumentError, "conversation observation parent must not be a symlink" if File.symlink?(parent)
        parent = File.dirname(parent)
      end
    end
  end
end
