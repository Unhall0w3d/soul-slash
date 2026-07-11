# frozen_string_literal: true

module SoulCore
  class ConversationToolCatalog
    ToolDefinition = Struct.new(
      :id,
      :label,
      :risk_class,
      :canonical_message,
      :synthesis_allowed,
      :scope,
      :evidence_profile,
      :patterns,
      keyword_init: true
    ) do
      def matches?(message)
        patterns.any? { |pattern| message.match?(pattern) }
      end

      def to_h
        {
          "id" => id,
          "label" => label,
          "risk_class" => risk_class,
          "canonical_message" => canonical_message,
          "synthesis_allowed" => synthesis_allowed == true,
          "scope" => scope,
          "evidence_profile" => evidence_profile
        }
      end
    end

    DEFINITIONS = [
      ToolDefinition.new(
        id: "system.status",
        label: "Soul runtime status",
        risk_class: "read_only",
        canonical_message: "status",
        synthesis_allowed: false,
        scope: "Soul application and registered-runtime status only",
        evidence_profile: "soul_runtime_status",
        patterns: [
          /\Astatus\z/i,
          /\b(system status|soul status|runtime status|status of (?:the )?system|check (?:the )?system|how is (?:the )?system)\b/i
        ]
      ),
      ToolDefinition.new(
        id: "assistant-skill-catalog",
        label: "Assistant skill catalog",
        risk_class: "read_only",
        canonical_message: "what skills do you have?",
        synthesis_allowed: true,
        scope: "Registered Soul assistant skills",
        evidence_profile: "skill_catalog",
        patterns: [
          /\b(what skills|list skills|available skills|skill catalog|show skills)\b/i
        ]
      ),
      ToolDefinition.new(
        id: "downloads.inspect",
        label: "Downloads inspection",
        risk_class: "read_only",
        canonical_message: "inspect downloads",
        synthesis_allowed: true,
        scope: "Configured Downloads directory inspection",
        evidence_profile: "downloads_inspection",
        patterns: [
          /\b(inspect|check|review|show|analy[sz]e|what(?:'s| is))\b.{0,40}\bdownloads\b/i,
          /\bdownloads\b.{0,40}\b(inspect|check|review|show|analy[sz]e|contents?)\b/i
        ]
      ),
      ToolDefinition.new(
        id: "downloads.cleanup_plan",
        label: "Downloads cleanup preview",
        risk_class: "review_only",
        canonical_message: "clean up downloads",
        synthesis_allowed: true,
        scope: "Review-only cleanup candidates in the configured Downloads directory",
        evidence_profile: "downloads_cleanup_preview",
        patterns: [
          /\b(clean(?:up)?|organize|free space|cleanup plan|cleanup preview)\b.{0,40}\bdownloads\b/i,
          /\bdownloads\b.{0,40}\b(clean(?:up)?|organize|free space|cleanup plan|cleanup preview)\b/i
        ]
      ),
      ToolDefinition.new(
        id: "execution.history.summary",
        label: "Execution history summary",
        risk_class: "read_only",
        canonical_message: "execution history summary",
        synthesis_allowed: true,
        scope: "Soul execution-history records",
        evidence_profile: "execution_history_summary",
        patterns: [
          /\b(execution history summary|summari[sz]e execution history|recent execution history)\b/i
        ]
      )
    ].freeze

    def definitions
      DEFINITIONS
    end

    def find(tool_id)
      definitions.find { |tool| tool.id == tool_id.to_s }
    end

    def match(message)
      text = message.to_s
      definitions.select { |tool| tool.matches?(text) }
    end

    def summary
      {
        "tool_count" => definitions.length,
        "tools" => definitions.map(&:to_h)
      }
    end
  end
end
