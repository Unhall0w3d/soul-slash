# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "application_facade"
require_relative "conversation_forget_service"
require_relative "intent_router"
require_relative "skill_registry"
require_relative "skill_runner"

module SoulCore
  class ConversationForgetServiceAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      details = {}
      Dir.mktmpdir("soul-chats-forget-") do |temp_root|
        chats = ChatStore.new(root: temp_root)
        chat = chats.create_chat(initial_title: "Forget me")
        chat_id = chat.fetch("id")
        chats.add_message(chat_id, role: "user", content: "private conversation content")
        chats.add_message(chat_id, role: "assistant", content: "private response content")

        memory = ConversationMemoryStore.new(root: temp_root)
        linked = memory.propose(layer: "episodic", content: "derived private memory", source: { "kind" => "conversation", "reference" => chat_id }, confidence: 0.9, chat_id: chat_id)
        other = memory.propose(layer: "project", content: "unrelated memory", source: { "kind" => "conversation", "reference" => "chat_other" }, confidence: 0.9, chat_id: "chat_other")
        memory.approve(linked.fetch("id"))
        memory.approve(other.fetch("id"))

        artifact_path = File.join(temp_root, "notes.txt")
        File.write(artifact_path, "artifact content must remain")
        artifacts = ConversationArtifactStore.new(root: temp_root)
        artifact = artifacts.register(path: "notes.txt", title: "Retained artifact", chat_id: chat_id)
        state_path = File.join(temp_root, "Soul/runtime/conversation_state/#{chat_id}.json")
        evidence_path = File.join(temp_root, "Soul/runtime/conversation_evidence/#{chat_id}.jsonl")
        FileUtils.mkdir_p(File.dirname(state_path)); File.write(state_path, JSON.generate("last_user_message" => "private conversation content"))
        FileUtils.mkdir_p(File.dirname(evidence_path)); File.write(evidence_path, JSON.generate("output" => "private evidence content") + "\n")

        service = ConversationForgetService.new(root: temp_root, chat_store: chats, memory_store: memory, artifact_store: artifacts)
        invalid = service.preview(chat_id: "../../etc")
        unknown = service.preview(chat_id: "chat_unknown")
        checks["exact_canonical_chat_id_is_required"] = [invalid, unknown].all? { |result| result["lifecycle_state"] == "awaiting_input" }

        before = owned_snapshot(temp_root, chat_id)
        preview = service.preview(chat_id: chat_id)
        checks["preview_is_complete_bounded_and_read_only"] =
          preview["ok"] == true && preview.dig("data", "message_count") == 2 &&
          preview.dig("data", "memory_ids") == [linked.fetch("id")] &&
          preview.dig("data", "artifact_ids") == [artifact.fetch("artifact_id")] &&
          preview.dig("data", "confirmation_phrase") == ConversationForgetService::CONFIRMATION &&
          before == owned_snapshot(temp_root, chat_id) && memory.find(linked.fetch("id"))["status"] == "approved"

        wrong = service.execute(chat_id: chat_id, confirmation: "DELETE", expected_digest: preview.dig("data", "inventory_digest"))
        missing = service.execute(chat_id: chat_id, confirmation: ConversationForgetService::CONFIRMATION, expected_digest: nil)
        checks["execution_requires_exact_confirmation_and_digest"] =
          [wrong, missing].all? { |result| result["lifecycle_state"] == "awaiting_input" } && before == owned_snapshot(temp_root, chat_id)

        chats.add_message(chat_id, role: "user", content: "inventory drift")
        stale = service.execute(chat_id: chat_id, confirmation: ConversationForgetService::CONFIRMATION, expected_digest: preview.dig("data", "inventory_digest"))
        checks["inventory_drift_blocks_before_mutation"] =
          stale["lifecycle_state"] == "blocked_for_human_review" && chats.chat(chat_id) && memory.find(linked.fetch("id"))["status"] == "approved"

        fresh = service.preview(chat_id: chat_id)
        executed = service.execute(chat_id: chat_id, confirmation: ConversationForgetService::CONFIRMATION, expected_digest: fresh.dig("data", "inventory_digest"))
        checks["verified_execution_deletes_conversation_owned_content"] =
          executed["ok"] == true && chats.chat(chat_id).nil? && owned_snapshot(temp_root, chat_id).values.none? &&
          executed.dig("data", "deleted_file_kinds").sort == %w[conversation_state grounded_evidence messages metadata]
        checks["linked_memory_is_logically_deleted_but_unrelated_memory_remains_retrievable"] =
          memory.find(linked.fetch("id"))["status"] == "deleted" && !memory.context_for(query: "derived private", chat_id: "chat_other")["record_ids"].include?(linked.fetch("id")) &&
          memory.find(other.fetch("id"))["status"] == "approved"
        checks["artifact_is_detached_without_deleting_artifact_or_audit_ledger"] =
          !artifacts.find(artifact.fetch("artifact_id"))["attached_chat_ids"].include?(chat_id) && File.read(artifact_path) == "artifact content must remain" &&
          artifacts.events.any? { |event| event["event_type"] == "detached" && event.dig("payload", "chat_id") == chat_id }
        checks["retained_append_only_memory_ledger_is_disclosed"] =
          File.read(memory.path).include?("derived private memory") && preview.dig("data", "retained").any? { |item| item.include?("memory events") }

        repeated = service.preview(chat_id: chat_id)
        checks["deleted_conversation_cannot_be_silently_retargeted"] = repeated["lifecycle_state"] == "awaiting_input"

        facade_root = File.join(temp_root, "facade")
        facade_chats = ChatStore.new(root: facade_root)
        facade_chat = facade_chats.create_chat(initial_title: "Facade forget target")
        facade_service = ConversationForgetService.new(root: facade_root, chat_store: facade_chats)
        facade = ApplicationFacade.new(root: facade_root, process_env: {}, chat_store: facade_chats, conversation_forget_service: facade_service)
        envelope = facade.call(request("facade:forget:preview", "chats.forget.preview", { "chat_id" => facade_chat.fetch("id") }))
        checks["application_facade_exposes_read_only_preview"] = !!(
          envelope["lifecycle_state"] == "complete" && envelope.dig("meta", "mutation") == "none" &&
          facade_chats.chat(facade_chat.fetch("id")) && !File.exist?(File.join(facade_root, ConversationMemoryStore::DEFAULT_PATH))
        )
        checks["preview_does_not_expose_absolute_owned_paths"] = envelope.dig("data", "owned_files").all? { |file| !file.key?("absolute_path") }

        intent = IntentRouter.new.route("delete and forget this conversation")
        checks["destructive_intent_routes_before_archival_intent"] = intent.skill_id == "chats.forget" && intent.confirmation_required == true

        runner_blocked = begin
          SkillRunner.new(registry: SkillRegistry.new(path: File.join(@root, "Soul/skills/registry.yaml"))).run("chats.forget", args: ["--execute", "--chat-id", "chat_fixture", "--expected-digest", "0" * 64])
          false
        rescue RuntimeError => error
          error.message.include?("exact confirmation")
        end
        checks["skill_runner_keeps_independent_confirmation_gate"] = runner_blocked

        html = File.read(File.join(@root, "assets/dashboard/index.html"))
        js = File.read(File.join(@root, "assets/dashboard/dashboard.js"))
        checks["dashboard_exposes_separate_scoped_bulk_permanent_route"] =
          html.include?("forget-confirmation-phrase") && html.include?("append-only safety records remain") &&
          js.include?('callSoul("chats.forget_many.preview"') && js.include?('callSoul("chats.forget_many.execute"') &&
          js.index('callSoul("chats.forget_many.preview"') < js.index('callSoul("chats.forget_many.execute"') &&
          js.include?("state.forgetPreview.confirmation") && !js.include?("innerHTML")

        details["deleted_chat_id"] = chat_id
        details["logically_deleted_memory_count"] = executed.dig("data", "memory_ids_logically_deleted").length
        details["detached_artifact_count"] = executed.dig("data", "artifact_ids_detached").length
      end

      Dir.mktmpdir("soul-chats-forget-symlink-") do |temp_root|
        target = File.join(temp_root, "external.json")
        File.write(target, JSON.generate("id" => "chat_symlink", "title" => "Must not read"))
        chat_root = File.join(temp_root, ChatStore::DEFAULT_ROOT)
        FileUtils.mkdir_p(chat_root)
        File.symlink(target, File.join(chat_root, "chat_symlink.json"))
        result = ConversationForgetService.new(root: temp_root).preview(chat_id: "chat_symlink")
        checks["symlinked_conversation_owned_path_blocks_before_content_read"] =
          result["lifecycle_state"] == "blocked_for_human_review" && result["reason"].include?("not a regular file") && File.exist?(target)
      end

      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?, "assessment" => "conversation_delete_and_forget_skill", "phase" => "12C-amendment",
        "status" => blockers.empty? ? "candidate_ready" : "blocked", "blockers" => blockers,
        "verification" => checks, "details" => details, "memory_keys" => ["shared conversation memories linked by exact chat_id"],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 5: Permanent local deletion", "human_review_required" => true
      }
    end

    private

    def owned_snapshot(root, chat_id)
      paths = [
        File.join(root, ChatStore::DEFAULT_ROOT, "#{chat_id}.json"), File.join(root, ChatStore::DEFAULT_ROOT, "#{chat_id}.jsonl"),
        File.join(root, "Soul/runtime/conversation_state/#{chat_id}.json"), File.join(root, "Soul/runtime/conversation_evidence/#{chat_id}.jsonl")
      ]
      paths.select { |path| File.file?(path) }.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
    end

    def request(request_id, operation, parameters)
      { "schema_version" => ApplicationContract::SCHEMA_VERSION, "request_id" => request_id, "operation" => operation, "parameters" => parameters, "context" => { "interface" => "dashboard_test" } }
    end
  end
end
