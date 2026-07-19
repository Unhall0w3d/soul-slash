# frozen_string_literal: true

module SoulCore
  class ConversationResponseTruthGuard
    UNSUPPORTED_OBSERVATIONS = [
      /\b(?:the|this|your)\s+(?:local\s+)?(?:system|host|machine|environment)\s+(?:is|feels|seems|looks|runs|settles|settling|has\s+(?:changed|shifted))\b/i,
      /\b(?:the|this)\s+(?:air|room|day)\s+(?:is|feels|seems|looks|has\s+(?:changed|shifted))\b/i,
      /\bI(?:'m| am| have been| was)\s+(?:processing|reviewing|monitoring|scanning|watching)\s+(?:the\s+)?(?:day'?s?|system|host|machine|files?|logs?|data)\b/i,
      /\bI(?:'ve| have)\s+been\s+(?:humming|working|waiting|watching|listening)\s+(?:along\s+)?(?:in the background|while you were away|for you)\b/i
    ].freeze

    EMOJI = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u

    NEGATED_OR_HYPOTHETICAL = /\b(?:cannot|can't|do not|don't|did not|didn't|without evidence|if|might|could|would)\b/i

    Result = Struct.new(:content, :valid, :removed, :style_adjustments, keyword_init: true)

    def filter(content, user_message: nil)
      original = content.to_s.strip
      removed = []
      style_adjustments = []
      kept = sentences(original).reject do |sentence|
        unsupported = UNSUPPORTED_OBSERVATIONS.any? { |pattern| sentence.match?(pattern) }
        reject = unsupported && !sentence.match?(NEGATED_OR_HYPOTHETICAL)
        removed << sentence.strip if reject
        reject
      end

      filtered = kept.join(" ").strip
      unless user_message.to_s.match?(EMOJI)
        without_emoji = filtered.gsub(EMOJI, "").gsub(/[ \t]+(?=[,.!?])/, "").gsub(/[ \t]{2,}/, " ").strip
        if without_emoji != filtered
          filtered = without_emoji
          style_adjustments << "removed unprompted emoji"
        end
      end
      filtered = "I’m here—curious, attentive, and ready to meet you in this conversation. I do not have environmental evidence in this turn." if filtered.empty?
      Result.new(content: filtered, valid: removed.empty?, removed: removed, style_adjustments: style_adjustments)
    end

    private

    def sentences(text)
      text.to_s.split(/(?<=[.!?])\s+(?=[A-Z“\"]|\z)/).reject(&:empty?)
    end
  end
end
