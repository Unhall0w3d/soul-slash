# frozen_string_literal: true

require "json"
require_relative "chat_responder"
require_relative "capability_gap_classifier"
require_relative "capability_gap_intake_service"
require_relative "conversation_artifact_creation_service"
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
      host_status_collector: nil,
      artifact_creation_service: nil,
      capability_gap_classifier: nil,
      capability_gap_intake_service: nil
    )
      @root = File.expand_path(root)
      @store = store
      @env = env
      @registry = registry || ConversationProviderRegistry.new(env: env)
      @provider_client = provider_client || ConversationProviderClient.new(env: env, root: @root)
      @artifact_creation_service = artifact_creation_service || ConversationArtifactCreationService.new(
        root: @root,
        env: env,
        provider_client: @provider_client
      )
      @deterministic_responder = deterministic_responder || ChatResponder.new(root: @root)
      @evidence_store = evidence_store || ConversationEvidenceStore.new(root: @root)
      @grounding_policy = grounding_policy || ConversationGroundingPolicy.new
      @evidence_followup_router = evidence_followup_router || ConversationEvidenceFollowupRouter.new
      @capability_registry = capability_registry || ConversationCapabilityRegistry.new
      @host_status_collector = host_status_collector || HostSystemStatusCollector.new
      @capability_gap_classifier = capability_gap_classifier || CapabilityGapClassifier.new
      @capability_gap_intake_service = capability_gap_intake_service || CapabilityGapIntakeService.new(root: @root)
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
      when "artifact_creation_preview"
        artifact_creation_preview(chat_id, text, decision)
      when "artifact_creation_control"
        artifact_creation_control(chat_id, text, decision)
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

    def artifact_creation_preview(chat_id, text, decision)
      provider = selected_artifact_provider
      outcome = @artifact_creation_service.preview(
        chat_id: chat_id,
        message: text,
        provider: provider
      )
      content = render_artifact_creation_outcome(outcome)
      context = safe_context(chat_id)
      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "artifact_creation_#{outcome.fetch('lifecycle_state')}",
        provider_id: provider&.id,
        fallback_reason: outcome["reason"],
        context: context,
        decision: decision
      )
      Result.new(
        content: content,
        mode: "artifact_creation_#{outcome.fetch('lifecycle_state')}",
        provider_id: provider&.id,
        fallback_reason: outcome["reason"],
        metadata: {
          "orchestration" => decision.to_h,
          "artifact_creation" => safe_artifact_creation_metadata(outcome),
          "context" => context_stats(context)
        }
      )
    end

    def artifact_creation_control(chat_id, text, decision)
      token_id = @artifact_creation_service.parse_token(text)
      outcome = if text.match?(/\A\s*cancel\b/i)
                  @artifact_creation_service.cancel(token_id: token_id, chat_id: chat_id)
                else
                  @artifact_creation_service.execute(
                    token_id: token_id,
                    confirm: text.match?(/\bconfirm\b/i),
                    chat_id: chat_id
                  )
                end
      content = render_artifact_creation_outcome(outcome)
      context = safe_context(chat_id)
      record_state(
        chat_id: chat_id,
        user_message: text,
        assistant_message: content,
        mode: "artifact_creation_#{outcome.fetch('lifecycle_state')}",
        fallback_reason: outcome["reason"],
        context: context,
        decision: decision
      )
      Result.new(
        content: content,
        mode: "artifact_creation_#{outcome.fetch('lifecycle_state')}",
        fallback_reason: outcome["reason"],
        metadata: {
          "orchestration" => decision.to_h,
          "artifact_creation" => safe_artifact_creation_metadata(outcome),
          "context" => context_stats(context)
        }
      )
    end

    def render_artifact_creation_outcome(outcome)
      lifecycle = outcome.fetch("lifecycle_state")
      case lifecycle
      when "awaiting_input"
        if outcome["token_id"]
          lines = [
            "Artifact creation preview",
            "Lifecycle: awaiting_input",
            "Operation: #{outcome['operation']}",
            "Target: #{outcome['target_path']}",
            "Privacy: #{outcome['privacy']}",
            "Provider: #{outcome['provider_id']}",
            "Size: #{outcome['size_bytes']} bytes / #{outcome['line_count']} lines",
            "SHA-256: #{outcome['sha256']}"
          ]
          lines << "Source artifact: #{outcome['source_artifact_id']}" if outcome["source_artifact_id"]
          lines.concat([
            "Redactions in preview: #{outcome['redaction_count']}",
            "",
            "Bounded redacted preview",
            outcome.fetch("excerpt", "").lines.map { |line| "| #{line.chomp}" }.join("\n"),
            "",
            "Approval token: #{outcome['token_id']}",
            "Expires: #{outcome['expires_at']}",
            "To create: create artifact #{outcome['token_id']} confirm",
            "To cancel: cancel artifact operation #{outcome['token_id']}",
            "Mutation: none"
          ])
          lines.join("\n")
        else
          [
            "Artifact creation needs more information.",
            "Reason: #{outcome['reason']}",
            "Lifecycle: awaiting_input",
            "Mutation: none"
          ].join("\n")
        end
      when "complete"
        [
          "Artifact created and attached.",
          "Lifecycle: complete",
          "Artifact ID: #{outcome['artifact_id']}",
          "Path: #{outcome['target_path']}",
          "Privacy: #{outcome['privacy']}",
          "Size: #{outcome['size_bytes']} bytes",
          "SHA-256 verified: #{outcome['hash_verified'] ? 'yes' : 'no'}",
          ("Revision of: #{outcome['source_artifact_id']}" if outcome["source_artifact_id"]),
          "Workspace delivery: #{outcome['delivery_state'] || 'not_recorded'}",
          ("Delivery ID: #{outcome['delivery_id']}" if outcome["delivery_id"]),
          ("Inbox delivery failed: #{outcome['delivery_failure_reason']}. Retry with: deliver artifact #{outcome['artifact_id']} to inbox" if outcome["delivery_state"] == "failed"),
          "Review the artifact before relying on or publishing it.",
          "Mutation: artifact_created"
        ].compact.join("\n")
      when "canceled"
        ["Artifact operation canceled.", "Lifecycle: canceled", "Mutation: none"].join("\n")
      when "blocked_for_human_review"
        [
          "Artifact operation is blocked for human review.",
          "Reason: #{outcome['reason']}",
          "Lifecycle: blocked_for_human_review",
          "Mutation: #{outcome['file_created'] ? 'verified_file_preserved' : 'none'}"
        ].join("\n")
      else
        [
          "Artifact operation failed safely.",
          "Reason: #{outcome['reason']}",
          "Lifecycle: failed",
          "Mutation: none"
        ].join("\n")
      end
    end

    def safe_artifact_creation_metadata(outcome)
      outcome.reject { |key, _value| %w[excerpt token_id].include?(key) }
    end

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
      context = safe_context(chat_id, provider: provider)
      terminal = artifact_inspection_terminal_result(
        chat_id: chat_id,
        message: text,
        decision: decision,
        context: context,
        provider_id: provider.id,
        prefix: @grounding_policy.render_evidence(evidence, heading: "Grounded deterministic result")
      )
      return terminal if terminal

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
      gap_intake = nil
      if mode == "capability_gap" && resolution&.matched?
        gap_intake = @capability_gap_intake_service.intake(
          chat_id: chat_id,
          request: text,
          classification: "declared_unavailable_capability",
          reason: resolution.reason,
          capability: resolution.capability
        )
        content = [content, render_gap_intake(gap_intake)].reject(&:empty?).join("\n\n")
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
          "capability_gap_intake" => gap_intake,
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

      context = safe_context(chat_id, provider: provider)
      terminal = artifact_inspection_terminal_result(
        chat_id: chat_id,
        message: text,
        decision: decision,
        context: context,
        provider_id: provider.id
      )
      return terminal if terminal

      request = build_request(
        chat_id: chat_id,
        provider: provider,
        context: context,
        orchestration: decision
      )
      response = provider_response(provider, request)

      if response.success? && !response.content.to_s.strip.empty?
        content = response.content.to_s.strip
        gap_classification = @capability_gap_classifier.classify(user_message: text, assistant_message: content)
        gap_intake = nil
        if gap_classification["candidate"] == true
          gap_intake = @capability_gap_intake_service.intake(
            chat_id: chat_id,
            request: text,
            classification: gap_classification.fetch("classification"),
            reason: gap_classification.fetch("reason")
          )
          content = [content, render_gap_intake(gap_intake)].reject(&:empty?).join("\n\n")
        end
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
            "capability_gap_classification" => gap_classification,
            "capability_gap_intake" => gap_intake,
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

    def render_gap_intake(result)
      return "" unless result.is_a?(Hash)

      case result["status"]
      when "created"
        [
          "I created a local Skill Studio proposal intake for this missing capability.",
          "Proposal: #{result['proposal_id']}",
          "It is attached to this conversation and delivered to the dashboard for your review.",
          "No cloud provider or implementation process was started. Human Gate 1 still applies."
        ].join("\n")
      when "deduplicated"
        [
          "This matches an existing Skill Studio proposal intake: #{result['proposal_id']}.",
          "I attached and delivered the existing proposal rather than creating a duplicate.",
          "No cloud provider or implementation process was started."
        ].join("\n")
      when "covered"
        coverage = result.fetch("coverage", {})
        if coverage["kind"] == "beta_skill"
          "A runnable Beta may cover this request: #{coverage['skill_id']}. I will not run it unless you explicitly ask me to try that Beta."
        else
          "A registered production skill may cover this request: #{coverage['skill_id']}. This is a routing or execution problem, so I did not create a duplicate proposal."
        end
      else
        reason = result["reason"].to_s
        reason.empty? ? "" : "I identified a possible capability gap, but proposal intake stopped safely: #{reason}"
      end
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

    def selected_artifact_provider
      preferred_id = @env["SOUL_CONVERSATION_PROVIDER"].to_s.strip
      preferred = preferred_id.empty? ? nil : @registry.find(preferred_id)
      if preferred&.configured? && %w[local_only local_network].include?(preferred.privacy_class)
        return preferred
      end

      candidates = @registry.configured.select do |item|
        %w[local_only local_network].include?(item.privacy_class)
      end
      candidates.find { |item| item.privacy_class == "local_only" } ||
        candidates.find { |item| item.privacy_class == "local_network" }
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

    def artifact_inspection_terminal_result(chat_id:, message:, decision:, context:, provider_id:, prefix: nil)
      inspection = context.fetch("artifact_inspection", {})
      lifecycle = inspection.fetch("lifecycle_state", "complete")
      return nil if lifecycle == "complete"

      detail = case lifecycle
               when "awaiting_input"
                 candidates = Array(inspection["candidate_artifact_ids"])
                 suffix = candidates.empty? ? "" : " Candidates: #{candidates.join(', ')}."
                 "I need a more specific attached artifact reference before reading content.#{suffix}"
               when "blocked_for_human_review"
                 ids = Array(inspection["blocked_artifact_ids"])
                 "Artifact inspection is blocked because #{ids.join(', ')} is not approved for the selected #{inspection['provider_privacy_class']} provider. Use a compatible local provider or complete a reviewed privacy change."
               else
                 failures = Array(inspection["failures"]).map do |failure|
                   "#{failure['artifact_id']}: #{failure['reason']}"
                 end
                 explanation = failures.empty? ? inspection.fetch("reason", "artifact inspection failed") : failures.join("; ")
                 "Artifact inspection failed safely. #{explanation}."
               end
      content = [prefix, detail, "Lifecycle: #{lifecycle}", "Content sent to provider: no", "Mutation: none"].compact.reject(&:empty?).join("\n\n")

      record_state(
        chat_id: chat_id,
        user_message: message,
        assistant_message: content,
        mode: "artifact_inspection_#{lifecycle}",
        provider_id: provider_id,
        fallback_reason: inspection.fetch("reason", lifecycle),
        context: context,
        decision: decision
      )

      Result.new(
        content: content,
        mode: "artifact_inspection_#{lifecycle}",
        provider_id: provider_id,
        fallback_reason: inspection.fetch("reason", lifecycle),
        metadata: {
          "orchestration" => decision.to_h,
          "artifact_inspection" => inspection,
          "context" => context_stats(context)
        }
      )
    end

    def safe_context(chat_id, provider: nil)
      @context_builder.build(
        chat_id: chat_id,
        provider_privacy_class: provider&.privacy_class
      )
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
