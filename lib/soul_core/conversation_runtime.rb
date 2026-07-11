# frozen_string_literal: true

require "json"
require_relative "chat_responder"
require_relative "conversation_context_builder"
require_relative "conversation_orchestrator"
require_relative "conversation_provider_client"
require_relative "conversation_provider_contract"
require_relative "conversation_provider_registry"
require_relative "conversation_state_store"

module SoulCore
  class ConversationRuntime
    Contract = ConversationProviderContract

    Result = Struct.new(
      :content,
      :mode,
      :provider_id,
      :fallback_reason,
      :metadata,
      keyword_init: true
    ) do
      def to_h
        {
          "content" => content,
          "mode" => mode,
          "provider_id" => provider_id,
          "fallback_reason" => fallback_reason,
          "metadata" => metadata || {}
        }.reject { |_key, value| value.nil? }
      end
    end

    def initialize(
      root: Dir.pwd,
      store:,
      env: ENV,
      registry: nil,
      provider_client: nil,
      deterministic_responder: nil,
      context_builder: nil,
      state_store: nil,
      orchestrator: nil
    )
      @root = File.expand_path(root)
      @store = store
      @env = env
      @registry = registry || ConversationProviderRegistry.new(env: env)
      @provider_client = provider_client || ConversationProviderClient.new(env: env)
      @deterministic_responder = deterministic_responder || ChatResponder.new(root: @root)
      @context_builder = context_builder || ConversationContextBuilder.new(
        store: store,
        max_messages: env.fetch("SOUL_CONVERSATION_MAX_MESSAGES", ConversationContextBuilder::DEFAULT_MAX_MESSAGES),
        max_characters: env.fetch("SOUL_CONVERSATION_MAX_CHARACTERS", ConversationContextBuilder::DEFAULT_MAX_CHARACTERS)
      )
      @state_store = state_store || ConversationStateStore.new(root: @root)
      @orchestrator = orchestrator || ConversationOrchestrator.new(
        max_tool_steps: env.fetch("SOUL_CONVERSATION_MAX_TOOL_STEPS", ConversationOrchestrator::MAX_TOOL_STEPS)
      )
    end

    def respond(chat_id:, message:)
      text = message.to_s.strip
      raise ArgumentError, "Conversation message must not be empty" if text.empty?

      provider = selected_provider
      decision = @orchestrator.plan(
        message: text,
        provider_available: !provider.nil?
      )

      case decision.kind
      when "deterministic_passthrough"
        deterministic_passthrough(chat_id, text, decision)
      when "skill_only"
        informational_skill_only(chat_id, text, decision)
      when "skill_then_model"
        informational_skill_then_model(chat_id, text, decision, provider)
      when "direct_model"
        direct_model(chat_id, text, decision, provider)
      else
        deterministic_fallback(
          chat_id: chat_id,
          message: text,
          reason: decision.reason,
          decision: decision
        )
      end
    end

    private

    def deterministic_passthrough(chat_id, text, decision)
      content = @deterministic_responder.respond(text)
      context = safe_context(chat_id)
      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "deterministic",
        context: context,
        decision: decision
      )

      Result.new(
        content: content,
        mode: "deterministic",
        metadata: {
          "orchestration" => decision.to_h,
          "context" => context_stats(context)
        }
      )
    end

    def informational_skill_only(chat_id, text, decision)
      tool_results = execute_tools(decision.tools)
      content = render_tool_results(tool_results)
      context = safe_context(chat_id)

      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "skill_only",
        context: context,
        decision: decision,
        tool_ids: decision.tool_ids
      )

      Result.new(
        content: content,
        mode: "skill_only",
        metadata: {
          "orchestration" => decision.to_h,
          "tool_results" => tool_result_metadata(tool_results),
          "context" => context_stats(context)
        }
      )
    end

    def informational_skill_then_model(chat_id, text, decision, provider)
      tool_results = execute_tools(decision.tools)
      context = safe_context(chat_id)
      request = build_request(
        chat_id: chat_id,
        provider: provider,
        context: context,
        orchestration: decision,
        tool_results: tool_results
      )
      response = provider_response(provider, request)

      if response.success? && !response.content.to_s.strip.empty?
        content = response.content.to_s.strip
        record_state(
          chat_id: chat_id,
          user_message: text,
          assistant_message: content,
          mode: "skill_then_model",
          provider_id: provider.id,
          context: context,
          decision: decision,
          tool_ids: decision.tool_ids
        )

        return Result.new(
          content: content,
          mode: "skill_then_model",
          provider_id: provider.id,
          metadata: {
            "orchestration" => decision.to_h,
            "tool_results" => tool_result_metadata(tool_results),
            "model" => response.model,
            "finish_reason" => response.finish_reason,
            "usage" => response.usage,
            "latency_ms" => response.latency_ms,
            "context" => context_stats(context)
          }
        )
      end

      reason = provider_error_reason(response)
      content = [
        render_tool_results(tool_results),
        "",
        "I gathered the deterministic result, but conversational synthesis is unavailable.",
        "Reason: #{reason}."
      ].join("\n")

      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "skill_fallback",
        provider_id: provider.id,
        fallback_reason: reason,
        context: context,
        decision: decision,
        tool_ids: decision.tool_ids
      )

      Result.new(
        content: content,
        mode: "skill_fallback",
        provider_id: provider.id,
        fallback_reason: reason,
        metadata: {
          "orchestration" => decision.to_h,
          "tool_results" => tool_result_metadata(tool_results),
          "context" => context_stats(context)
        }
      )
    end

    def direct_model(chat_id, text, decision, provider)
      return deterministic_fallback(
        chat_id: chat_id,
        message: text,
        reason: "no configured local conversation provider",
        decision: decision
      ) unless provider

      context = safe_context(chat_id)
      request = build_request(
        chat_id: chat_id,
        provider: provider,
        context: context,
        orchestration: decision
      )
      response = provider_response(provider, request)

      if response.success? && !response.content.to_s.strip.empty?
        content = response.content.to_s.strip
        record_state(
          chat_id: chat_id,
          user_message: text,
          assistant_message: content,
          mode: "model",
          provider_id: provider.id,
          context: context,
          decision: decision
        )

        return Result.new(
          content: content,
          mode: "model",
          provider_id: provider.id,
          metadata: {
            "orchestration" => decision.to_h,
            "model" => response.model,
            "finish_reason" => response.finish_reason,
            "usage" => response.usage,
            "latency_ms" => response.latency_ms,
            "context" => context_stats(context)
          }
        )
      end

      deterministic_fallback(
        chat_id: chat_id,
        message: text,
        reason: provider_error_reason(response),
        provider_id: provider.id,
        context: context,
        decision: decision
      )
    end

    def build_request(chat_id:, provider:, context:, orchestration:, tool_results: [])
      messages = context.fetch("messages").map(&:dup)

      unless tool_results.empty?
        messages << {
          "role" => "system",
          "content" => [
            "Deterministic skill results are provided below.",
            "Use them as authoritative for this turn.",
            "Explain the useful result naturally and return to the user's conversation.",
            "Do not claim any other tool or action ran.",
            JSON.pretty_generate(tool_results)
          ].join("\n")
        }
      end

      Contract::RequestEnvelope.new(
        conversation_id: chat_id,
        messages: messages,
        model: provider.model,
        temperature: float_env("SOUL_CONVERSATION_TEMPERATURE", 0.65),
        max_output_tokens: integer_env("SOUL_CONVERSATION_MAX_OUTPUT_TOKENS", 1_024),
        privacy_requirement: privacy_requirement(provider),
        metadata: {
          "runtime" => "conversational_soul_phase4",
          "orchestration" => orchestration.to_h,
          "context" => context_stats(context)
        }
      )
    end

    def execute_tools(tools)
      tools.map do |tool|
        begin
          output = @deterministic_responder.respond(tool.canonical_message)
          {
            "tool_id" => tool.id,
            "risk_class" => tool.risk_class,
            "status" => "ok",
            "output" => output.to_s
          }
        rescue StandardError => error
          {
            "tool_id" => tool.id,
            "risk_class" => tool.risk_class,
            "status" => "failed",
            "error_class" => error.class.name,
            "error_message" => error.message
          }
        end
      end
    end

    def render_tool_results(results)
      results.map do |result|
        if result["status"] == "ok"
          result["output"].to_s
        else
          "Tool #{result['tool_id']} failed: #{result['error_message']}"
        end
      end.join("\n\n")
    end

    def tool_result_metadata(results)
      results.map do |result|
        {
          "tool_id" => result["tool_id"],
          "risk_class" => result["risk_class"],
          "status" => result["status"]
        }
      end
    end

    def provider_response(provider, request)
      @provider_client.chat(
        provider: provider,
        request: request,
        timeout_seconds: float_env("SOUL_CONVERSATION_TIMEOUT_SECONDS", 120.0)
      )
    end

    def selected_provider
      preferred_id = @env["SOUL_CONVERSATION_PROVIDER"].to_s.strip
      provider = preferred_id.empty? ? nil : @registry.find(preferred_id)

      if provider
        return nil unless provider.configured?
        return nil if provider.privacy_class == "cloud" && !cloud_allowed?
        return provider
      end

      candidates = @registry.configured
      candidates = candidates.reject { |item| item.privacy_class == "cloud" } unless cloud_allowed?
      candidates.find { |item| item.privacy_class == "local_only" } ||
        candidates.find { |item| item.privacy_class == "local_network" } ||
        candidates.first
    end

    def deterministic_fallback(
      chat_id:,
      message:,
      reason:,
      decision:,
      provider_id: nil,
      context: nil
    )
      context ||= safe_context(chat_id)
      content = [
        "I can keep this conversation session, but the model-backed conversation path is unavailable.",
        "Reason: #{reason}.",
        "Deterministic skills and approval-gated actions are still available."
      ].join("\n")

      record_state(
        chat_id: chat_id,
        user_message: message,
        assistant_message: content,
        mode: "fallback",
        provider_id: provider_id,
        fallback_reason: reason,
        context: context,
        decision: decision
      )

      Result.new(
        content: content,
        mode: "fallback",
        provider_id: provider_id,
        fallback_reason: reason,
        metadata: {
          "orchestration" => decision.to_h,
          "context" => context_stats(context)
        }
      )
    end

    def record_state(
      chat_id:,
      user_message:,
      assistant_message:,
      mode:,
      context:,
      decision:,
      provider_id: nil,
      fallback_reason: nil,
      tool_ids: []
    )
      @state_store.record_turn(
        chat_id: chat_id,
        user_message: user_message,
        assistant_message: assistant_message,
        mode: mode,
        provider_id: provider_id,
        fallback_reason: fallback_reason,
        context: context,
        orchestration: decision.to_h,
        tool_ids: tool_ids
      )
    end

    def safe_context(chat_id)
      @context_builder.build(chat_id: chat_id)
    rescue StandardError
      {
        "messages" => [],
        "context_digest" => "",
        "total_message_count" => 0,
        "included_message_count" => 0,
        "truncated_message_count" => 0,
        "character_count" => 0
      }
    end

    def context_stats(context)
      {
        "total_message_count" => context.fetch("total_message_count", 0),
        "included_message_count" => context.fetch("included_message_count", 0),
        "truncated_message_count" => context.fetch("truncated_message_count", 0),
        "character_count" => context.fetch("character_count", 0)
      }
    end

    def provider_error_reason(response)
      error = response.error || {}
      type = error["type"].to_s
      message = error["message"].to_s
      return "provider returned an empty response" if type.empty? && message.empty?
      return type unless type.empty? && !message.empty?
      return message if type.empty?

      "#{type}: #{message}"
    end

    def privacy_requirement(provider)
      provider.privacy_class == "cloud" ? "cloud" : provider.privacy_class
    end

    def cloud_allowed?
      @env["SOUL_ALLOW_CLOUD_CONVERSATION"] == "1"
    end

    def integer_env(name, fallback)
      value = @env[name].to_i
      value.positive? ? value : fallback
    end

    def float_env(name, fallback)
      value = Float(@env.fetch(name, fallback))
      value.positive? ? value : fallback
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
