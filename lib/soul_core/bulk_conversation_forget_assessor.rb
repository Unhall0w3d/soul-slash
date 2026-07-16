# frozen_string_literal: true

require "tmpdir"
require_relative "application_facade"
require_relative "conversation_clear_service"
require_relative "conversation_forget_service"

module SoulCore
  class BulkConversationForgetAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      details = {}

      Dir.mktmpdir("soul-bulk-forget-50-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        records = 50.times.map do |index|
          chat = chats.create_chat(initial_title: "Old conversation #{index + 1}")
          (index % 3 + 1).times { |message| chats.add_message(chat.fetch("id"), role: "user", content: "message #{message + 1}") }
          chat
        end
        ids = records.map { |record| record.fetch("id") }
        expected_messages = (0...50).sum { |index| index % 3 + 1 }
        service = ConversationForgetService.new(root: temp_root, chat_store: chats)

        before = owned_count(temp_root, ids)
        preview = service.preview_many(mode: "selected", chat_ids: ids)
        checks["fifty_selected_preview_as_fifty_with_aggregate_messages"] =
          preview["ok"] == true && preview.dig("data", "conversation_count") == 50 &&
          preview.dig("data", "message_count") == expected_messages && preview.dig("data", "records").length == 50 &&
          preview.dig("data", "confirmation_phrase") == "DELETE_AND_FORGET_50_CONVERSATIONS" && owned_count(temp_root, ids) == before

        wrong = service.execute_many(mode: "selected", chat_ids: ids, confirmation: "DELETE_AND_FORGET_CONVERSATION", expected_digest: preview.dig("data", "inventory_digest"))
        checks["wrong_confirmation_is_read_only"] = wrong["lifecycle_state"] == "awaiting_input" && owned_count(temp_root, ids) == before

        chats.add_message(ids.first, role: "user", content: "inventory drift")
        stale = service.execute_many(mode: "selected", chat_ids: ids, confirmation: "DELETE_AND_FORGET_50_CONVERSATIONS", expected_digest: preview.dig("data", "inventory_digest"))
        checks["stale_aggregate_inventory_blocks_before_mutation"] = stale["lifecycle_state"] == "blocked_for_human_review" && owned_count(temp_root, ids) == before

        fresh = service.preview_many(mode: "selected", chat_ids: ids)
        executed = service.execute_many(mode: "selected", chat_ids: ids, confirmation: "DELETE_AND_FORGET_50_CONVERSATIONS", expected_digest: fresh.dig("data", "inventory_digest"))
        checks["verified_bulk_execution_removes_all_conversation_owned_files"] =
          executed["ok"] == true && executed.dig("data", "conversation_count") == 50 && chats.list_chats.empty? && owned_count(temp_root, ids).zero?
        details["fifty_chat_message_count"] = fresh.dig("data", "message_count")
      end

      Dir.mktmpdir("soul-bulk-forget-scope-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        duplicate_a = chats.create_chat(initial_title: "Duplicate")
        duplicate_b = chats.create_chat(initial_title: "duplicate")
        other = chats.create_chat(initial_title: "Other")
        service = ConversationForgetService.new(root: temp_root, chat_store: chats)
        title = service.preview_many(mode: "title", title: "Duplicate")
        all = service.preview_many(mode: "all")
        duplicate_ids = title.dig("data", "records").map { |record| record.fetch("id") }.sort
        checks["title_and_all_scopes_are_exact"] = duplicate_ids == [duplicate_a.fetch("id"), duplicate_b.fetch("id")].sort && all.dig("data", "conversation_count") == 3
        checks["duplicate_or_invalid_selected_ids_await_input"] =
          service.preview_many(mode: "selected", chat_ids: [other.fetch("id"), other.fetch("id")])["lifecycle_state"] == "awaiting_input" &&
          service.preview_many(mode: "selected", chat_ids: ["../../etc"])["lifecycle_state"] == "awaiting_input"

        archive = ConversationClearService.new(root: temp_root, store: chats)
        archive_preview = archive.preview(mode: "selected", chat_ids: [other.fetch("id")])
        transcript = File.join(temp_root, ChatStore::DEFAULT_ROOT, "#{other.fetch('id')}.jsonl")
        archived = archive.execute(mode: "selected", chat_ids: [other.fetch("id")], confirmation: ConversationClearService::CONFIRMATION, expected_digest: archive_preview.dig("data", "match_digest"))
        checks["archive_remains_metadata_only_and_retains_transcript"] = archived["ok"] == true && File.file?(transcript) && chats.chat(other.fetch("id"))["archived"] == true
      end

      Dir.mktmpdir("soul-bulk-forget-cap-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        101.times { |index| chats.create_chat(initial_title: "Cap #{index}") }
        result = ConversationForgetService.new(root: temp_root, chat_store: chats).preview_many(mode: "all")
        checks["permanent_scope_is_capped_at_one_hundred"] = result["lifecycle_state"] == "blocked_for_human_review" && result["reason"].include?("exceeds 100")
      end

      Dir.mktmpdir("soul-bulk-forget-shared-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        first = chats.create_chat(initial_title: "Shared first")
        second = chats.create_chat(initial_title: "Shared second")
        memory = ConversationMemoryStore.new(root: temp_root)
        shared_memory = memory.propose(
          layer: "episodic", content: "shared derived context",
          source: { "kind" => "conversation", "reference" => second.fetch("id") },
          confidence: 0.9, chat_id: first.fetch("id")
        )
        memory.approve(shared_memory.fetch("id"))
        artifact_path = File.join(temp_root, "shared-artifact.txt")
        File.write(artifact_path, "retained artifact")
        artifacts = ConversationArtifactStore.new(root: temp_root)
        artifact = artifacts.register(path: "shared-artifact.txt", chat_id: first.fetch("id"))
        artifacts.attach(artifact.fetch("artifact_id"), chat_id: second.fetch("id"))
        ids = [first.fetch("id"), second.fetch("id")]
        service = ConversationForgetService.new(root: temp_root, chat_store: chats, memory_store: memory, artifact_store: artifacts)
        preview = service.preview_many(mode: "selected", chat_ids: ids)
        executed = service.execute_many(mode: "selected", chat_ids: ids, confirmation: "DELETE_AND_FORGET_2_CONVERSATIONS", expected_digest: preview.dig("data", "inventory_digest"))
        checks["shared_memory_is_forgotten_once"] =
          preview.dig("data", "memory_count") == 1 && executed.dig("data", "memory_ids_logically_deleted") == [shared_memory.fetch("id")] && memory.find(shared_memory.fetch("id"))["status"] == "deleted"
        checks["shared_artifact_is_detached_per_chat_and_file_retained"] =
          preview.dig("data", "artifact_count") == 1 && preview.dig("data", "artifact_attachment_count") == 2 &&
          executed.dig("data", "artifact_detachments").length == 2 && artifacts.find(artifact.fetch("artifact_id"))["attached_chat_ids"].empty? && File.read(artifact_path) == "retained artifact"
      end

      Dir.mktmpdir("soul-bulk-forget-partial-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        first = chats.create_chat(initial_title: "Partial first")
        second = chats.create_chat(initial_title: "Partial second")
        memory = FailingMemoryStore.new(first.fetch("id"), second.fetch("id"))
        service = ConversationForgetService.new(root: temp_root, chat_store: chats, memory_store: memory)
        ids = [first.fetch("id"), second.fetch("id")]
        preview = service.preview_many(mode: "selected", chat_ids: ids)
        result = service.execute_many(mode: "selected", chat_ids: ids, confirmation: "DELETE_AND_FORGET_2_CONVERSATIONS", expected_digest: preview.dig("data", "inventory_digest"))
        checks["partial_failure_stops_and_reports_completed_work"] =
          result["lifecycle_state"] == "blocked_for_human_review" && result.dig("data", "completed", "memory_ids") == ["memory_1"] &&
          memory.deleted == ["memory_1"] && ids.all? { |id| chats.chat(id) }
      end

      Dir.mktmpdir("soul-bulk-forget-facade-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        chat = chats.create_chat(initial_title: "Facade target")
        service = ConversationForgetService.new(root: temp_root, chat_store: chats)
        facade = ApplicationFacade.new(root: temp_root, process_env: {}, chat_store: chats, conversation_forget_service: service)
        envelope = facade.call(request("bulk:preview", "chats.forget_many.preview", { "mode" => "selected", "chat_ids" => [chat.fetch("id")] }))
        checks["facade_exposes_bounded_bulk_preview"] = envelope["lifecycle_state"] == "complete" && envelope.dig("data", "conversation_count") == 1 && envelope.dig("meta", "mutation") == "none"
      end

      html = File.read(File.join(@root, "assets/dashboard/index.html"))
      js = File.read(File.join(@root, "assets/dashboard/dashboard.js"))
      checks["dashboard_uses_one_visible_scope_for_two_distinct_actions"] =
        html.include?("Archive this scope") && html.include?("Permanently delete this scope") && html.include?("This cannot be undone") &&
        js.scan("const parameters = clearParameters();").length >= 2 && js.include?('callSoul("chats.clear.preview"') && js.include?('callSoul("chats.forget_many.preview"')
      checks["dashboard_uses_aggregate_counts_and_dynamic_confirmation"] =
        js.include?("data.conversation_count") && js.include?("data.message_count") && js.include?("data.confirmation_phrase") &&
        js.include?("state.forgetPreview.confirmation") && !js.match?(/setInterval|setTimeout/)

      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?, "assessment" => "bulk_conversation_archive_and_delete_forget", "phase" => "conversation-management-amendment",
        "status" => blockers.empty? ? "candidate_ready" : "blocked", "blockers" => blockers, "verification" => checks,
        "details" => details, "memory_keys" => ["shared conversation memories linked by exact chat_id"],
        "lifecycle_states" => %w[complete awaiting_input blocked_for_human_review],
        "risk_class" => "Class 5: Permanent local deletion", "human_review_required" => true
      }
    end

    private

    def owned_count(root, ids)
      ids.sum do |id|
        [File.join(root, ChatStore::DEFAULT_ROOT, "#{id}.json"), File.join(root, ChatStore::DEFAULT_ROOT, "#{id}.jsonl"),
         File.join(root, "Soul/runtime/conversation_state/#{id}.json"), File.join(root, "Soul/runtime/conversation_evidence/#{id}.jsonl")]
          .count { |path| File.file?(path) }
      end
    end

    def request(request_id, operation, parameters)
      { "schema_version" => ApplicationContract::SCHEMA_VERSION, "request_id" => request_id, "operation" => operation,
        "parameters" => parameters, "context" => { "interface" => "dashboard_test" } }
    end

    class FailingMemoryStore
      attr_reader :deleted

      def initialize(first_chat_id, second_chat_id)
        @records = [record("memory_1", first_chat_id), record("memory_2", second_chat_id)]
        @deleted = []
      end

      def records(include_deleted: false)
        _unused = include_deleted
        @records
      end

      def delete(memory_id, reason:)
        _unused = reason
        raise RuntimeError, "injected memory failure" if memory_id == "memory_2"

        @deleted << memory_id
      end

      private

      def record(id, chat_id)
        { "id" => id, "status" => "approved", "chat_id" => chat_id, "source" => { "kind" => "conversation", "reference" => chat_id } }
      end
    end
  end
end
