# frozen_string_literal: true

module SoulCore
  class ConversationAcknowledgmentControls
    MICROPHONE_CHECK_PATTERNS = [
      /\A\s*testing[, ]+testing[, ]+(?:one|1)[, ]+(?:two|2)[, ]+(?:three|3)[.!]?(?:\s+if this (?:came|comes) through clearly,?\s+(?:we're|we are) good[.!]?)?\s*\z/i
    ].freeze
    PATTERNS = MICROPHONE_CHECK_PATTERNS.freeze

    def match?(message)
      PATTERNS.any? { |pattern| message.to_s.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      _unused = [message, chat_id]
      "That came through clearly."
    end
  end
end
