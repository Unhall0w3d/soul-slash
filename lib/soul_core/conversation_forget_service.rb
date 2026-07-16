# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "chat_store"
require_relative "conversation_artifact_store"
require_relative "conversation_memory_store"

module SoulCore
  class ConversationForgetService
    CONFIRMATION = "DELETE_AND_FORGET_CONVERSATION"
    CHAT_ID = /\Achat_[A-Za-z0-9_.-]+\z/
    MAX_LINKS = 500
    BULK_MODES = %w[title selected all].freeze
    MAX_BULK_CONVERSATIONS = 100
    MAX_BULK_LINKS = 2_000

    def initialize(root: Dir.pwd, chat_store: nil, memory_store: nil, artifact_store: nil)
      @root = File.expand_path(root)
      @chat_store = chat_store || ChatStore.new(root: @root)
      @memory_store = memory_store
      @artifact_store = artifact_store || ConversationArtifactStore.new(root: @root)
    end

    def preview(chat_id:)
      inventory = inventory_for(chat_id)
      return inventory unless inventory.fetch("ok")

      data = inventory.fetch("data")
      public_data = data.except("memory_inventory", "artifact_inventory")
        .merge("owned_files" => data.fetch("owned_files").map { |file| file.except("absolute_path") })
      success(public_data.merge(
        "inventory_digest" => digest(data),
        "confirmation_required" => true,
        "confirmation_phrase" => CONFIRMATION,
        "irreversible" => true,
        "retained" => retained_disclosure
      ), mutation: "none")
    end

    def execute(chat_id:, confirmation:, expected_digest:)
      return awaiting("exact confirmation #{CONFIRMATION} is required") unless confirmation == CONFIRMATION
      return awaiting("preview inventory digest is required") unless expected_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

      inventory = inventory_for(chat_id)
      return inventory unless inventory.fetch("ok")
      data = inventory.fetch("data")
      return blocked("conversation inventory changed; preview again") unless secure_compare(expected_digest, digest(data))

      completed = { "memory_ids" => [], "artifact_ids" => [], "deleted_files" => [] }
      data.fetch("memory_ids").each do |memory_id|
        memory_store.delete(memory_id, reason: "Source conversation permanently deleted by explicit owner request")
        completed["memory_ids"] << memory_id
      end
      data.fetch("artifact_ids").each do |artifact_id|
        @artifact_store.detach(artifact_id, chat_id: chat_id)
        completed["artifact_ids"] << artifact_id
      end
      data.fetch("owned_files").each do |file|
        next unless file.fetch("exists")

        File.unlink(file.fetch("absolute_path"))
        completed["deleted_files"] << file.fetch("kind")
      end

      success(
        data.except("owned_files").merge(
          "memory_ids_logically_deleted" => completed.fetch("memory_ids"),
          "artifact_ids_detached" => completed.fetch("artifact_ids"),
          "deleted_file_kinds" => completed.fetch("deleted_files"),
          "retained" => retained_disclosure,
          "irreversible" => true
        ),
        mutation: "conversation_deleted_and_memories_forgotten"
      )
    rescue StandardError => error
      blocked(
        "delete-and-forget stopped after a partial or zero mutation: #{error.class}",
        data: { "completed" => completed || {}, "retained" => retained_disclosure }
      )
    end

    def preview_many(mode:, title: nil, chat_ids: nil)
      selection = select_active(mode: mode, title: title, chat_ids: chat_ids)
      return selection unless selection.fetch("ok")

      aggregate = aggregate_inventory(selection.fetch("records"))
      return aggregate unless aggregate.fetch("ok")

      data = aggregate.fetch("data")
      success(
        public_aggregate(data).merge(
          "mode" => mode,
          "title" => normalized_title(title, required: false),
          "chat_ids" => mode == "selected" ? data.fetch("conversations").map { |item| item.dig("chat", "id") } : [],
          "inventory_digest" => aggregate_digest(data),
          "confirmation_required" => true,
          "confirmation_phrase" => bulk_confirmation(data.fetch("conversation_count")),
          "irreversible" => true,
          "retained" => retained_disclosure
        ),
        mutation: "none"
      )
    end

    def execute_many(mode:, title: nil, chat_ids: nil, confirmation:, expected_digest:)
      completed = { "memory_ids" => [], "artifact_detachments" => [], "deleted_files" => [] }
      return awaiting("exact preview confirmation is required") unless confirmation.to_s.match?(/\ADELETE_AND_FORGET_[1-9][0-9]*_CONVERSATIONS\z/)
      return awaiting("preview inventory digest is required") unless expected_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

      selection = select_active(mode: mode, title: title, chat_ids: chat_ids)
      return selection unless selection.fetch("ok")

      aggregate = aggregate_inventory(selection.fetch("records"))
      return aggregate unless aggregate.fetch("ok")
      data = aggregate.fetch("data")
      phrase = bulk_confirmation(data.fetch("conversation_count"))
      return blocked("conversation inventory changed; preview again") unless secure_compare(expected_digest, aggregate_digest(data))
      return awaiting("exact confirmation #{phrase} is required") unless confirmation == phrase

      data.fetch("memory_ids").each do |memory_id|
        memory_store.delete(memory_id, reason: "Source conversations permanently deleted by explicit owner request")
        completed["memory_ids"] << memory_id
      end
      data.fetch("conversations").each do |item|
        chat_id = item.dig("chat", "id")
        item.fetch("artifact_ids").each do |artifact_id|
          @artifact_store.detach(artifact_id, chat_id: chat_id)
          completed["artifact_detachments"] << { "artifact_id" => artifact_id, "chat_id" => chat_id }
        end
      end
      data.fetch("conversations").each do |item|
        chat_id = item.dig("chat", "id")
        item.fetch("owned_files").each do |file|
          next unless file.fetch("exists")

          File.unlink(file.fetch("absolute_path"))
          completed["deleted_files"] << { "chat_id" => chat_id, "kind" => file.fetch("kind") }
        end
      end

      deleted_chat_ids = data.fetch("conversations").map { |item| item.dig("chat", "id") }
      remaining = data.fetch("conversations").filter_map do |item|
        chat_id = item.dig("chat", "id")
        file_kinds = owned_paths(chat_id).filter_map do |kind, path|
          kind if File.exist?(path) || File.symlink?(path)
        end
        { "chat_id" => chat_id, "file_kinds" => file_kinds } if @chat_store.chat(chat_id) || !file_kinds.empty?
      end
      raise RuntimeError, "conversation deletion postcondition failed" unless remaining.empty?

      success(
        public_aggregate(data).merge(
          "mode" => mode,
          "memory_ids_logically_deleted" => completed.fetch("memory_ids"),
          "artifact_detachments" => completed.fetch("artifact_detachments"),
          "deleted_files" => completed.fetch("deleted_files"),
          "deleted_chat_ids" => deleted_chat_ids,
          "postcondition_verified" => true,
          "retained" => retained_disclosure,
          "irreversible" => true
        ),
        mutation: "conversations_deleted_and_memories_forgotten"
      )
    rescue StandardError => error
      blocked(
        "bulk delete-and-forget stopped after a partial or zero mutation: #{error.class}",
        data: { "completed" => completed || {}, "retained" => retained_disclosure, "postcondition_verified" => false }
      )
    end

    private

    def select_active(mode:, title:, chat_ids:)
      return awaiting("mode must be title, selected, or all") unless BULK_MODES.include?(mode)

      active = @chat_store.list_chats
      records = if mode == "all"
                  return awaiting("title must not be provided for all mode") unless title.to_s.strip.empty?
                  return awaiting("chat_ids must not be provided for all mode") unless Array(chat_ids).empty?
                  active
                elsif mode == "selected"
                  return awaiting("title must not be provided for selected mode") unless title.to_s.strip.empty?
                  ids = normalized_chat_ids(chat_ids)
                  return ids if ids.is_a?(Hash)
                  active_by_id = active.to_h { |record| [record.fetch("id"), record] }
                  return awaiting("selected conversations are no longer active; preview again") unless ids.all? { |id| active_by_id.key?(id) }
                  ids.map { |id| active_by_id.fetch(id) }
                else
                  return awaiting("chat_ids must not be provided for title mode") unless Array(chat_ids).empty?
                  exact_title = normalized_title(title, required: true)
                  return exact_title if exact_title.is_a?(Hash)
                  active.select { |record| record["title"].to_s.strip.casecmp?(exact_title) }
                end
      return awaiting("no active conversations matched") if records.empty?
      return blocked("permanent deletion scope exceeds #{MAX_BULK_CONVERSATIONS}; narrow the request") if records.length > MAX_BULK_CONVERSATIONS

      { "ok" => true, "records" => records.sort_by { |record| record.fetch("id") } }
    end

    def normalized_chat_ids(chat_ids)
      return awaiting("select at least one conversation") unless chat_ids.is_a?(Array) && !chat_ids.empty?
      return blocked("permanent deletion scope exceeds #{MAX_BULK_CONVERSATIONS}; narrow the request") if chat_ids.length > MAX_BULK_CONVERSATIONS
      return awaiting("selected conversation IDs must be strings") unless chat_ids.all? { |value| value.is_a?(String) }
      return awaiting("selected conversation ID is invalid") unless chat_ids.all? { |value| value.match?(CHAT_ID) }
      return awaiting("selected conversation IDs must be unique") unless chat_ids.uniq.length == chat_ids.length

      chat_ids
    end

    def normalized_title(title, required:)
      value = title.to_s.strip
      return awaiting("exact title is required") if required && value.empty?
      return awaiting("title exceeds 120 characters") if value.length > 120

      value.empty? ? nil : value
    end

    def aggregate_inventory(records)
      conversations = records.map do |record|
        inventory = inventory_for(record.fetch("id"))
        return inventory unless inventory.fetch("ok")
        inventory.fetch("data")
      end
      memory_ids = conversations.flat_map { |item| item.fetch("memory_ids") }.uniq.sort
      artifact_ids = conversations.flat_map { |item| item.fetch("artifact_ids") }.uniq.sort
      memory_reference_count = conversations.sum { |item| item.fetch("memory_ids").length }
      artifact_attachment_count = conversations.sum { |item| item.fetch("artifact_ids").length }
      return blocked("aggregate linked memory reference count exceeds #{MAX_BULK_LINKS}") if memory_reference_count > MAX_BULK_LINKS
      return blocked("aggregate artifact attachment count exceeds #{MAX_BULK_LINKS}") if artifact_attachment_count > MAX_BULK_LINKS

      owned_files = conversations.flat_map { |item| item.fetch("owned_files") }
      { "ok" => true, "data" => {
        "conversations" => conversations,
        "conversation_count" => conversations.length,
        "message_count" => conversations.sum { |item| item.fetch("message_count") },
        "memory_ids" => memory_ids,
        "artifact_ids" => artifact_ids,
        "memory_reference_count" => memory_reference_count,
        "artifact_attachment_count" => artifact_attachment_count,
        "owned_file_count" => owned_files.count { |file| file.fetch("exists") },
        "owned_file_bytes" => owned_files.sum { |file| file.fetch("exists") ? file.fetch("size_bytes") : 0 }
      } }
    end

    def public_aggregate(data)
      {
        "records" => data.fetch("conversations").map do |item|
          {
            "id" => item.dig("chat", "id"),
            "title" => item.dig("chat", "title"),
            "message_count" => item.fetch("message_count"),
            "memory_count" => item.fetch("memory_ids").length,
            "artifact_count" => item.fetch("artifact_ids").length,
            "owned_file_count" => item.fetch("owned_files").count { |file| file.fetch("exists") }
          }
        end,
        "conversation_count" => data.fetch("conversation_count"),
        "message_count" => data.fetch("message_count"),
        "memory_count" => data.fetch("memory_ids").length,
        "artifact_count" => data.fetch("artifact_ids").length,
        "artifact_attachment_count" => data.fetch("artifact_attachment_count"),
        "owned_file_count" => data.fetch("owned_file_count"),
        "owned_file_bytes" => data.fetch("owned_file_bytes")
      }
    end

    def aggregate_digest(data)
      canonical = {
        "conversations" => data.fetch("conversations").map do |item|
          {
            "chat" => item.fetch("chat"),
            "message_count" => item.fetch("message_count"),
            "memory_ids" => item.fetch("memory_ids"),
            "artifact_ids" => item.fetch("artifact_ids"),
            "memory_inventory" => item.fetch("memory_inventory"),
            "artifact_inventory" => item.fetch("artifact_inventory"),
            "owned_files" => item.fetch("owned_files").map { |file| file.except("absolute_path") }
          }
        end,
        "memory_ids" => data.fetch("memory_ids"),
        "artifact_ids" => data.fetch("artifact_ids")
      }
      Digest::SHA256.hexdigest(JSON.generate(canonical))
    end

    def bulk_confirmation(count)
      "DELETE_AND_FORGET_#{count}_CONVERSATIONS"
    end

    def inventory_for(chat_id)
      id = chat_id.to_s.strip
      return awaiting("canonical chat_id is required") unless id.match?(CHAT_ID)

      files = owned_paths(id).map { |kind, path| inspect_owned_file(kind, path) }
      unsafe = files.find { |file| file["exists"] && !file["regular"] }
      return blocked("conversation-owned #{unsafe['kind']} path is not a regular file") if unsafe

      chat = @chat_store.chat(id)
      return awaiting("unknown chat ID") unless chat
      memories = memory_store.records(include_deleted: true).select do |record|
        record["status"] != "deleted" &&
          (record["chat_id"].to_s == id || record.dig("source", "reference").to_s == id)
      end
      artifacts = @artifact_store.list.select { |record| Array(record["attached_chat_ids"]).include?(id) }
      return blocked("linked memory count exceeds #{MAX_LINKS}") if memories.length > MAX_LINKS
      return blocked("attached artifact count exceeds #{MAX_LINKS}") if artifacts.length > MAX_LINKS

      { "ok" => true, "data" => {
        "chat" => chat.slice("id", "title", "created_at", "updated_at", "archived", "pinned"),
        "message_count" => @chat_store.messages(id, scan_limit: ChatStore::APPLICATION_SCAN_LIMIT).length,
        "memory_ids" => memories.map { |record| record.fetch("id") }.sort,
        "artifact_ids" => artifacts.map { |record| record.fetch("artifact_id") }.sort,
        "memory_inventory" => record_fingerprints(memories, id_key: "id"),
        "artifact_inventory" => record_fingerprints(artifacts, id_key: "artifact_id"),
        "owned_files" => files
      } }
    rescue RuntimeError => error
      blocked(error.message)
    end

    def owned_paths(chat_id)
      safe = chat_id.gsub(/[^a-zA-Z0-9_.-]/, "_")
      [
        ["messages", File.join(@root, ChatStore::DEFAULT_ROOT, "#{safe}.jsonl")],
        ["conversation_state", File.join(@root, "Soul/runtime/conversation_state", "#{safe}.json")],
        ["grounded_evidence", File.join(@root, "Soul/runtime/conversation_evidence", "#{safe}.jsonl")],
        ["metadata", File.join(@root, ChatStore::DEFAULT_ROOT, "#{safe}.json")]
      ]
    end

    def memory_store
      return @memory_store if @memory_store

      path = File.join(@root, ConversationMemoryStore::DEFAULT_PATH)
      File.file?(path) ? ConversationMemoryStore.new(root: @root) : EmptyMemoryStore.new
    end

    def inspect_owned_file(kind, path)
      stat = File.lstat(path)
      {
        "kind" => kind,
        "absolute_path" => path,
        "exists" => true,
        "regular" => stat.file? && !stat.symlink?,
        "size_bytes" => stat.size,
        "sha256" => stat.file? && !stat.symlink? ? Digest::SHA256.file(path).hexdigest : nil
      }
    rescue Errno::ENOENT
      { "kind" => kind, "absolute_path" => path, "exists" => false, "regular" => false, "size_bytes" => 0, "sha256" => nil }
    end

    def digest(data)
      canonical = {
        "chat" => data.fetch("chat"),
        "message_count" => data.fetch("message_count"),
        "memory_ids" => data.fetch("memory_ids"),
        "artifact_ids" => data.fetch("artifact_ids"),
        "memory_inventory" => data.fetch("memory_inventory"),
        "artifact_inventory" => data.fetch("artifact_inventory"),
        "owned_files" => data.fetch("owned_files").map { |file| file.except("absolute_path") }
      }
      Digest::SHA256.hexdigest(JSON.generate(canonical))
    end

    def record_fingerprints(records, id_key:)
      records.map do |record|
        { "id" => record.fetch(id_key), "sha256" => Digest::SHA256.hexdigest(JSON.generate(deep_sort(record))) }
      end.sort_by { |record| record.fetch("id") }
    end

    def deep_sort(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
      when Array then value.map { |item| deep_sort(item) }
      else value
      end
    end

    def retained_disclosure
      [
        "append-only memory events and logical-deletion tombstones",
        "artifact files and append-only artifact provenance events",
        "inbox delivery, application receipt, and safety/audit records",
        "previously exported memory snapshots"
      ]
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

    class EmptyMemoryStore
      def records(include_deleted: false)
        _unused = include_deleted
        []
      end
    end
  end
end
