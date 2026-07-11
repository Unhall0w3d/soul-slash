# frozen_string_literal: true

require_relative "chat_responder"
require_relative "conversation_context_builder"
require_relative "conversation_provider_client"
require_relative "conversation_provider_contract"
require_relative "conversation_provider_registry"
require_relative "conversation_state_store"
require_relative "intent_router"

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

    DETERMINISTIC_INTENTS = %w[
      identity
      skill_catalog
      repo_status
      downloads_inspect
      downloads_cleanup_plan
    ].freeze

    DETERMINISTIC_PATTERNS = [
      /\b(approve downloads cleanup preview|approve cleanup preview)\b/i,
      /\b(pending approvals|show approvals|list approvals)\b/i,
      /\brevoke approval\b/i,
      /\b(dry run downloads move|dry run move approved downloads|preview approved downloads move)\b/i,
      /\bmove approved downloads to trash\b/i,
      /\b(adapter registry|execution adapters|list adapters|enabled adapters|blocked adapters)\b/i,
      /\b(execution history|history summary|clear history|prune history|export history)\b/i
    ].freeze

    def initialize(
      root: Dir.pwd,
      store:,
      env: ENV,
      registry: nil,
      provider_client: nil,
      deterministic_responder: nil,
      context_builder: nil,
      state_store: nil
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
      @router = IntentRouter.new
    end

    def respond(chat_id:, message:)
      text = message.to_s.strip
      raise ArgumentError, "Conversation message must not be empty" if text.empty?

      if deterministic_route?(text)
        content = @deterministic_responder.respond(text)
        context = safe_context(chat_id)
        record_state(
          chat_id: chat_id,
          user_message: text,
          assistant_message: content,
          mode: "deterministic",
          context: context
        )
        return Result.new(
          content: content,
          mode: "deterministic",
          metadata: {
            "context" => context_stats(context),
            "reason" => "registered deterministic route"
          }
        )
      end

      provider = selected_provider
      unless provider
        return deterministic_fallback(
          chat_id: chat_id,
          message: text,
          reason: "no configured local conversation provider"
        )
      end

      context = @context_builder.build(chat_id: chat_id)
      request = Contract::RequestEnvelope.new(
        conversation_id: chat_id,
        messages: context.fetch("messages"),
        model: provider.model,
        temperature: float_env("SOUL_CONVERSATION_TEMPERATURE", 0.65),
        max_output_tokens: integer_env("SOUL_CONVERSATION_MAX_OUTPUT_TOKENS", 1_024),
        privacy_requirement: privacy_requirement(provider),
        metadata: {
          "runtime" => "conversational_soul_phase3",
          "context" => context_stats(context)
        }
      )

      response = @provider_client.chat(
        provider: provider,
        request: request,
        timeout_seconds: float_env("SOUL_CONVERSATION_TIMEOUT_SECONDS", 120.0)
      )

      if response.success? && !response.content.to_s.strip.empty?
        content = response.content.to_s.strip
        record_state(
          chat_id: chat_id,
          user_message: text,
          assistant_message: content,
          mode: "model",
          provider_id: provider.id,
          context: context
        )

        return Result.new(
          content: content,
          mode: "model",
          provider_id: provider.id,
          metadata: {
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
        context: context
      )
    end

    private

    def deterministic_route?(text)
      return true if conversation_mode == "deterministic"
      return true if DETERMINISTIC_PATTERNS.any? { |pattern| text.match?(pattern) }

      intent = @router.route(text)
      DETERMINISTIC_INTENTS.include?(intent.id.to_s)
    rescue StandardError
      false
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

    def deterministic_fallback(chat_id:, message:, reason:, provider_id: nil, context: nil)
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
        context: context
      )

      Result.new(
        content: content,
        mode: "fallback",
        provider_id: provider_id,
        fallback_reason: reason,
        metadata: {
          "context" => context_stats(context)
        }
      )
    end

    def record_state(**arguments)
      @state_store.record_turn(**arguments)
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

    def conversation_mode
      mode = @env.fetch("SOUL_CONVERSATION_MODE", "auto").to_s
      %w[auto model deterministic].include?(mode) ? mode : "auto"
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
