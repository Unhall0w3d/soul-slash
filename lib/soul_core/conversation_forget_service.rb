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
      public_data = data.merge("owned_files" => data.fetch("owned_files").map { |file| file.except("absolute_path") })
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

    private

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
        "owned_files" => data.fetch("owned_files").map { |file| file.except("absolute_path") }
      }
      Digest::SHA256.hexdigest(JSON.generate(canonical))
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
