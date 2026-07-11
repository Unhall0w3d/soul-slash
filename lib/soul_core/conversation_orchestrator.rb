# frozen_string_literal: true

require_relative "conversation_capability_registry"
require_relative "conversation_evidence_followup_router"
require_relative "conversation_grounding_policy"
require_relative "conversation_orchestration_contract"
require_relative "conversation_tool_catalog"
require_relative "intent_router"

module SoulCore
  class ConversationOrchestrator
    Contract = ConversationOrchestrationContract

    MAX_TOOL_STEPS = 2

    CONTROL_PATTERNS = [
      /\b(approve downloads cleanup preview|approve cleanup preview)\b/i,
      /\b(pending approvals|show approvals|list approvals)\b/i,
      /\brevoke approval\b/i,
      /\b(dry run downloads move|dry run move approved downloads|preview approved downloads move)\b/i,
      /\bmove approved downloads to trash\b/i,
      /\b(clear history|prune history|export history)\b/i,
      /\b(adapter registry|execution adapters|list adapters|enabled adapters|blocked adapters)\b/i
    ].freeze

    MEMORY_PATTERNS = [
      /\b(remember|earlier|last time|previously|we discussed|we talked about|you should know)\b/i
    ].freeze

    ARTIFACT_PATTERNS = [
      /\b(report|overlay|zip|csv|spreadsheet|workbook|document|file|package|presentation)\b/i
    ].freeze

    DETERMINISTIC_INTENTS = %w[identity].freeze

    INTENT_TOOL_MAP = {
      "skill_catalog" => "assistant-skill-catalog",
      "repo_status" => "system.status",
      "downloads_inspect" => "downloads.inspect",
      "downloads_cleanup_plan" => "downloads.cleanup_plan"
    }.freeze

    def initialize(
      tool_catalog: nil,
      router: nil,
      capability_registry: nil,
      followup_router: nil,
      grounding_policy: nil,
      max_tool_steps: MAX_TOOL_STEPS
    )
      @tool_catalog = tool_catalog || ConversationToolCatalog.new
      @router = router || IntentRouter.new
      @grounding_policy = grounding_policy || ConversationGroundingPolicy.new
      @followup_router = followup_router || ConversationEvidenceFollowupRouter.new
      @capability_registry = capability_registry || ConversationCapabilityRegistry.new
      @max_tool_steps = normalize_limit(max_tool_steps)
    end

    def plan(message:, provider_available:, recent_evidence: [])
      text = message.to_s.strip
      raise ArgumentError, "Conversation message must not be empty" if text.empty?

      flags = {
        "memory_requested" => MEMORY_PATTERNS.any? { |pattern| text.match?(pattern) },
        "artifact_requested" => ARTIFACT_PATTERNS.any? { |pattern| text.match?(pattern) },
        "recent_evidence_ids" => Array(recent_evidence).map { |record| record["evidence_id"] }
      }

      if CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "approval, mutation, registry, or history control remains deterministic",
          flags: flags
        )
      end

      followup = @followup_router.route(
        message: text,
        evidence_records: recent_evidence
      )
      if followup.matched?
        return decision(
          kind: "evidence_followup",
          reason: followup.reason,
          flags: flags.merge("evidence_followup" => followup.to_h)
        )
      end

      capability = @capability_registry.resolve(text)
      if capability.catalog?
        return decision(
          kind: "capability_catalog",
          reason: capability.reason,
          flags: flags.merge("capability" => capability.to_h)
        )
      end

      if capability.gap?
        return decision(
          kind: "capability_gap",
          reason: capability.reason,
          flags: flags.merge(
            "requested_capability" => capability.capability.id,
            "capability" => capability.to_h
          )
        )
      end

      if capability.info?
        return decision(
          kind: "capability_info",
          reason: capability.reason,
          flags: flags.merge(
            "requested_capability" => capability.capability.id,
            "capability" => capability.to_h
          )
        )
      end

      intent = safe_intent(text)
      if DETERMINISTIC_INTENTS.include?(intent)
        return decision(
          kind: "deterministic_passthrough",
          reason: "identity and fixed control surfaces remain deterministic",
          flags: flags
        )
      end

      tools = matched_tools(text, intent).first(@max_tool_steps)
      unless tools.empty?
        if provider_available && tools.all? { |tool| tool.synthesis_allowed == true }
          return decision(
            kind: "skill_then_model",
            reason: "bounded informational skills are relevant and grounded synthesis is available",
            tools: tools,
            requires_model: true,
            synthesize: true,
            max_steps: tools.length,
            flags: flags
          )
        end

        return decision(
          kind: "skill_only",
          reason: "deterministic evidence should be returned without model synthesis",
          tools: tools,
          max_steps: tools.length,
          flags: flags
        )
      end

      if provider_available
        return decision(
          kind: "direct_model",
          reason: "no registered deterministic skill is relevant",
          requires_model: true,
          flags: flags
        )
      end

      decision(
        kind: "deterministic_fallback",
        reason: "no configured conversation provider and no relevant deterministic skill",
        flags: flags
      )
    end

    private

    def matched_tools(text, intent)
      matches = @tool_catalog.match(text)
      host = matches.find { |tool| tool.id == "host.system_status" }
      return [host] if host

      mapped_id = INTENT_TOOL_MAP[intent]
      mapped = mapped_id && @tool_catalog.find(mapped_id)
      matches << mapped if mapped && !matches.include?(mapped)
      matches.uniq { |tool| tool.id }
    end

    def safe_intent(text)
      @router.route(text).id.to_s
    rescue StandardError
      ""
    end

    def decision(
      kind:,
      reason:,
      tools: [],
      requires_model: false,
      synthesize: false,
      max_steps: 0,
      flags: {}
    )
      Contract::Decision.new(
        kind: kind,
        reason: reason,
        tools: tools,
        requires_model: requires_model,
        synthesize: synthesize,
        max_steps: max_steps,
        flags: flags
      )
    end

    def normalize_limit(value)
      number = value.to_i
      return MAX_TOOL_STEPS unless number.positive?

      [number, MAX_TOOL_STEPS].min
    end
  end
end
