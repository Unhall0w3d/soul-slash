# frozen_string_literal: true

require "json"
require_relative "chat_responder"
require_relative "conversation_context_builder"
require_relative "conversation_capability_registry"
require_relative "conversation_evidence_contract"
require_relative "conversation_evidence_followup_router"
require_relative "conversation_evidence_store"
require_relative "conversation_grounding_policy"
require_relative "conversation_orchestrator"
require_relative "conversation_provider_client"
require_relative "conversation_provider_contract"
require_relative "conversation_provider_registry"
require_relative "conversation_state_store"
require_relative "host_system_status_collector"

module SoulCore
  class ConversationRuntime
    Contract = ConversationProviderContract
    EvidenceContract = ConversationEvidenceContract

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
      evidence_store: nil,
      capability_registry: nil,
      evidence_followup_router: nil,
      grounding_policy: nil,
      orchestrator: nil,
      host_status_collector: nil
    )
      @root = File.expand_path(root)
      @store = store
      @env = env
      @registry = registry || ConversationProviderRegistry.new(env: env)
      @provider_client = provider_client || ConversationProviderClient.new(env: env)
      @deterministic_responder = deterministic_responder || ChatResponder.new(root: @root)
      @evidence_store = evidence_store || ConversationEvidenceStore.new(root: @root)
      @grounding_policy = grounding_policy || ConversationGroundingPolicy.new
      @evidence_followup_router = evidence_followup_router || ConversationEvidenceFollowupRouter.new
      @capability_registry = capability_registry || ConversationCapabilityRegistry.new
      @host_status_collector = host_status_collector || HostSystemStatusCollector.new
      @context_builder = context_builder || ConversationContextBuilder.new(
        store: store,
        evidence_store: @evidence_store,
        max_messages: env.fetch("SOUL_CONVERSATION_MAX_MESSAGES", ConversationContextBuilder::DEFAULT_MAX_MESSAGES),
        max_characters: env.fetch("SOUL_CONVERSATION_MAX_CHARACTERS", ConversationContextBuilder::DEFAULT_MAX_CHARACTERS)
      )
      @state_store = state_store || ConversationStateStore.new(root: @root)
      @orchestrator = orchestrator || ConversationOrchestrator.new(
        grounding_policy: @grounding_policy,
        followup_router: @evidence_followup_router,
        capability_registry: @capability_registry,
        max_tool_steps: env.fetch("SOUL_CONVERSATION_MAX_TOOL_STEPS", ConversationOrchestrator::MAX_TOOL_STEPS)
      )
    end

    def respond(chat_id:, message:)
      text = message.to_s.strip
      raise ArgumentError, "Conversation message must not be empty" if text.empty?

      provider = selected_provider
      recent_evidence = @evidence_store.recent(chat_id, limit: 5)
      decision = @orchestrator.plan(
        message: text,
        provider_available: !provider.nil?,
        recent_evidence: recent_evidence
      )

      case decision.kind
      when "deterministic_passthrough"
        deterministic_passthrough(chat_id, text, decision)
      when "skill_only"
        informational_skill_only(chat_id, text, decision)
      when "skill_then_model"
        informational_skill_then_model(chat_id, text, decision, provider)
      when "evidence_followup"
        evidence_followup(chat_id, text, decision, recent_evidence)
      when "capability_catalog"
        capability_catalog(chat_id, text, decision)
      when "capability_info"
        capability_info(chat_id, text, decision)
      when "capability_gap"
        capability_gap(chat_id, text, decision)
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
      content = deterministic_response(text, chat_id)
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
      evidence = execute_tools(decision.tools, chat_id)
      content = @grounding_policy.render_evidence(
        evidence,
        heading: "What Soul actually checked"
      )
      context = safe_context(chat_id)

      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "skill_only",
        context: context,
        decision: decision,
        tool_ids: decision.tool_ids,
        evidence_ids: evidence_ids(evidence),
        grounding: { "valid" => true, "mode" => "deterministic_evidence" }
      )

      Result.new(
        content: content,
        mode: "skill_only",
        metadata: {
          "orchestration" => decision.to_h,
          "evidence" => evidence_metadata(evidence),
          "grounding" => { "valid" => true, "mode" => "deterministic_evidence" },
          "context" => context_stats(context)
        }
      )
    end

    def informational_skill_then_model(chat_id, text, decision, provider)
      evidence = execute_tools(decision.tools, chat_id)
      context = safe_context(chat_id)
      request = build_request(
        chat_id: chat_id,
        provider: provider,
        context: context,
        orchestration: decision,
        evidence: evidence
      )
      response = provider_response(provider, request)

      if response.success? && !response.content.to_s.strip.empty?
        grounding = @grounding_policy.validate(
          response: response.content,
          evidence_records: evidence
        )

        if grounding["valid"]
          content = response.content.to_s.strip
          record_state(
            chat_id: chat_id,
            user_message: text,
            assistant_message: content,
            mode: "skill_then_model",
            provider_id: provider.id,
            context: context,
            decision: decision,
            tool_ids: decision.tool_ids,
            evidence_ids: evidence_ids(evidence),
            grounding: grounding
          )

          return Result.new(
            content: content,
            mode: "skill_then_model",
            provider_id: provider.id,
            metadata: {
              "orchestration" => decision.to_h,
              "evidence" => evidence_metadata(evidence),
              "grounding" => grounding,
              "model" => response.model,
              "finish_reason" => response.finish_reason,
              "usage" => response.usage,
              "latency_ms" => response.latency_ms,
              "context" => context_stats(context)
            }
          )
        end

        content = [
          @grounding_policy.render_evidence(
            evidence,
            heading: "Grounded deterministic result"
          ),
          "",
          "I rejected the model-written explanation because it introduced claims not supported by the collected evidence."
        ].join("\n")

        record_state(
          chat_id: chat_id,
          user_message: text,
          assistant_message: content,
          mode: "grounding_fallback",
          provider_id: provider.id,
          fallback_reason: "unsupported synthesized claims",
          context: context,
          decision: decision,
          tool_ids: decision.tool_ids,
          evidence_ids: evidence_ids(evidence),
          grounding: grounding
        )

        return Result.new(
          content: content,
          mode: "grounding_fallback",
          provider_id: provider.id,
          fallback_reason: "unsupported synthesized claims",
          metadata: {
            "orchestration" => decision.to_h,
            "evidence" => evidence_metadata(evidence),
            "grounding" => grounding,
            "context" => context_stats(context)
          }
        )
      end

      reason = provider_error_reason(response)
      content = [
        @grounding_policy.render_evidence(
          evidence,
          heading: "Grounded deterministic result"
        ),
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
        tool_ids: decision.tool_ids,
        evidence_ids: evidence_ids(evidence),
        grounding: { "valid" => true, "mode" => "deterministic_fallback" }
      )

      Result.new(
        content: content,
        mode: "skill_fallback",
        provider_id: provider.id,
        fallback_reason: reason,
        metadata: {
          "orchestration" => decision.to_h,
          "evidence" => evidence_metadata(evidence),
          "grounding" => { "valid" => true, "mode" => "deterministic_fallback" },
          "context" => context_stats(context)
        }
      )
    end

    def evidence_followup(chat_id, text, decision, recent_evidence)
      selection = @evidence_followup_router.route(
        message: text,
        evidence_records: recent_evidence
      )
      content = @evidence_followup_router.render(
        selection: selection,
        heading: "Details from the most recent deterministic check"
      )
      selected_evidence = selection.record ? [selection.record] : recent_evidence
      context = safe_context(chat_id)

      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "evidence_followup",
        context: context,
        decision: decision,
        tool_ids: selected_evidence.map { |record| record["tool_id"] },
        evidence_ids: evidence_ids(selected_evidence),
        grounding: { "valid" => true, "mode" => "persisted_evidence_router" }
      )

      Result.new(
        content: content,
        mode: "evidence_followup",
        metadata: {
          "orchestration" => decision.to_h,
          "evidence" => evidence_metadata(selected_evidence),
          "followup" => selection.to_h,
          "grounding" => { "valid" => true, "mode" => "persisted_evidence_router" },
          "context" => context_stats(context)
        }
      )
    end

    def capability_catalog(chat_id, text, decision)
      capability_response(chat_id, text, decision, mode: "capability_catalog")
    end

    def capability_info(chat_id, text, decision)
      capability_response(chat_id, text, decision, mode: "capability_info")
    end

    def capability_gap(chat_id, text, decision)
      capability_response(chat_id, text, decision, mode: "capability_gap")
    end

    def capability_response(chat_id, text, decision, mode:)
      requested = decision.flags["requested_capability"].to_s
      resolution = if mode == "capability_catalog"
                     @capability_registry.resolve(text)
                   elsif requested.empty?
                     @capability_registry.resolve(text)
                   else
                     @capability_registry.resolve_id(requested, kind: mode)
                   end
      content = if mode == "capability_catalog"
                  @capability_registry.render_catalog
                else
                  @capability_registry.render(resolution)
                end
      context = safe_context(chat_id)

      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: mode,
        context: context,
        decision: decision,
        grounding: { "valid" => true, "mode" => "declared_capability_registry" }
      )

      Result.new(
        content: content,
        mode: mode,
        metadata: {
          "orchestration" => decision.to_h,
          "capability" => resolution.to_h,
          "grounding" => { "valid" => true, "mode" => "declared_capability_registry" },
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

    def build_request(chat_id:, provider:, context:, orchestration:, evidence: [])
      messages = context.fetch("messages").map(&:dup)

      unless evidence.empty?
        messages << {
          "role" => "system",
          "content" => [
            "Deterministic evidence for this turn follows as JSON.",
            "Positive factual claims may use only collected values or claims.",
            "Items in not_collected are unknown and must never be described as healthy, present, absent, configured, or measured.",
            "State the scope of the check.",
            "Do not introduce CPU, memory, storage, filesystem, RAID, SMART, network, service, security, or scheduling facts unless collected evidence contains them.",
            "Explain the useful result naturally and return to the user's conversation.",
            JSON.pretty_generate(evidence)
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
          "runtime" => "conversational_soul_phase6",
          "orchestration" => orchestration.to_h,
          "evidence_ids" => evidence_ids(evidence),
          "context" => context_stats(context)
        }
      )
    end

    def execute_tools(tools, chat_id)
      tools.map do |tool|
        if tool.id == "host.system_status"
          result = @host_status_collector.collect
          evidence = EvidenceContract.build_structured(
            tool: tool,
            chat_id: chat_id,
            result: result
          )
          next @evidence_store.append(evidence)
        end

        begin
          output = @deterministic_responder.respond(tool.canonical_message)
          evidence = EvidenceContract.build(
            tool: tool,
            chat_id: chat_id,
            output: output,
            status: "ok"
          )
          @evidence_store.append(evidence)
        rescue StandardError => error
          evidence = EvidenceContract.build(
            tool: tool,
            chat_id: chat_id,
            output: "",
            status: "failed",
            error: {
              "class" => error.class.name,
              "message" => error.message
            }
          )
          @evidence_store.append(evidence)
        end
      end
    end

    def evidence_metadata(records)
      Array(records).map do |record|
        {
          "evidence_id" => record["evidence_id"],
          "tool_id" => record["tool_id"],
          "scope" => record["scope"],
          "status" => record["status"],
          "not_collected_count" => Array(record["not_collected"]).length
        }
      end
    end

    def evidence_ids(records)
      Array(records).map { |record| record["evidence_id"] }.compact
    end

    def deterministic_response(text, chat_id)
      parameters = @deterministic_responder.method(:respond).parameters
      accepts_chat_id = parameters.any? do |kind, name|
        ([:key, :keyreq].include?(kind) && name == :chat_id) || kind == :keyrest
      end
      if accepts_chat_id
        @deterministic_responder.respond(text, chat_id: chat_id)
      else
        @deterministic_responder.respond(text)
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
      tool_ids: [],
      evidence_ids: [],
      grounding: nil
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
        tool_ids: tool_ids,
        evidence_ids: evidence_ids,
        grounding: grounding
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
        "character_count" => 0,
        "evidence_count" => 0,
        "evidence_ids" => []
      }
    end

    def context_stats(context)
      {
        "total_message_count" => context.fetch("total_message_count", 0),
        "included_message_count" => context.fetch("included_message_count", 0),
        "truncated_message_count" => context.fetch("truncated_message_count", 0),
        "character_count" => context.fetch("character_count", 0),
        "evidence_count" => context.fetch("evidence_count", 0)
      }
    end

    def provider_error_reason(response)
      error = response.error || {}
      type = error["type"].to_s
      message = error["message"].to_s
      return "provider returned an empty response" if type.empty? && message.empty?
      return "#{type}: #{message}" unless type.empty? || message.empty?
      return type unless type.empty?

      message
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
