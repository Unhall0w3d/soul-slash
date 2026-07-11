# frozen_string_literal: true

require "tmpdir"
require_relative "chat_store"
require_relative "conversation_context_builder"
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
      attr_reader :messages

      def initialize
        @messages = []
      end

      def respond(message)
        @messages << message.to_s

        case message.to_s
        when "status"
          "Soul runtime status: core routes loaded and available."
        when "inspect downloads"
          "Downloads inspection: 4 files and 2 older candidates."
        when "clean up downloads"
          "Cleanup preview: 2 candidates; mutation none."
        else
          "Deterministic response."
        end
      end
    end

    class HallucinatingProviderClient
      attr_reader :requests

      def initialize
        @requests = []
      end

      def chat(provider:, request:, timeout_seconds:)
        @requests << request

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
        registry = FakeRegistry.new(provider)
        responder = RecordingResponder.new
        provider_client = HallucinatingProviderClient.new

        runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: {
            "SOUL_CONVERSATION_PROVIDER" => provider.id
          },
          registry: registry,
          provider_client: provider_client,
          deterministic_responder: responder,
          evidence_store: evidence_store,
          state_store: state_store
        )

        chat = store.create_chat(initial_title: "Phase 5 assessment")
        chat_id = chat.fetch("id")

        status_message = "Can you check the system status and tell me what it means?"
        store.add_message(chat_id, role: "user", content: status_message)
        provider_before_status = provider_client.requests.length
        status_result = runtime.respond(chat_id: chat_id, message: status_message)
        status_evidence = evidence_store.latest(chat_id)

        status_grounded =
          status_result.mode == "skill_only" &&
          provider_client.requests.length == provider_before_status &&
          status_result.content.include?("Soul application and registered-runtime status only") &&
          status_result.content.include?("Not collected by this check") &&
          status_evidence["tool_id"] == "system.status" &&
          status_evidence["evidence_profile"] == "soul_runtime_status"

        followup_message = "Further details about what you checked, please."
        store.add_message(chat_id, role: "user", content: followup_message)
        provider_before_followup = provider_client.requests.length
        followup_result = runtime.respond(
          chat_id: chat_id,
          message: followup_message
        )
        followup_grounded =
          followup_result.mode == "evidence_followup" &&
          provider_client.requests.length == provider_before_followup &&
          followup_result.content.include?(status_evidence["evidence_id"]) &&
          followup_result.content.include?("RAID state") &&
          followup_result.content.include?("Not collected by this check")

        host_message = "Can you perform an assessment of your environment?"
        store.add_message(chat_id, role: "user", content: host_message)
        provider_before_host = provider_client.requests.length
        responder_before_host = responder.messages.length
        host_result = runtime.respond(chat_id: chat_id, message: host_message)
        host_gap =
          host_result.mode == "capability_gap" &&
          provider_client.requests.length == provider_before_host &&
          responder.messages.length == responder_before_host &&
          host_result.content.include?("no registered host-environment assessment skill") &&
          host_result.content.include?("host.system_status")

        downloads_message = "Inspect Downloads and explain the result."
        store.add_message(chat_id, role: "user", content: downloads_message)
        downloads_result = runtime.respond(
          chat_id: chat_id,
          message: downloads_message
        )
        hallucination_blocked =
          downloads_result.mode == "grounding_fallback" &&
          downloads_result.content.include?("rejected the model-written explanation") &&
          downloads_result.content.include?("Downloads inspection: 4 files") &&
          downloads_result.metadata.dig("grounding", "valid") == false &&
          downloads_result.metadata.dig("grounding", "errors").any? do |error|
            error.include?("raid") || error.include?("68%")
          end

        context_builder = ConversationContextBuilder.new(
          store: store,
          evidence_store: evidence_store,
          max_messages: 10,
          max_characters: 12_000
        )
        context = context_builder.build(chat_id: chat_id)
        evidence_in_context =
          context["evidence_count"].positive? &&
          context["evidence_ids"].include?(status_evidence["evidence_id"]) &&
          context["messages"].first["content"].include?("Recent deterministic evidence")

        state = state_store.state(chat_id)
        state_recorded =
          state["last_response_mode"] == "grounding_fallback" &&
          state["last_grounding"]["valid"] == false &&
          !state["last_evidence_ids"].empty?

        ignored = system(
          "git",
          "check-ignore",
          "Soul/runtime/conversation_evidence/example.jsonl",
          chdir: @root,
          out: File::NULL,
          err: File::NULL
        )

        blockers = []
        blockers << "Soul runtime status was not scoped and persisted" unless status_grounded
        blockers << "Evidence follow-up was not resolved from persisted evidence" unless followup_grounded
        blockers << "Host environment request did not expose the capability gap" unless host_gap
        blockers << "Unsupported synthesized claims were not blocked" unless hallucination_blocked
        blockers << "Recent evidence was not included in conversation context" unless evidence_in_context
        blockers << "Grounding state was not persisted" unless state_recorded
        blockers << "Conversation evidence runtime path is not gitignored" unless ignored

        report = {
          "ok" => blockers.empty?,
          "assessment" => "grounded_evidence_lifecycle",
          "milestone" => "conversational_soul",
          "phase" => 5,
          "status" => blockers.empty? ? "ready" : "blocked",
          "results" => {
            "runtime_status" => status_result.to_h,
            "followup" => followup_result.to_h,
            "host_capability_gap" => host_result.to_h,
            "hallucination_guard" => downloads_result.to_h
          },
          "context" => context.reject { |key, _value| key == "messages" },
          "state" => state,
          "blockers" => blockers,
          "verification" => {
            "runtime_status_is_scoped_and_persisted" => status_grounded,
            "followup_uses_persisted_evidence" => followup_grounded,
            "host_capability_gap_is_explicit" => host_gap,
            "unsupported_environment_claims_are_blocked" => hallucination_blocked,
            "evidence_is_available_to_context" => evidence_in_context,
            "grounding_state_is_recorded" => state_recorded,
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
      if report.fetch("blockers").empty?
        lines << "- None"
      else
        report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      end
      lines.join("\n")
    end
  end
end
