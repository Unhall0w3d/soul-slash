# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "chat_store"
require_relative "conversation_artifact_creation_service"
require_relative "conversation_artifact_inbox_store"
require_relative "conversation_artifact_store"
require_relative "conversation_context_builder"
require_relative "conversation_orchestrator"
require_relative "conversation_provider_contract"
require_relative "conversation_workspace_controls"
require_relative "conversation_workspace_service"

module SoulCore
  class Phase11dSharedWorkspaceInboxAssessor
    Contract = ConversationProviderContract

    class FakeProviderClient
      def initialize(contents)
        @contents = contents.dup
      end

      def chat(provider:, request:, timeout_seconds:)
        _unused = timeout_seconds
        Contract::ResponseEnvelope.new(
          request_id: request.request_id,
          provider_id: provider.id,
          model: provider.model,
          content: @contents.shift.to_s,
          finish_reason: "stop",
          latency_ms: 1.0
        )
      end
    end

    class FailingInboxStore
      def deliver(**_kwargs)
        raise IOError, "simulated inbox append failure"
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      details = {}

      Dir.mktmpdir("soul-phase11d-") do |temp_root|
        chat_id = "chat_phase11d"
        other_chat = "chat_other"
        artifact_store = ConversationArtifactStore.new(root: temp_root)
        inbox_store = ConversationArtifactInboxStore.new(root: temp_root)
        workspace = ConversationWorkspaceService.new(
          root: temp_root,
          artifact_store: artifact_store,
          inbox_store: inbox_store
        )

        empty = workspace.inbox(chat_id: chat_id)
        checks["empty_workspace_completes_without_mutation"] =
          empty["lifecycle_state"] == "complete" && empty["count"] == 0 && !File.exist?(inbox_store.path)

        source = register_fixture(
          temp_root,
          artifact_store,
          path: "source.md",
          content: "# Source\n\nCanonical source bytes.\n",
          chat_id: chat_id,
          privacy: "project"
        )
        private_artifact = register_fixture(
          temp_root,
          artifact_store,
          path: "private.txt",
          content: "private workspace fixture\n",
          chat_id: chat_id,
          privacy: "local_private"
        )
        unattached = register_fixture(
          temp_root,
          artifact_store,
          path: "unattached.txt",
          content: "not attached\n",
          chat_id: nil,
          privacy: "project"
        )
        archived = register_fixture(
          temp_root,
          artifact_store,
          path: "archived.txt",
          content: "archived\n",
          chat_id: chat_id,
          privacy: "project"
        )
        artifact_store.archive(archived.fetch("artifact_id"))

        original_bytes = File.binread(File.join(temp_root, source.fetch("relative_path")))
        first_delivery = workspace.deliver(artifact_id: source.fetch("artifact_id"), chat_id: chat_id)
        duplicate_delivery = workspace.deliver(artifact_id: source.fetch("artifact_id"), chat_id: chat_id)
        checks["delivery_is_append_only_and_idempotent"] =
          first_delivery["lifecycle_state"] == "complete" &&
          duplicate_delivery.dig("delivery", "idempotent") == true &&
          inbox_store.events.count { |event| event["event_type"] == "delivered" } == 1

        delivery_id = first_delivery.dig("delivery", "delivery_id")
        seen = workspace.change_state(delivery_id: delivery_id, chat_id: chat_id, state: "seen")
        seen_again = workspace.change_state(delivery_id: delivery_id, chat_id: chat_id, state: "seen")
        dismissed = workspace.change_state(delivery_id: delivery_id, chat_id: chat_id, state: "dismissed")
        checks["inbox_state_events_do_not_mutate_artifact"] =
          seen["delivery_state"] == "seen" &&
          seen_again.dig("delivery", "idempotent") == true &&
          dismissed["delivery_state"] == "dismissed" &&
          File.binread(File.join(temp_root, source.fetch("relative_path"))) == original_bytes &&
          artifact_store.find(source.fetch("artifact_id"))["lifecycle"] == "active"

        cross_chat = workspace.change_state(delivery_id: delivery_id, chat_id: other_chat, state: "seen")
        checks["cross_chat_inbox_state_is_rejected"] =
          cross_chat["lifecycle_state"] == "failed" &&
          inbox_store.find(delivery_id)["latest_delivery_state"] == "dismissed"

        missing_attachment = workspace.deliver(artifact_id: unattached.fetch("artifact_id"), chat_id: chat_id)
        inactive = workspace.deliver(artifact_id: archived.fetch("artifact_id"), chat_id: chat_id)
        unknown = workspace.detail(artifact_id: "art_unknown")
        checks["unknown_detached_and_inactive_artifacts_do_not_deliver"] =
          missing_attachment["lifecycle_state"] == "awaiting_input" &&
          inactive["lifecycle_state"] == "blocked_for_human_review" &&
          unknown["lifecycle_state"] == "awaiting_input"

        revision = register_fixture(
          temp_root,
          artifact_store,
          path: "revision.md",
          content: "# Revision\n",
          chat_id: chat_id,
          privacy: "project",
          revision_of_artifact_id: source.fetch("artifact_id")
        )
        revision_detail = workspace.detail(artifact_id: revision.fetch("artifact_id"))
        checks["workspace_projection_reuses_canonical_identity_and_revision"] =
          revision_detail.dig("record", "artifact_id") == revision.fetch("artifact_id") &&
          revision_detail.dig("record", "revision_of_artifact_id") == source.fetch("artifact_id") &&
          revision_detail.dig("record", "metadata_only") == true &&
          revision_detail.dig("record", "content_read") == false

        broken_root = File.join(temp_root, "broken-project")
        FileUtils.mkdir_p(broken_root)
        broken_artifact_store = ConversationArtifactStore.new(root: broken_root)
        broken_workspace = ConversationWorkspaceService.new(root: broken_root, artifact_store: broken_artifact_store)
        broken_revision = register_fixture(
          broken_root,
          broken_artifact_store,
          path: "broken-revision.md",
          content: "# Broken revision provenance\n",
          chat_id: chat_id,
          privacy: "project",
          revision_of_artifact_id: "art_missing_source"
        )
        checks["inconsistent_revision_provenance_blocks_for_review"] =
          broken_workspace.detail(artifact_id: broken_revision.fetch("artifact_id"))["lifecycle_state"] == "blocked_for_human_review" &&
          broken_workspace.list["lifecycle_state"] == "blocked_for_human_review"

        workspace.deliver(artifact_id: private_artifact.fetch("artifact_id"), chat_id: chat_id)
        provider_context = workspace.context_for(
          chat_id: chat_id,
          provider_privacy_class: "local_network"
        )
        checks["provider_context_filters_incompatible_privacy"] =
          provider_context.fetch("artifact_ids").include?(source.fetch("artifact_id")) &&
          !provider_context.fetch("artifact_ids").include?(private_artifact.fetch("artifact_id"))

        corrupt_inbox = ConversationArtifactInboxStore.new(
          root: temp_root,
          path: File.join(temp_root, "corrupt-inbox.jsonl")
        )
        corrupt_snapshot = source.merge("sha256" => "0" * 64)
        corrupt_inbox.deliver(
          artifact: corrupt_snapshot,
          originating_chat_id: chat_id,
          recipient_chat_id: chat_id,
          reason: "corrupt_fixture"
        )
        corrupt_workspace = ConversationWorkspaceService.new(
          root: temp_root,
          artifact_store: artifact_store,
          inbox_store: corrupt_inbox
        )
        orphan_inbox = ConversationArtifactInboxStore.new(
          root: temp_root,
          path: File.join(temp_root, "orphan-inbox.jsonl")
        )
        orphan_inbox.deliver(
          artifact: source.merge("artifact_id" => "art_orphan"),
          originating_chat_id: chat_id,
          recipient_chat_id: chat_id,
          reason: "orphan_fixture"
        )
        orphan_workspace = ConversationWorkspaceService.new(
          root: temp_root,
          artifact_store: artifact_store,
          inbox_store: orphan_inbox
        )
        checks["inconsistent_delivery_provenance_blocks_for_review"] =
          corrupt_workspace.detail(artifact_id: source.fetch("artifact_id"))["lifecycle_state"] == "blocked_for_human_review" &&
          corrupt_workspace.list["lifecycle_state"] == "blocked_for_human_review" &&
          orphan_workspace.inbox(chat_id: chat_id)["lifecycle_state"] == "blocked_for_human_review" &&
          orphan_workspace.list["lifecycle_state"] == "blocked_for_human_review"

        52.times do |index|
          register_fixture(
            temp_root,
            artifact_store,
            path: "bulk-#{index}.txt",
            content: "bulk #{index}\n",
            chat_id: chat_id,
            privacy: "project"
          )
        end
        bounded = workspace.list(chat_id: chat_id, limit: 500)
        checks["workspace_queries_are_stable_and_capped"] =
          bounded["count"] == 50 && bounded["limit"] == 50 &&
          bounded.fetch("records").map { |record| record.fetch("workspace_updated_at") } ==
            bounded.fetch("records").map { |record| record.fetch("workspace_updated_at") }.sort.reverse

        controls = ConversationWorkspaceControls.new(root: temp_root, service: workspace)
        controls_list = controls.respond("What is in my workspace?", chat_id: chat_id)
        controls_ambiguous = controls.respond("Send that to the inbox.", chat_id: chat_id)
        controls_watch = controls.respond("Keep watching the workspace and tell me when something changes.", chat_id: chat_id)
        controls_cancel = controls.respond("cancel workspace request", chat_id: chat_id)
        checks["conversation_controls_have_explicit_terminal_behavior"] =
          controls_list.include?("Lifecycle: complete") &&
          controls_ambiguous.include?("Lifecycle: awaiting_input") &&
          controls_watch.include?("Lifecycle: failed") &&
          controls_cancel.include?("Lifecycle: canceled")

        orchestrator = ConversationOrchestrator.new
        route = orchestrator.plan(message: "show workspace", provider_available: true)
        checks["workspace_routes_deterministically_without_model_requirement"] =
          route.kind == "deterministic_passthrough" && route.flags["workspace_control"] == true && route.requires_model == false

        chat_store = ChatStore.new(root: temp_root, chat_root: "Soul/runtime/phase11d-context-chats")
        context_chat = chat_store.create_chat(initial_title: "Phase 11D context").fetch("id")
        artifact_store.attach(source.fetch("artifact_id"), chat_id: context_chat)
        inbox_store.deliver(
          artifact: artifact_store.find(source.fetch("artifact_id")),
          originating_chat_id: chat_id,
          recipient_chat_id: context_chat,
          reason: "context_fixture"
        )
        context = ConversationContextBuilder.new(
          store: chat_store,
          artifact_store: artifact_store,
          workspace_service: workspace
        ).build(chat_id: context_chat, provider_privacy_class: "local_only")
        checks["conversation_context_labels_workspace_as_metadata_only"] =
          context.dig("workspace", "artifact_ids").include?(source.fetch("artifact_id")) &&
          context.dig("workspace", "metadata_only") == true &&
          context.dig("workspace", "content_read") == false &&
          context.fetch("messages").first.fetch("content").include?("Delivery does not grant permission")

        auto_client = FakeProviderClient.new(["# Automatically delivered\n"])
        auto_service = ConversationArtifactCreationService.new(
          root: temp_root,
          provider_client: auto_client,
          artifact_store: artifact_store,
          inbox_store: inbox_store
        )
        auto_preview = auto_service.preview(
          chat_id: chat_id,
          message: "Create a report at artifacts/phase11d-auto.md with project privacy.",
          provider: local_provider
        )
        auto_created = auto_service.execute(
          token_id: auto_preview.fetch("token_id"),
          confirm: true,
          chat_id: chat_id
        )
        checks["phase11c_completion_delivers_synchronously"] =
          auto_created["lifecycle_state"] == "complete" &&
          auto_created["delivery_state"] == "new" &&
          inbox_store.find(auto_created.fetch("delivery_id"))["artifact_id"] == auto_created.fetch("artifact_id")

        failed_delivery_service = ConversationArtifactCreationService.new(
          root: temp_root,
          provider_client: FakeProviderClient.new(["# Preserved artifact\n"]),
          artifact_store: artifact_store,
          inbox_store: FailingInboxStore.new
        )
        failed_preview = failed_delivery_service.preview(
          chat_id: chat_id,
          message: "Create a report at artifacts/delivery-failure.md with project privacy.",
          provider: local_provider
        )
        failed_delivery = failed_delivery_service.execute(
          token_id: failed_preview.fetch("token_id"),
          confirm: true,
          chat_id: chat_id
        )
        checks["inbox_failure_preserves_truthful_artifact_completion"] =
          failed_delivery["lifecycle_state"] == "complete" &&
          failed_delivery["delivery_state"] == "failed" &&
          File.file?(File.join(temp_root, "artifacts", "delivery-failure.md")) &&
          !artifact_store.find(failed_delivery.fetch("artifact_id")).nil?

        failed_workspace = ConversationWorkspaceService.new(
          root: temp_root,
          artifact_store: artifact_store,
          inbox_store: FailingInboxStore.new
        )
        explicit_failure = failed_workspace.deliver(artifact_id: source.fetch("artifact_id"), chat_id: chat_id)
        checks["explicit_inbox_append_failure_is_visible"] =
          explicit_failure["lifecycle_state"] == "failed" &&
          File.binread(File.join(temp_root, source.fetch("relative_path"))) == original_bytes

        checks["inbox_store_is_private_runtime_state"] =
          (File.stat(inbox_store.path).mode & 0o777) == 0o600

        details["delivery_id"] = delivery_id
        details["auto_delivery_id"] = auto_created["delivery_id"]
        details["workspace_record_cap"] = bounded["count"]
      end

      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "phase11d_shared_workspace_inbox",
        "milestone" => "conversational_soul",
        "phase" => "11D",
        "status" => blockers.empty? ? "candidate_ready" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "details" => details,
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 2: Local state write, non-destructive",
        "human_review_required" => true
      }
    end

    def render(report)
      lines = [
        "Soul Phase 11D Shared Workspace and Artifact Inbox Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}",
        "Status: #{report['status']}",
        "",
        "Verification"
      ]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def register_fixture(root, store, path:, content:, chat_id:, privacy:, revision_of_artifact_id: nil)
      File.write(File.join(root, path), content)
      store.register(
        path: path,
        title: File.basename(path),
        kind: "document",
        privacy: privacy,
        chat_id: chat_id,
        source: { "kind" => "manual_registration", "reference" => "phase11d_fixture" },
        revision_of_artifact_id: revision_of_artifact_id
      )
    end

    def local_provider
      Contract::ProviderDefinition.new(
        id: "local.phase11d",
        label: "Phase 11D local provider",
        transport: "openai_compatible",
        endpoint: "http://127.0.0.1:1/v1",
        model: "phase11d-model",
        privacy_class: "local_only",
        capabilities: %w[chat],
        configured: true
      )
    end
  end
end
