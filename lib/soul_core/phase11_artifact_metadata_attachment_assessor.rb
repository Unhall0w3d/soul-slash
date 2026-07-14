# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "conversation_artifact_controls"
require_relative "conversation_artifact_decision_policy"
require_relative "conversation_artifact_store"
require_relative "conversation_context_builder"

module SoulCore
  class Phase11ArtifactMetadataAttachmentAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      verification = {}
      sample = {}

      Dir.mktmpdir("soul-phase11-artifacts") do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "docs"))
        sample_path = File.join(tmp, "docs", "sample-report.md")
        secret_body = "INTERNAL-CONTENT-MUST-NOT-ENTER-CONTEXT\n"
        File.write(sample_path, secret_body)
        original_digest = Digest::SHA256.file(sample_path).hexdigest

        clock_index = 0
        clock = lambda do
          clock_index += 1
          Time.utc(2026, 7, 12, 5, 0, clock_index)
        end

        store = ConversationArtifactStore.new(root: tmp, clock: clock)
        policy = ConversationArtifactDecisionPolicy.new
        controls = ConversationArtifactControls.new(root: tmp, store: store)

        unconfirmed = controls.respond(
          "register artifact: docs/sample-report.md | Sample report | report | project",
          chat_id: "chat-a"
        )
        verification["registration_requires_confirmation"] =
          unconfirmed.include?("Confirmation required") && store.list.empty?

        registered = controls.respond(
          "register artifact: docs/sample-report.md | Sample report | report | project confirm",
          chat_id: "chat-a"
        )
        record = store.list.first
        verification["confirmed_registration_records_metadata"] =
          registered.include?("metadata_registered") && record&.fetch("kind") == "report"
        verification["registration_preserves_file_contents"] =
          Digest::SHA256.file(sample_path).hexdigest == original_digest
        verification["artifact_metadata_has_provenance"] =
          record&.dig("source", "kind") == "manual_registration" &&
          record&.dig("source", "chat_id") == "chat-a" &&
          record&.fetch("sha256") == original_digest
        verification["artifact_is_attached_to_origin_chat"] =
          store.context_for(chat_id: "chat-a").fetch("artifact_ids").include?(record.fetch("artifact_id"))
        verification["artifact_is_not_attached_to_other_chats"] =
          store.context_for(chat_id: "chat-b").fetch("records").empty?

        builder = ConversationContextBuilder.new(
          store: FakeChatStore.new(tmp),
          memory_store: EmptyMemoryStore.new,
          interest_store: EmptyInterestStore.new,
          artifact_store: store,
          identity_profile: FakeIdentityProfile.new,
          style_analyzer: FakeStyleAnalyzer.new
        )
        context = builder.build(chat_id: "chat-a")
        system_prompt = context.fetch("messages").first.fetch("content")
        verification["context_injects_attached_artifact_metadata"] =
          system_prompt.include?(record.fetch("artifact_id")) &&
          context.dig("artifacts", "count") == 1
        verification["context_does_not_inject_artifact_contents"] =
          !system_prompt.include?(secret_body.strip) && context.dig("artifacts", "metadata_only") == true
        verification["context_declares_no_mutation_authority"] =
          system_prompt.include?("does not grant permission to read, rewrite, move, execute, upload, or delete")

        controls.respond("detach artifact #{record.fetch('artifact_id')}", chat_id: "chat-a")
        verification["detached_artifacts_leave_context"] =
          store.context_for(chat_id: "chat-a").fetch("records").empty?
        controls.respond("attach artifact #{record.fetch('artifact_id')}", chat_id: "chat-b")
        archive_preview = controls.respond("archive artifact #{record.fetch('artifact_id')}", chat_id: "chat-b")
        verification["archive_requires_confirmation"] =
          archive_preview.include?("Confirmation required") && store.find(record.fetch("artifact_id"))["lifecycle"] == "active"
        controls.respond("archive artifact #{record.fetch('artifact_id')} confirm", chat_id: "chat-b")
        verification["archived_artifacts_leave_context"] =
          store.context_for(chat_id: "chat-b").fetch("records").empty?
        verification["archive_does_not_delete_file"] = File.file?(sample_path)
        verification["artifact_events_are_append_only"] =
          store.events.map { |event| event.fetch("event_type") } == %w[registered detached attached archived]

        File.write(File.join(tmp, ".env"), "SECRET=example\n")
        blocked = begin
          store.register(path: ".env", chat_id: "chat-a")
          false
        rescue ArgumentError
          true
        end
        verification["reserved_local_state_is_blocked"] = blocked

        FileUtils.mkdir_p(File.join(tmp, ".ssh"))
        File.write(File.join(tmp, ".ssh", "id_ed25519"), "not-a-real-key\n")
        private_key_blocked = begin
          store.register(path: ".ssh/id_ed25519", chat_id: "chat-a")
          false
        rescue ArgumentError
          true
        end
        verification["private_key_paths_are_blocked"] = private_key_blocked

        registry_self_blocked = begin
          store.register(path: ConversationArtifactStore::DEFAULT_RELATIVE_PATH, chat_id: "chat-a")
          false
        rescue ArgumentError
          true
        end
        verification["artifact_registry_cannot_register_itself"] = registry_self_blocked

        explicit = policy.classify("Please produce a downloadable implementation report")
        ordinary = policy.classify("Can you explain what a file descriptor is?")
        review = policy.classify("Please review this file path and tell me what it means")
        verification["explicit_deliverables_require_artifacts"] = explicit.required?
        verification["ordinary_file_language_stays_in_chat"] = !ordinary.artifact? && !review.artifact?

        sample = {
          "record" => record,
          "decision" => explicit.to_h,
          "context" => context.fetch("artifacts"),
          "event_types" => store.events.map { |event| event.fetch("event_type") }
        }
      end

      verification["canonical_artifact_document_exists"] =
        File.file?(File.join(@root, "docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md"))
      verification["phase11_assessment_document_exists"] =
        File.file?(File.join(@root, "docs/assessments/CONVERSATIONAL_SOUL_PHASE11_ARTIFACT_FOUNDATION.md"))

      blockers = verification.select { |_name, value| value != true }.keys
      {
        "ok" => blockers.empty?,
        "assessment" => "phase11_artifact_metadata_attachment",
        "milestone" => "conversational_soul",
        "phase" => 11,
        "slice" => "11A",
        "status" => blockers.empty? ? "ready" : "blocked",
        "sample" => sample,
        "verification" => verification,
        "blockers" => blockers
      }
    end

    def render(report)
      lines = [
        "Soul Phase 11 Artifact Metadata and Attachment Foundation Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']} (#{report['slice']})",
        "Status: #{report['status']}",
        "",
        "Verification"
      ]
      report.fetch("verification").each do |name, value|
        lines << "- #{name}: #{value}"
      end
      lines << ""
      lines << "Blockers"
      if report.fetch("blockers").empty?
        lines << "- None"
      else
        report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      end
      lines.join("\n")
    end

    class FakeChatStore
      attr_reader :project_root

      def initialize(project_root)
        @project_root = project_root
      end

      def chat(chat_id)
        { "chat_id" => chat_id, "summary" => "" }
      end

      def messages(_chat_id)
        [
          { "role" => "user", "content" => "Summarize the attached report metadata." }
        ]
      end
    end

    class EmptyMemoryStore
      def context_for(query:, chat_id:, limit:)
        { "records" => [], "record_ids" => [], "layers" => [], "count" => 0, "rendered" => "" }
      end
    end

    class EmptyInterestStore
      def context_for(query:, limit:)
        { "records" => [], "record_ids" => [], "count" => 0, "reviewed_only" => true, "automatic_inference" => false, "rendered" => "" }
      end
    end

    class FakeIdentityProfile
      def context_for(message:)
        {
          "profile_id" => "soul.identity.v1",
          "profile_version" => 2,
          "tone_mode" => "technical",
          "tone_label" => "Exact",
          "automatic_identity_mutation" => false
        }
      end

      def render_system_guidance(message:)
        "Declared identity guidance."
      end
    end

    class FakeStyleAnalyzer
      def analyze(messages:)
        {
          "window_size" => 8,
          "assistant_sample_count" => 0,
          "eligible" => false,
          "signals" => [],
          "guidance" => [],
          "automatic_identity_mutation" => false,
          "persistent_style_profile" => false
        }
      end

      def render_system_guidance(_style)
        ""
      end
    end
  end
end
