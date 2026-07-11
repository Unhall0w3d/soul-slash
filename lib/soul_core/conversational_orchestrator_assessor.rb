# frozen_string_literal: true

require "tmpdir"
require_relative "chat_store"
require_relative "conversation_orchestration_contract"
require_relative "conversation_orchestrator"
require_relative "conversation_provider_contract"
require_relative "conversation_runtime"
require_relative "conversation_state_store"

module SoulCore
  class ConversationalOrchestratorAssessor
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
          "Soul runtime status: healthy."
        when "inspect downloads"
          "Downloads inspection: 4 files, 2 older candidates."
        when "clean up downloads"
          "Cleanup preview: 2 candidates, mutation none."
        when "execution history summary"
          "Execution history: 3 successful read-only actions."
        when "what skills do you have?"
          "Available skills: system.status, downloads.inspect, downloads.cleanup_plan."
        else
          "I am Soul: deterministic route."
        end
      end
    end

    class RecordingProviderClient
      attr_reader :requests

      def initialize(fail: false)
        @fail = fail
        @requests = []
      end

      def chat(provider:, request:, timeout_seconds:)
        @requests << {
          "provider" => provider,
          "request" => request,
          "timeout_seconds" => timeout_seconds
        }

        if @fail
          return Contract::ResponseEnvelope.new(
            request_id: request.request_id,
            provider_id: provider.id,
            model: provider.model,
            content: "",
            error: {
              "type" => "assessment_failure",
              "message" => "simulated synthesis failure"
            }
          )
        end

        evidence_context = request.messages.find do |message|
          message["role"] == "system" &&
            message["content"].to_s.include?("Deterministic evidence")
        end

        content =
          if evidence_context
            "The Downloads inspection found 4 files and 2 older candidates."
          else
            "Direct conversational response."
          end

        Contract::ResponseEnvelope.new(
          request_id: request.request_id,
          provider_id: provider.id,
          model: provider.model,
          content: content,
          finish_reason: "stop",
          latency_ms: 4.0
        )
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      report = nil

      Dir.mktmpdir("soul-phase4-") do |temp_root|
        store = ChatStore.new(root: temp_root)
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
        provider_client = RecordingProviderClient.new
        state_store = ConversationStateStore.new(root: temp_root)
        orchestrator = ConversationOrchestrator.new

        runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: {
            "SOUL_CONVERSATION_PROVIDER" => provider.id,
            "SOUL_CONVERSATION_MODE" => "auto"
          },
          registry: registry,
          provider_client: provider_client,
          deterministic_responder: responder,
          state_store: state_store,
          orchestrator: orchestrator
        )

        chat = store.create_chat(initial_title: "Phase 4 assessment")
        chat_id = chat.fetch("id")

        synthesis_message = "Inspect Downloads and tell me what it means."
        store.add_message(chat_id, role: "user", content: synthesis_message)
        synthesis_result = runtime.respond(
          chat_id: chat_id,
          message: synthesis_message
        )

        synthesis_request = provider_client.requests.last.fetch("request")
        synthesis_works =
          synthesis_result.mode == "skill_then_model" &&
          responder.messages.include?("inspect downloads") &&
          synthesis_request.messages.any? do |message|
            message["content"].to_s.include?("Downloads inspection: 4 files")
          end

        responder_count_before_unrelated = responder.messages.length
        unrelated_message = "What Ruby optimizations would improve Soul's codebase?"
        store.add_message(chat_id, role: "user", content: unrelated_message)
        unrelated_result = runtime.respond(chat_id: chat_id, message: unrelated_message)
        unrelated_avoided =
          unrelated_result.mode == "model" &&
          responder.messages.length == responder_count_before_unrelated

        provider_count_before_control = provider_client.requests.length
        control_message = "approve downloads cleanup preview"
        store.add_message(chat_id, role: "user", content: control_message)
        control_result = runtime.respond(chat_id: chat_id, message: control_message)
        control_preserved =
          control_result.mode == "deterministic" &&
          provider_client.requests.length == provider_count_before_control

        chain_message = "Inspect Downloads and give me a cleanup plan."
        store.add_message(chat_id, role: "user", content: chain_message)
        chain_result = runtime.respond(chat_id: chat_id, message: chain_message)
        chain_ids = chain_result.metadata.dig("orchestration", "tool_ids")
        bounded_chain =
          chain_result.mode == "skill_then_model" &&
          chain_ids == ["downloads.inspect", "downloads.cleanup_plan"] &&
          chain_ids.length <= ConversationOrchestrator::MAX_TOOL_STEPS

        provider_count_before_status = provider_client.requests.length
        status_message = "Can you check the system status and tell me what it means?"
        store.add_message(chat_id, role: "user", content: status_message)
        status_result = runtime.respond(chat_id: chat_id, message: status_message)
        runtime_status_grounded =
          status_result.mode == "skill_only" &&
          provider_client.requests.length == provider_count_before_status &&
          status_result.content.include?("Soul application and registered-runtime status only") &&
          status_result.content.include?("Not collected by this check")

        flagged_plan = orchestrator.plan(
          message: "Remember our earlier discussion and prepare a report.",
          provider_available: true,
          recent_evidence: []
        )
        flags_recorded =
          flagged_plan.flags["memory_requested"] == true &&
          flagged_plan.flags["artifact_requested"] == true

        failing_client = RecordingProviderClient.new(fail: true)
        failing_runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: {
            "SOUL_CONVERSATION_PROVIDER" => provider.id
          },
          registry: registry,
          provider_client: failing_client,
          deterministic_responder: responder,
          state_store: state_store,
          orchestrator: orchestrator
        )
        failure_message = "Inspect Downloads and explain the result."
        store.add_message(chat_id, role: "user", content: failure_message)
        failure_result = failing_runtime.respond(
          chat_id: chat_id,
          message: failure_message
        )
        safe_failure =
          failure_result.mode == "skill_fallback" &&
          failure_result.content.include?("Downloads inspection") &&
          failure_result.content.include?("conversational synthesis is unavailable")

        state = state_store.state(chat_id)
        state_recorded =
          state["last_orchestration_kind"] == "skill_then_model" &&
          state["last_tool_ids"] == ["downloads.inspect"] &&
          state["last_response_mode"] == "skill_fallback"

        blockers = []
        blockers << "Informational skill result was not synthesized" unless synthesis_works
        blockers << "Unrelated Ruby discussion invoked a tool" unless unrelated_avoided
        blockers << "Approval control did not remain deterministic" unless control_preserved
        blockers << "Bounded two-skill chain failed" unless bounded_chain
        blockers << "Runtime status was not returned as scoped evidence" unless runtime_status_grounded
        blockers << "Memory and artifact intent flags were not recorded" unless flags_recorded
        blockers << "Provider synthesis failure lost the deterministic result" unless safe_failure
        blockers << "Orchestration state was not persisted" unless state_recorded

        report = {
          "ok" => blockers.empty?,
          "assessment" => "conversational_orchestrator",
          "milestone" => "conversational_soul",
          "phase" => 4,
          "status" => blockers.empty? ? "ready" : "blocked",
          "results" => {
            "synthesis" => synthesis_result.to_h,
            "unrelated" => unrelated_result.to_h,
            "control" => control_result.to_h,
            "chain" => chain_result.to_h,
            "runtime_status" => status_result.to_h,
            "failure" => failure_result.to_h
          },
          "flagged_plan" => flagged_plan.to_h,
          "state" => state,
          "blockers" => blockers,
          "verification" => {
            "single_skill_synthesis_works" => synthesis_works,
            "unrelated_skill_avoidance_works" => unrelated_avoided,
            "approval_controls_remain_deterministic" => control_preserved,
            "bounded_skill_chain_works" => bounded_chain,
            "runtime_status_is_scoped_evidence" => runtime_status_grounded,
            "memory_and_artifact_flags_work" => flags_recorded,
            "skill_result_survives_provider_failure" => safe_failure,
            "orchestration_state_is_recorded" => state_recorded,
            "max_tool_steps_is_two" => ConversationOrchestrator::MAX_TOOL_STEPS == 2,
            "no_external_provider_required" => true
          }
        }
      end

      report
    end

    def render(report)
      lines = []
      lines << "Soul Conversational Orchestrator Assessment"
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
