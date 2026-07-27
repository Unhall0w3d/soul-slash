# frozen_string_literal: true

require_relative "chat_store"

module SoulCore
  class ConversationPersonaControls
    DISABLE_PATTERNS = [
      /\A\s*(?:please\s+)?disable\s+(?:soul'?s\s+)?persona\s+for\s+(?:this|the)\s+(?:conversation|chat|transmission)\s*[?.!]*\z/i,
      /\A\s*(?:please\s+)?turn\s+(?:the\s+)?persona\s+off\s+(?:for|in)\s+(?:this|the)\s+(?:conversation|chat|transmission)\s*[?.!]*\z/i,
      /\A\s*(?:please\s+)?speak\s+without\s+(?:the\s+)?persona\s+for\s+(?:this|the)\s+(?:conversation|chat|transmission)\s*[?.!]*\z/i
    ].freeze
    ENABLE_PATTERNS = [
      /\A\s*(?:please\s+)?(?:enable|re-enable|reenable)\s+(?:soul'?s\s+)?persona\s+for\s+(?:this|the)\s+(?:conversation|chat|transmission)\s*[?.!]*\z/i,
      /\A\s*(?:please\s+)?turn\s+(?:the\s+)?persona\s+(?:back\s+)?on\s+(?:for|in)\s+(?:this|the)\s+(?:conversation|chat|transmission)\s*[?.!]*\z/i,
      /\A\s*(?:please\s+)?bring\s+(?:soul'?s|the)\s+persona\s+back\s*[?.!]*\z/i
    ].freeze
    STATUS_PATTERNS = [
      /\A\s*(?:show|check)\s+(?:the\s+)?persona\s+(?:mode|status)\s*[?.!]*\z/i,
      /\A\s*is\s+(?:soul'?s|the)\s+persona\s+(?:enabled|on|disabled|off)\s*[?.!]*\z/i
    ].freeze
    PATTERNS = (DISABLE_PATTERNS + ENABLE_PATTERNS + STATUS_PATTERNS).freeze

    def initialize(root: Dir.pwd, store: nil)
      @store = store || ChatStore.new(root: root)
    end

    def match?(message)
      text = message.to_s.strip
      PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      return awaiting_chat unless chat_id && @store.chat(chat_id)

      text = message.to_s.strip
      return set_mode(chat_id, false) if DISABLE_PATTERNS.any? { |pattern| text.match?(pattern) }
      return set_mode(chat_id, true) if ENABLE_PATTERNS.any? { |pattern| text.match?(pattern) }
      return status(chat_id) if STATUS_PATTERNS.any? { |pattern| text.match?(pattern) }

      "Persona control did not recognize that command.\nLifecycle: awaiting_input\nMutation: none"
    end

    private

    def set_mode(chat_id, enabled)
      @store.set_persona_enabled(chat_id, enabled: enabled)
      state = enabled ? "enabled" : "disabled"
      detail =
        if enabled
          "Soul's normal voice is restored for this conversation."
        else
          "Soul will use neutral, concise language in this conversation. Truth, privacy, evidence, skill routing, and approval boundaries are unchanged."
        end
      [
        "Persona expression is #{state} for this conversation.",
        detail,
        "Lifecycle: complete",
        "Mutation: conversation_metadata"
      ].join("\n")
    end

    def status(chat_id)
      enabled = @store.persona_enabled?(chat_id)
      [
        "Persona expression is #{enabled ? 'enabled' : 'disabled'} for this conversation.",
        "Scope: this conversation only",
        "Lifecycle: complete",
        "Mutation: none"
      ].join("\n")
    end

    def awaiting_chat
      [
        "Persona mode needs an active conversation.",
        "Lifecycle: awaiting_input",
        "Mutation: none"
      ].join("\n")
    end
  end
end
