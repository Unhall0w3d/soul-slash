# frozen_string_literal: true

require_relative "chat_store"
require_relative "conversation_style_analyzer"

module SoulCore
  class ConversationStyleControls
    HELP_PATTERNS = [
      /\A\s*(?:style help|help style)\s*[?.!]*\z/i
    ].freeze
    RECENT_PATTERNS = [
      /\A\s*(?:show|inspect)\s+(?:recent\s+)?(?:response\s+)?style\s*[?.!]*\z/i,
      /\A\s*show\s+recent\s+variation\s*[?.!]*\z/i
    ].freeze
    POLICY_PATTERNS = [
      /\A\s*(?:show|inspect)\s+(?:variation|style)\s+policy\s*[?.!]*\z/i
    ].freeze

    def initialize(root: Dir.pwd, store: nil, analyzer: nil)
      @store = store || ChatStore.new(root: root)
      @analyzer = analyzer || ConversationStyleAnalyzer.new
    end

    def match?(message)
      text = message.to_s.strip
      all_patterns.any? { |pattern| text.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return render_help if HELP_PATTERNS.any? { |pattern| text.match?(pattern) }
      return render_policy if POLICY_PATTERNS.any? { |pattern| text.match?(pattern) }
      return render_recent(chat_id) if RECENT_PATTERNS.any? { |pattern| text.match?(pattern) }

      "Style control did not recognize that command.\n\n#{render_help}"
    end

    private

    def all_patterns
      HELP_PATTERNS + RECENT_PATTERNS + POLICY_PATTERNS
    end

    def render_help
      [
        "Soul Recent-Style Controls",
        "Mutation: none",
        "",
        "Commands",
        "- show recent style",
        "- show variation policy",
        "- style help",
        "",
        "These commands inspect bounded recent-turn analysis. They do not rewrite identity, memory, preferences, or prior responses."
      ].join("\n")
    end

    def render_policy
      policy = @analyzer.policy
      [
        "Soul Variation Policy",
        "Mutation: none",
        "Window: #{policy['window_size']} recent assistant turns",
        "Minimum sample: #{policy['minimum_sample']}",
        "Maximum guidance items: #{policy['maximum_guidance_items']}",
        "Raw responses stored by analyzer: no",
        "Persistent style profile: no",
        "Automatic identity mutation: no",
        "Priority: truth, safety, evidence, approvals, and requested format precede variation.",
        "Signal types: #{policy['signal_types'].join(', ')}"
      ].join("\n")
    end

    def render_recent(chat_id)
      return no_chat_message if chat_id.to_s.strip.empty?

      chat = @store.chat(chat_id)
      return no_chat_message unless chat

      analysis = @analyzer.analyze(messages: @store.messages(chat_id))
      lines = [
        "Soul Recent-Style Assessment",
        "Mutation: none",
        "Assistant samples: #{analysis['assistant_sample_count']}",
        "Eligible: #{analysis['eligible']}",
        "Persistent style profile: no",
        "Automatic identity mutation: no",
        ""
      ]

      if analysis.fetch("signals").empty?
        lines << "Signals"
        lines << "- none"
      else
        lines << "Signals"
        analysis.fetch("signals").each do |signal|
          lines << "- #{signal['type']}: #{signal['count']} occurrences; severity #{signal['severity']}; preview #{safe_preview(signal)}"
        end
      end

      lines << ""
      lines << "Variation guidance"
      if analysis.fetch("guidance").empty?
        lines << "- none"
      else
        analysis.fetch("guidance").each { |item| lines << "- #{item}" }
      end
      lines.join("\n")
    end

    def safe_preview(signal)
      value = signal["value"].to_s
      return "suppressed" if value.empty? || sensitive_value?(value)

      preview = value.gsub(/\s+/, " ").strip
      preview = "#{preview[0, 37]}..." if preview.length > 40
      preview.inspect
    end

    def sensitive_value?(value)
      value.match?(%r{https?://|/home/|/Users/|[A-Za-z]:\\}) ||
        value.match?(/(?:token|secret|password|api[-_ ]?key|private[-_ ]?key)/i) ||
        value.match?(/[A-Za-z0-9+\/_=-]{24,}/) ||
        value.include?("```")
    end

    def no_chat_message
      [
        "Soul Recent-Style Assessment",
        "Mutation: none",
        "No active persisted chat was available for inspection."
      ].join("\n")
    end
  end
end
