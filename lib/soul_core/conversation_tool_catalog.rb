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
        id: "host.system_status",
        label: "Host system status",
        risk_class: "read_only",
        canonical_message: "assess host system",
        synthesis_allowed: false,
        scope: "Bounded read-only Linux host environment assessment",
        evidence_profile: "host_system_status",
        patterns: [
          /\b(?:check|inspect|show|assess)\b.{0,50}\b(?:linux md(?: raid)?|mdraid|\/proc\/mdstat)\b/i,
          /\A\s*(?:system status|host status|computer status|machine status)\s*[?.!]*\s*\z/i,
          /\b(?:check|inspect|show|assess|review|scan|survey|report|run|give me|tell me)\b.{0,45}\b(?:system status|host status|computer status|machine status)\b/i,
          /\b(?:what(?:'s| is)|how(?:'s| is))\b.{0,35}\b(?:system|host|computer|machine)\b.{0,20}\b(?:status|health|doing|running)\b/i,
          /\b(?:assess(?:ment)?|inspect|diagnose|audit|check|review|scan|survey)\b.{0,50}\b(?:environment|host|computer|machine|hardware|operating system|os)\b/i,
          /\b(?:environment|host|computer|machine|hardware|operating system|os)\b.{0,50}\b(?:assess(?:ment)?|inspect|diagnose|audit|check|review|scan|survey)\b/i,
          /\bwhat\b.{0,45}\b(?:filesystems?|disks?|drives?|storage devices?|block devices?|hardware)\b.{0,45}\b(?:do i have|are present|are attached|are mounted)\b/i,
          /\b(?:show|list|inspect|check)\b.{0,35}\b(?:my )?(?:filesystems?|disks?|drives?|storage devices?|block devices?)\b/i,
          /\b(?:filesystems?|disks?|drives?)\b.{0,25}\b(?:do i have|are mounted|are attached)\b/i
        ]
      ),
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
          /\b(soul status|runtime status|soul runtime status|status of soul)\b/i
        ]
      ),
      ToolDefinition.new(
        id: "assistant-skill-catalog",
        label: "Assistant skill catalog",
        risk_class: "read_only",
        canonical_message: "what skills do you have?",
        synthesis_allowed: false,
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
