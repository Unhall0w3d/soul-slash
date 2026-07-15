# frozen_string_literal: true

require "digest"
require_relative "chat_store"

module SoulCore
  class ConversationClearService
    MAX_MATCHES = 500
    CONFIRMATION = "CLEAR_CONVERSATIONS"
    MODES = %w[title selected all].freeze

    def initialize(root: Dir.pwd, store: nil)
      @store = store || ChatStore.new(root: root)
    end

    def preview(mode:, title: nil, chat_ids: nil)
      selection = select_active(mode: mode, title: title, chat_ids: chat_ids)
      return selection unless selection.fetch("ok")

      records = selection.fetch("records")
      success(
        {
          "mode" => mode,
          "title" => normalized_title(title, required: false),
          "chat_ids" => mode == "selected" ? records.map { |record| record.fetch("id") } : [],
          "records" => records.map { |record| projection(record) },
          "count" => records.length,
          "match_digest" => digest(records),
          "confirmation_required" => true,
          "confirmation_phrase" => CONFIRMATION,
          "transcripts_deleted" => false,
          "archival_only" => true
        },
        mutation: "none"
      )
    end

    def execute(mode:, title: nil, chat_ids: nil, confirmation:, expected_digest:)
      return awaiting("exact confirmation #{CONFIRMATION} is required") unless confirmation == CONFIRMATION
      return awaiting("preview match digest is required") unless expected_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

      selection = select_active(mode: mode, title: title, chat_ids: chat_ids)
      if mode == "selected" && !selection.fetch("ok") && selection["reason"] == "selected conversations are no longer active; preview again"
        return blocked("selected conversation set changed; preview again")
      end
      return selection unless selection.fetch("ok")

      records = selection.fetch("records")
      current_digest = digest(records)
      return blocked("active conversation match set changed; preview again") unless secure_compare(expected_digest, current_digest)

      archived = []
      records.each { |record| archived << projection(@store.archive(record.fetch("id"))) }
      success(
        {
          "mode" => mode,
          "title" => normalized_title(title, required: false),
          "chat_ids" => mode == "selected" ? records.map { |record| record.fetch("id") } : [],
          "records" => archived,
          "count" => archived.length,
          "match_digest" => current_digest,
          "transcripts_deleted" => false,
          "archival_only" => true
        },
        mutation: "conversations_archived"
      )
    rescue StandardError => error
      blocked("conversation archival stopped safely after #{archived&.length || 0} updates: #{error.class}", data: { "records" => archived || [], "transcripts_deleted" => false })
    end

    private

    def select_active(mode:, title:, chat_ids: nil)
      return awaiting("mode must be title, selected, or all") unless MODES.include?(mode)

      active = @store.list_chats
      records = if mode == "all"
                  return awaiting("title must not be provided for all mode") unless title.to_s.strip.empty?
                  return awaiting("chat_ids must not be provided for all mode") unless Array(chat_ids).empty?
                  active
                elsif mode == "selected"
                  return awaiting("title must not be provided for selected mode") unless title.to_s.strip.empty?
                  ids = normalized_chat_ids(chat_ids)
                  return ids if ids.is_a?(Hash)
                  active_by_id = active.to_h { |record| [record.fetch("id"), record] }
                  missing = ids.reject { |id| active_by_id.key?(id) }
                  return awaiting("selected conversations are no longer active; preview again") unless missing.empty?
                  ids.map { |id| active_by_id.fetch(id) }
                else
                  return awaiting("chat_ids must not be provided for title mode") unless Array(chat_ids).empty?
                  exact_title = normalized_title(title, required: true)
                  return exact_title if exact_title.is_a?(Hash)
                  active.select { |record| record["title"].to_s.strip.casecmp?(exact_title) }
                end
      return awaiting("no active conversations matched") if records.empty?
      return blocked("match set exceeds #{MAX_MATCHES}; narrow the request") if records.length > MAX_MATCHES

      { "ok" => true, "records" => records.sort_by { |record| record.fetch("id") } }
    end

    def normalized_chat_ids(chat_ids)
      return awaiting("select at least one conversation") unless chat_ids.is_a?(Array) && !chat_ids.empty?
      return awaiting("selected conversation count exceeds #{MAX_MATCHES}") if chat_ids.length > MAX_MATCHES
      return awaiting("selected conversation IDs must be strings") unless chat_ids.all? { |value| value.is_a?(String) }
      return awaiting("selected conversation ID is invalid") unless chat_ids.all? { |value| value.match?(/\Achat_[A-Za-z0-9_.-]+\z/) }
      return awaiting("selected conversation IDs must be unique") unless chat_ids.uniq.length == chat_ids.length

      chat_ids
    end

    def normalized_title(title, required:)
      value = title.to_s.strip
      return awaiting("exact title is required") if required && value.empty?
      return awaiting("title exceeds 120 characters") if value.length > 120

      value.empty? ? nil : value
    end

    def digest(records)
      Digest::SHA256.hexdigest(records.map { |record| record.fetch("id") }.sort.join("\n"))
    end

    def projection(record)
      record.slice("id", "title", "updated_at", "pinned", "archived")
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def success(data, mutation:)
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def blocked(reason, data: {})
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => data, "mutation" => "partial_or_none" }
    end
  end
end
