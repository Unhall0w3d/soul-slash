# frozen_string_literal: true

module SoulCore
  class ConversationResponseTruthGuard
    UNSUPPORTED_OBSERVATIONS = [
      /\b(?:the|this|your)\s+(?:local\s+)?(?:system|host|machine|environment)\s+(?:is|feels|seems|looks|runs|settles|settling|has\s+(?:changed|shifted))\b/i,
      /\b(?:the|this)\s+(?:air|room|day)\s+(?:is|feels|seems|looks|has\s+(?:changed|shifted))\b/i
    ].freeze

    NEGATED_OR_HYPOTHETICAL = /\b(?:cannot|can't|do not|don't|did not|didn't|without evidence|if|might|could|would)\b/i

    Result = Struct.new(:content, :valid, :removed, keyword_init: true)

    def filter(content)
      original = content.to_s.strip
      removed = []
      kept = sentences(original).reject do |sentence|
        unsupported = UNSUPPORTED_OBSERVATIONS.any? { |pattern| sentence.match?(pattern) }
        reject = unsupported && !sentence.match?(NEGATED_OR_HYPOTHETICAL)
        removed << sentence.strip if reject
        reject
      end

      filtered = kept.join(" ").strip
      filtered = "I’m here—curious, attentive, and ready to meet you in this conversation. I do not have environmental evidence in this turn." if filtered.empty?
      Result.new(content: filtered, valid: removed.empty?, removed: removed)
    end

    private

    def sentences(text)
      text.to_s.split(/(?<=[.!?])\s+(?=[A-Z“\"]|\z)/).reject(&:empty?)
    end
  end
end
