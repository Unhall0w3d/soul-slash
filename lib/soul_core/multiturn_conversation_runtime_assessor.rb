# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "chat_responder"
require_relative "chat_store"
require_relative "conversation_context_builder"
require_relative "conversation_provider_contract"
require_relative "conversation_runtime"
require_relative "conversation_state_store"

module SoulCore
  class MultiturnConversationRuntimeAssessor
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

    class FakeDeterministicResponder
      def respond(message)
        return "I am Soul: deterministic identity route." if message.to_s.downcase.include?("who are you")

        "Deterministic response."
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
              "message" => "simulated offline provider"
            }
          )
        end

        prior_user_text = request.messages
          .select { |message| message["role"] == "user" }
          .map { |message| message["content"] }
          .join(" | ")

        Contract::ResponseEnvelope.new(
          request_id: request.request_id,
          provider_id: provider.id,
          model: provider.model,
          content: "Context received: #{prior_user_text}",
          finish_reason: "stop",
          usage: {
            "input_tokens" => 20,
            "output_tokens" => 8
          },
          latency_ms: 5.0
        )
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      report = nil

      Dir.mktmpdir("soul-phase3-") do |temp_root|
        store = ChatStore.new(root: temp_root)
        provider = Contract::ProviderDefinition.new(
          id: "local.assessment",
          label: "Assessment conversation provider",
          transport: "openai_compatible",
          endpoint: "http://127.0.0.1:1/v1",
          model: "assessment-model",
          privacy_class: "local_only",
          capabilities: %w[chat],
          configured: true
        )
        registry = FakeRegistry.new(provider)
        client = RecordingProviderClient.new
        state_store = ConversationStateStore.new(root: temp_root)

        runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: {
            "SOUL_CONVERSATION_PROVIDER" => provider.id,
            "SOUL_CONVERSATION_MODE" => "auto",
            "SOUL_CONVERSATION_MAX_MESSAGES" => "6",
            "SOUL_CONVERSATION_MAX_CHARACTERS" => "8000"
          },
          registry: registry,
          provider_client: client,
          deterministic_responder: FakeDeterministicResponder.new,
          state_store: state_store
        )

        chat = store.create_chat(initial_title: "Phase 3 assessment")
        chat_id = chat.fetch("id")

        store.add_message(
          chat_id,
          role: "user",
          content: "For this project, remember that I use zsh."
        )
        first = runtime.respond(
          chat_id: chat_id,
          message: "For this project, remember that I use zsh."
        )
        store.add_message(
          chat_id,
          role: "assistant",
          content: first.content,
          metadata: { "mode" => first.mode }
        )

        store.add_message(
          chat_id,
          role: "user",
          content: "Which shell did I mention?"
        )
        second = runtime.respond(
          chat_id: chat_id,
          message: "Which shell did I mention?"
        )
        store.add_message(
          chat_id,
          role: "assistant",
          content: second.content,
          metadata: { "mode" => second.mode }
        )

        second_request = client.requests.last.fetch("request")
        second_messages = second_request.messages
        continuity =
          second_messages.any? do |message|
            message["role"] == "user" &&
              message["content"].include?("I use zsh")
          end &&
          second_messages.any? do |message|
            message["role"] == "assistant" &&
              message["content"].include?("Context received")
          end &&
          second_messages.any? do |message|
            message["role"] == "user" &&
              message["content"].include?("Which shell")
          end

        requests_before_identity = client.requests.length
        store.add_message(chat_id, role: "user", content: "who are you?")
        identity_conversation = runtime.respond(
          chat_id: chat_id,
          message: "who are you?"
        )
        identity_used_model =
          client.requests.length == requests_before_identity + 1 &&
          identity_conversation.mode == "model"
        store.add_message(
          chat_id,
          role: "assistant",
          content: identity_conversation.content,
          metadata: { "mode" => identity_conversation.mode }
        )

        requests_before_inspection = client.requests.length
        store.add_message(chat_id, role: "user", content: "show identity")
        identity_inspection = runtime.respond(
          chat_id: chat_id,
          message: "show identity"
        )
        inspection_bypassed_model =
          client.requests.length == requests_before_inspection &&
          identity_inspection.mode == "deterministic"

        failing_client = RecordingProviderClient.new(fail: true)
        failing_runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: {
            "SOUL_CONVERSATION_PROVIDER" => provider.id,
            "SOUL_CONVERSATION_MODE" => "model"
          },
          registry: registry,
          provider_client: failing_client,
          deterministic_responder: FakeDeterministicResponder.new,
          state_store: state_store
        )
        store.add_message(
          chat_id,
          role: "user",
          content: "Continue the conversation despite a provider failure."
        )
        fallback = failing_runtime.respond(
          chat_id: chat_id,
          message: "Continue the conversation despite a provider failure."
        )

        context_builder = ConversationContextBuilder.new(
          store: store,
          max_messages: 2,
          max_characters: 4_000,
          digest_characters: 1_000
        )
        bounded_context = context_builder.build(chat_id: chat_id)
        context_bounded =
          bounded_context["included_message_count"] <= 2 &&
          bounded_context["truncated_message_count"].positive? &&
          !bounded_context["context_digest"].empty?

        state = state_store.state(chat_id)
        state_recorded =
          state["turn_count"].to_i >= 4 &&
          state["last_response_mode"] == "fallback" &&
          state["last_fallback_reason"].to_s.include?("assessment_failure") &&
          state["active_subject"].to_s.include?("Continue the conversation")

        ignored = system(
          "git",
          "check-ignore",
          "Soul/runtime/conversation_state/example.json",
          chdir: @root,
          out: File::NULL,
          err: File::NULL
        )

        blockers = []
        blockers << "First model-backed turn failed" unless first.mode == "model"
        blockers << "Second model-backed turn failed" unless second.mode == "model"
        blockers << "Prior turns were not supplied to the second request" unless continuity
        blockers << "Natural identity conversation did not use the configured model" unless identity_used_model
        blockers << "Identity policy inspection did not bypass the model" unless inspection_bypassed_model
        blockers << "Provider failure did not return a safe fallback" unless fallback.mode == "fallback"
        blockers << "Context window was not bounded" unless context_bounded
        blockers << "Conversation state was not recorded" unless state_recorded
        blockers << "Conversation state runtime path is not gitignored" unless ignored

        report = {
          "ok" => blockers.empty?,
          "assessment" => "multiturn_conversation_runtime",
          "milestone" => "conversational_soul",
          "phase" => 3,
          "status" => blockers.empty? ? "ready" : "blocked",
          "chat_id" => chat_id,
          "provider_request_count" => client.requests.length,
          "first_result" => first.to_h,
          "second_result" => second.to_h,
          "identity_conversation_result" => identity_conversation.to_h,
          "identity_inspection_result" => identity_inspection.to_h,
          "fallback_result" => fallback.to_h,
          "bounded_context" => bounded_context.reject { |key, _value| key == "messages" },
          "state" => state,
          "blockers" => blockers,
          "verification" => {
            "model_backed_turn_works" => first.mode == "model",
            "multiturn_context_continues" => continuity,
            "natural_identity_conversation_uses_model" => identity_used_model,
            "deterministic_identity_inspection_preserved" => inspection_bypassed_model,
            "provider_failure_falls_back_safely" => fallback.mode == "fallback",
            "context_window_is_bounded" => context_bounded,
            "runtime_state_is_recorded" => state_recorded,
            "runtime_state_is_gitignored" => ignored,
            "no_external_provider_required" => true
          }
        }
      end

      report
    end

    def render(report)
      lines = []
      lines << "Soul Multi-turn Conversation Runtime Assessment"
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
