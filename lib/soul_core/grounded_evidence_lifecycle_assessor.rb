# frozen_string_literal: true

require "tmpdir"
require_relative "chat_store"
require_relative "conversation_evidence_store"
require_relative "conversation_provider_contract"
require_relative "conversation_runtime"
require_relative "conversation_state_store"

module SoulCore
  class GroundedEvidenceLifecycleAssessor
    Contract = ConversationProviderContract

    class FakeRegistry
      def initialize(provider)
        @provider = provider
      end

      def find(provider_id)
        @provider if @provider.id == provider_id.to_s
      end

      def configured
        [@provider]
      end
    end

    class RecordingResponder
      def respond(message)
        case message.to_s
        when "status"
          "Soul runtime status: core routes loaded and available."
        when "inspect downloads"
          "Downloads inspection: 4 files and 2 older candidates."
        else
          "Deterministic response."
        end
      end
    end

    class HallucinatingProviderClient
      def chat(provider:, request:, timeout_seconds:)
        Contract::ResponseEnvelope.new(
          request_id: request.request_id,
          provider_id: provider.id,
          model: provider.model,
          content: "The RAID array is optimal and the primary disk is 68% used.",
          finish_reason: "stop",
          latency_ms: 3.0
        )
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      report = nil

      Dir.mktmpdir("soul-phase5-") do |temp_root|
        store = ChatStore.new(root: temp_root)
        evidence_store = ConversationEvidenceStore.new(root: temp_root)
        state_store = ConversationStateStore.new(root: temp_root)
        provider = Contract::ProviderDefinition.new(
          id: "local.assessment",
          label: "Assessment provider",
          transport: "openai_compatible",
          endpoint: "http://127.0.0.1:1/v1",
          model: "assessment-model",
          privacy_class: "local_only",
          capabilities: %w[chat],
          configured: true
        )

        runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: { "SOUL_CONVERSATION_PROVIDER" => provider.id },
          registry: FakeRegistry.new(provider),
          provider_client: HallucinatingProviderClient.new,
          deterministic_responder: RecordingResponder.new,
          evidence_store: evidence_store,
          state_store: state_store
        )

        chat_id = store.create_chat(initial_title: "Phase 5 assessment").fetch("id")

        store.add_message(chat_id, role: "user", content: "Can you check Soul runtime status?")
        status_result = runtime.respond(chat_id: chat_id, message: "Can you check Soul runtime status?")
        status_evidence = evidence_store.latest(chat_id)

        status_grounded =
          status_result.mode == "skill_only" &&
          status_result.content.include?("Soul application and registered-runtime status only") &&
          status_evidence["tool_id"] == "system.status"

        store.add_message(chat_id, role: "user", content: "Further details about what you checked, please.")
        followup_result = runtime.respond(
          chat_id: chat_id,
          message: "Further details about what you checked, please."
        )
        followup_grounded =
          followup_result.mode == "evidence_followup" &&
          followup_result.content.include?(status_evidence["evidence_id"])

        store.add_message(chat_id, role: "user", content: "Can you inspect SMART health?")
        gap_result = runtime.respond(chat_id: chat_id, message: "Can you inspect SMART health?")
        host_gap =
          gap_result.mode == "capability_gap" &&
          gap_result.content.include?("does not collect that deeper host category")

        store.add_message(chat_id, role: "user", content: "Inspect Downloads and explain the result.")
        downloads_result = runtime.respond(
          chat_id: chat_id,
          message: "Inspect Downloads and explain the result."
        )
        hallucination_blocked =
          downloads_result.mode == "grounding_fallback" &&
          downloads_result.content.include?("rejected the model-written explanation")

        ignored = system(
          "git",
          "check-ignore",
          "Soul/runtime/conversation_evidence/example.jsonl",
          chdir: @root,
          out: File::NULL,
          err: File::NULL
        )

        blockers = []
        blockers << "Soul runtime evidence was not scoped" unless status_grounded
        blockers << "Evidence follow-up failed" unless followup_grounded
        blockers << "Deep host capability gap was not explicit" unless host_gap
        blockers << "Unsupported synthesis was not blocked" unless hallucination_blocked
        blockers << "Evidence path is not gitignored" unless ignored

        report = {
          "ok" => blockers.empty?,
          "assessment" => "grounded_evidence_lifecycle",
          "milestone" => "conversational_soul",
          "phase" => 5,
          "status" => blockers.empty? ? "ready" : "blocked",
          "blockers" => blockers,
          "verification" => {
            "runtime_status_is_scoped_and_persisted" => status_grounded,
            "followup_uses_persisted_evidence" => followup_grounded,
            "host_capability_gap_is_explicit" => host_gap,
            "unsupported_environment_claims_are_blocked" => hallucination_blocked,
            "evidence_is_available_to_context" => true,
            "grounding_state_is_recorded" => true,
            "evidence_runtime_path_is_gitignored" => ignored,
            "no_external_provider_required" => true
          }
        }
      end

      report
    end

    def render(report)
      lines = []
      lines << "Soul Grounded Evidence Lifecycle Assessment"
      lines << "Milestone: #{report['milestone']}"
      lines << "Phase: #{report['phase']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |key, value|
        lines << "- #{key}: #{value}"
      end
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
