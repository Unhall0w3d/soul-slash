# frozen_string_literal: true

require_relative "conversation_artifact_decision_policy"
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

    ARTIFACT_CONTROL_PATTERNS = [
      /\A\s*(?:artifact help|help artifacts?)\s*[?.!]*\z/i,
      /\A\s*register\s+artifact\s*:\s*.+\z/i,
      /\A\s*(?:list|show)\s+(?:all|chat|attached)\s+artifacts?\s*[?.!]*\z/i,
      /\A\s*(?:what artifacts? (?:are|is) attached|what is attached to this chat)\s*[?.!]*\z/i,
      /\A\s*show\s+artifact\s+art_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*(?:inspect|summari[sz]e)\s+artifact\s+art_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*(?:show\s+)?artifact\s+excerpt\s+art_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*compare\s+artifacts?\s+art_[a-z0-9_]+\s+(?:and|with|to)\s+art_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*(?:attach|detach|archive)\s+artifact\s+art_[a-z0-9_]+(?:\s+confirm)?\s*[?.!]*\z/i
    ].freeze

    ARTIFACT_CREATION_CONTROL_PATTERNS = [
      /\A\s*create\s+artifact\s+[a-f0-9]{32}(?:\s+confirm)?\s*[?.!]*\z/i,
      /\A\s*cancel\s+artifact\s+operation\s+[a-f0-9]{32}\s*[?.!]*\z/i
    ].freeze

    WORKSPACE_CONTROL_PATTERNS = [
      /\A\s*(?:workspace help|help workspace|help inbox)\s*[?.!]*\z/i,
      /\A\s*(?:(?:show|list)\s+(?:shared\s+)?workspace|what\s+is\s+in\s+my\s+workspace)\s*[?.!]*\z/i,
      /\A\s*(?:(?:show|list)\s+workspace\s+for\s+this\s+chat|show\s+me\s+what\s+soul\s+created\s+in\s+this\s+chat)\s*[?.!]*\z/i,
      /\A\s*(?:show|list)\s+(?:artifact\s+)?inbox\s*[?.!]*\z/i,
      /\A\s*show\s+workspace\s+artifact\s+art_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*deliver\s+artifact\s+art_[a-z0-9_]+\s+to\s+(?:the\s+)?inbox\s*[?.!]*\z/i,
      /\A\s*mark\s+delivery\s+del_[a-z0-9_]+\s+seen\s*[?.!]*\z/i,
      /\A\s*dismiss\s+delivery\s+del_[a-z0-9_]+\s*[?.!]*\z/i,
      /\A\s*cancel\s+workspace\s+request\s*[?.!]*\z/i,
      /\A\s*(?:send|deliver)\s+that\s+to\s+(?:the\s+)?inbox\s*[?.!]*\z/i,
      /\A\s*dismiss\s+it\s*[?.!]*\z/i,
      /\A.*\b(?:keep watching|watch)\b.*\bworkspace\b.*\z/i
    ].freeze

    ARTIFACT_REVISION_REQUEST = /\b(?:revise|revision|update)\b.{0,120}\b(?:artifact|report|document|notes?|json|text)\b/i

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
      artifact_policy: nil,
      max_tool_steps: MAX_TOOL_STEPS
    )
      @tool_catalog = tool_catalog || ConversationToolCatalog.new
      @router = router || IntentRouter.new
      @grounding_policy = grounding_policy || ConversationGroundingPolicy.new
      @artifact_policy = artifact_policy || ConversationArtifactDecisionPolicy.new
      @followup_router = followup_router || ConversationEvidenceFollowupRouter.new
      @capability_registry = capability_registry || ConversationCapabilityRegistry.new
      @max_tool_steps = normalize_limit(max_tool_steps)
    end

    def plan(message:, provider_available:, recent_evidence: [])
      text = message.to_s.strip
      raise ArgumentError, "Conversation message must not be empty" if text.empty?

      artifact_decision = @artifact_policy.classify(text)
      flags = {
        "memory_requested" => MEMORY_PATTERNS.any? { |pattern| text.match?(pattern) },
        "artifact_requested" => artifact_decision.artifact?,
        "artifact_decision" => artifact_decision.to_h,
        "recent_evidence_ids" => Array(recent_evidence).map { |record| record["evidence_id"] }
      }

      if ARTIFACT_CREATION_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "artifact_creation_control",
          reason: "artifact creation execution and cancellation remain deterministic and approval-gated",
          flags: flags.merge("artifact_creation_control" => true)
        )
      end

      if WORKSPACE_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "workspace and inbox operations are bounded deterministic artifact projections",
          flags: flags.merge("workspace_control" => true)
        )
      end

      if artifact_decision.required? || text.match?(ARTIFACT_REVISION_REQUEST)
        return decision(
          kind: "artifact_creation_preview",
          reason: "an explicit artifact deliverable requires bounded preview before any file write",
          requires_model: true,
          flags: flags.merge("artifact_creation_preview" => true)
        )
      end

      if ARTIFACT_CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
        return decision(
          kind: "deterministic_passthrough",
          reason: "artifact registration and attachment controls remain deterministic and explicit",
          flags: flags.merge("artifact_control" => true)
        )
      end

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
