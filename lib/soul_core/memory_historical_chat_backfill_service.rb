# frozen_string_literal: true

require "digest"
require "json"
require_relative "chat_store"
require_relative "conversation_observation_store"

module SoulCore
  # Reconciles persisted historical chats into immutable source observations.
  class MemoryHistoricalChatBackfillService
    SCHEMA = "soul.memory_historical_chat_backfill.a15.v1"
    CONFIRMATION = "BACKFILL_HISTORICAL_CONVERSATIONS"
    MAX_CHATS = 25
    MAX_CHAT_RECORDS = 500
    MAX_EXCHANGES = 50
    MAX_MESSAGES_PER_CHAT = 10_000
    MAX_SCANNED_MESSAGES = 20_000

    def initialize(root: Dir.pwd, chat_store: nil, observation_store: nil)
      @root = File.expand_path(root)
      @chats = chat_store || ChatStore.new(root: @root)
      @observations = observation_store || ConversationObservationStore.new(root: @root)
    end

    def preview
      scope = build_scope
      complete(
        "backfill" => projection(scope),
        "expected_digest" => scope_digest(scope),
        "confirmation_phrase" => scope.empty? ? nil : CONFIRMATION,
        "confirmation_required" => !scope.empty?,
        "no_work" => scope.empty?,
        "mutation" => "none"
      )
    rescue StandardError => error
      failed(safe_reason(error))
    end

    def execute(confirmation:, expected_digest:)
      return awaiting("exact confirmation #{CONFIRMATION} is required") unless confirmation == CONFIRMATION
      return awaiting("preview digest is required") unless expected_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

      scope = build_scope
      return blocked("historical chat backfill scope changed; preview again") unless secure_compare(expected_digest, scope_digest(scope))
      return complete("backfill" => projection(scope), "no_work" => true, "mutation" => "none") if scope.empty?

      captured = 0
      idempotent = 0
      scope.each do |exchange|
        result = @observations.capture_exchange(
          user_message: exchange.fetch("user"), assistant_message: exchange.fetch("assistant"),
          request_id: exchange.fetch("request_id"), interface: "historical_backfill"
        )
        raise ArgumentError, result.fetch("reason", "historical observation capture failed") unless result["ok"]
        result["idempotent"] ? idempotent += 1 : captured += 1
      end
      complete(
        "backfill" => projection(scope).merge("captured_exchanges" => captured, "idempotent_exchanges" => idempotent),
        "no_work" => false,
        "mutation" => "append_private_observations"
      )
    rescue StandardError => error
      failed(safe_reason(error), mutation: "partial_or_none")
    end

    private

    def build_scope
      ensure_chat_store_safe!
      candidates = []
      scanned_messages = 0
      chats = @chats.list_chats(include_archived: true).sort_by { |chat| [chat.fetch("created_at").to_s, chat.fetch("id").to_s] }
      raise ArgumentError, "historical chat inventory exceeds #{MAX_CHAT_RECORDS} chats; use a later narrowing control" if chats.length > MAX_CHAT_RECORDS
      chats.each do |chat|
        messages = safe_messages(chat.fetch("id"))
        scanned_messages += messages.length
        raise ArgumentError, "historical chat scan exceeds #{MAX_SCANNED_MESSAGES} messages; narrow the reviewed batch" if scanned_messages > MAX_SCANNED_MESSAGES
        candidates.concat(complete_exchanges(messages))
      end
      return [] if candidates.empty?

      ids = candidates.flat_map { |exchange| exchange.values_at("user", "assistant").map { |message| message.fetch("id").to_s } }
      captured = @observations.captured_message_ids(ids: ids).to_h { |id| [id, true] }
      pending = candidates.reject do |exchange|
        pair_ids = exchange.values_at("user", "assistant").map { |message| message.fetch("id").to_s }
        pair_ids.any? { |id| captured[id] }
      end
      selected = []
      selected_chats = {}
      pending.each do |exchange|
        chat_id = exchange.fetch("chat_id")
        next if !selected_chats.key?(chat_id) && selected_chats.length >= MAX_CHATS
        selected_chats[chat_id] = true
        selected << exchange
        break if selected.length >= MAX_EXCHANGES
      end
      selected
    end

    def complete_exchanges(messages)
      exchanges = []
      index = 0
      while index < messages.length - 1
        user = messages[index]
        assistant = messages[index + 1]
        if user["role"] == "user" && assistant["role"] == "assistant" && user["chat_id"] == assistant["chat_id"]
          exchanges << {
            "chat_id" => user.fetch("chat_id"),
            "user" => normalized_source_message(user),
            "assistant" => normalized_source_message(assistant),
            "request_id" => request_id(user, assistant)
          }
          index += 2
        else
          index += 1
        end
      end
      exchanges
    end

    def normalized_source_message(message)
      message.slice("id", "chat_id", "role", "content", "created_at")
    end

    def request_id(user, assistant)
      existing = [user, assistant].filter_map { |message| message.dig("metadata", "application_request_id") }
        .find { |value| value.to_s.match?(/\A[A-Za-z0-9_.:-]{1,160}\z/) }
      return existing.to_s if existing

      material = [user["chat_id"], user["id"], assistant["id"]].join("\0")
      "a15_backfill_#{Digest::SHA256.hexdigest(material)[0, 24]}"
    end

    def safe_messages(chat_id)
      path = File.join(@chats.root, "#{safe_chat_id(chat_id)}.jsonl")
      stat = File.lstat(path)
      raise ArgumentError, "historical chat transcript must be a regular file" unless stat.file? && !File.symlink?(path)
      @chats.messages(chat_id, scan_limit: MAX_MESSAGES_PER_CHAT)
    end

    def ensure_chat_store_safe!
      project_prefix = "#{@root}#{File::SEPARATOR}"
      expanded = File.expand_path(@chats.root)
      raise ArgumentError, "historical chat store escapes the project" unless expanded.start_with?(project_prefix)
      relative = expanded.delete_prefix(project_prefix)
      current = @root
      relative.split(File::SEPARATOR).each do |part|
        current = File.join(current, part)
        stat = File.lstat(current)
        raise ArgumentError, "historical chat store contains a symlink" if stat.symlink?
      end
      raise ArgumentError, "historical chat store is not a directory" unless File.directory?(expanded)
      Dir.glob(File.join(expanded, "*.{json,jsonl}"), File::FNM_EXTGLOB).each do |path|
        stat = File.lstat(path)
        raise ArgumentError, "historical chat store contains an unsafe entry" unless stat.file? && !stat.symlink?
      end
    end

    def safe_chat_id(value)
      id = value.to_s
      raise ArgumentError, "historical chat identity is invalid" unless id.match?(/\A[A-Za-z0-9_.-]{1,160}\z/)
      id
    end

    def projection(scope)
      {
        "exchange_count" => scope.length,
        "chat_count" => scope.map { |item| item.fetch("chat_id") }.uniq.length,
        "message_count" => scope.length * 2,
        "first_created_at" => scope.first&.dig("user", "created_at"),
        "last_created_at" => scope.last&.dig("assistant", "created_at"),
        "content_included" => false
      }
    end

    def scope_digest(scope)
      material = scope.map do |exchange|
        [exchange.fetch("chat_id"), exchange.fetch("request_id"),
         exchange.dig("user", "id"), exchange.dig("user", "created_at"), Digest::SHA256.hexdigest(exchange.dig("user", "content")),
         exchange.dig("assistant", "id"), exchange.dig("assistant", "created_at"), Digest::SHA256.hexdigest(exchange.dig("assistant", "content"))]
      end
      Digest::SHA256.hexdigest(JSON.generate(material))
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "data" => data, "content_included" => false }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "schema" => SCHEMA,
        "reason" => reason, "data" => {}, "content_included" => false }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "schema" => SCHEMA,
        "reason" => reason, "data" => {}, "content_included" => false }
    end

    def failed(reason, mutation: "none")
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "reason" => reason, "data" => { "mutation" => mutation }, "content_included" => false }
    end

    def safe_reason(error)
      "historical chat backfill failed safely: #{error.class}"
    end
  end
end
