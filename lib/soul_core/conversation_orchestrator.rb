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

    INTEREST_CONTROL_PATTERNS = [
      /\A\s*(?:interest help|help interests?)\s*[?.!]*\z/i,
      /\A\s*(?:propose|add|remember)\s+interest\s*:\s*.+\z/i,
      /\A\s*(?:list|show)\s+(?:(?:candidate|approved|inactive|retired)\s+interests?|interest\s+(?:candidates?|approved|inactive|retired)|interests?)\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect)\s+interest\s+int_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*(?:approve|deactivate|reactivate|retire)\s+interest\s+(?:latest|int_[a-z0-9_]+)(?:\s+confirm)?\s*[?.!]*\z/i,
      /\A\s*(?:what are you interested in|what interests do you have|show your interests)\s*[?.!]*\z/i
    ].freeze
    STYLE_CONTROL_PATTERNS = [
      /\A\s*(?:style help|help style)\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect)\s+(?:recent\s+)?(?:response\s+)?style\s*[?.!]*\z/i,
      /\A\s*show\s+recent\s+variation\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect)\s+(?:variation|style)\s+policy\s*[?.!]*\z/i
    ].freeze
    IDENTITY_CONTROL_PATTERNS = [
      /\A\s*(?:identity help|help identity)\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect)\s+identity\s*[?.!]*\z/i,
      /\A\s*show\s+(?:personality|identity)\s+policy\s*[?.!]*\z/i,
      /\A\s*(?:show\s+tone\s+policy|inspect\s+tone\s+modes?)\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect)\s+identity\s+boundaries\s*[?.!]*\z/i
    ].freeze
    MEMORY_MAINTENANCE_PATTERNS = [
      /\A\s*(?:memory maintenance help|help memory maintenance)\s*[?.!]*\z/i,
      /\A\s*list\s+approved\s+reflections?\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect|preview|import)\s+approved\s+reflection\b/i,
      /\A\s*(?:export|verify)\s+memory\s+snapshot\b/i
    ].freeze

    MEMORY_CONTROL_PATTERNS = [
      /\A\s*(?:memory help|help memory)\s*[?.!]*\z/i,
      /\A\s*(?:what do you remember|show memories|show memory|list memories|list memory)(?:\s|\z)/i,
      /\A\s*(?:show|inspect|approve|forget|delete|supersede)\s+(?:latest\s+)?memory\b/i,
      /\A\s*(?:please\s+)?remember\s+(?:this|that)\b/i,
      /\A\s*(?:please\s+)?remember\s+(?:as\s+)?(?:project|preference|episodic|semantic)\s*[:\-]/i,
      /\A\s*propose\s+memory(?:\s+as)?\s+(?:project|preference|episodic|semantic)\s*[:\-]/i
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

      if INTEREST_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "reviewed-interest controls remain deterministic and human-approved",
          flags: flags.merge("interest_control" => true)
        )
      end
      if STYLE_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "recent-style inspection remains deterministic and read-only",
          flags: flags.merge("style_control" => true)
        )
      end
      if IDENTITY_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "identity policy inspection remains deterministic and read-only",
          flags: flags.merge("identity_control" => true)
        )
      end
      if MEMORY_MAINTENANCE_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "memory reflection import and snapshot controls require deterministic review boundaries",
          flags: flags.merge("memory_maintenance_control" => true)
        )
      end

      if MEMORY_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "durable memory controls require deterministic review and explicit approval",
          flags: flags.merge("memory_control" => true)
        )
      end

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
