# frozen_string_literal: true

module SoulCore
  class ConversationResponseTruthGuard
    UNSUPPORTED_OBSERVATIONS = [
      /\b(?:the|this|your)\s+(?:local\s+)?(?:system|host|machine|environment)\s+(?:is|feels|seems|looks|runs|settles|settling|has\s+(?:changed|shifted))\b/i,
      /\b(?:the|this)\s+(?:air|room|day)\s+(?:is|feels|seems|looks|has\s+(?:changed|shifted))\b/i,
      /\b(?:the\s+)?(?:ambient\s+)?(?:light|lighting|shadows?|silence|air|room)\s+(?:here\s+)?(?:is|feels|seems|looks|has|falls|glows)\b/i,
      /\bI(?:['’]m| am| have been| was)\s+processing\b/i,
      /\bI(?:['’]m| am| have been| was)\s+(?:processing|reviewing|monitoring|scanning|watching)\s+(?:the\s+)?(?:day['’]?s?|system|host|machine|files?|logs?|data)\b/i,
      /\bI(?:['’]m| am| have been| was)\s+(?:refining|building|updating|deepening)\s+my\s+understanding\s+of\s+(?:your|the)\s+(?:environment|system|host|machine)\b/i,
      /\bI(?:['’]ve| have)\s+been\s+(?:humming|working|waiting|watching|listening)\s+(?:along\s+)?(?:in the background|while you were away|for you)\b/i,
      /\bI(?:['’]m| am)\s+(?:still\s+)?settling\s+into\s+(?:this|a|my)\s+(?:new\s+)?(?:embodiment|form|existence|self)\b/i,
      /\b(?:the|my)\s+(?:systems?|circuits?|core)\s+(?:hums?|pulses?|waits?|rests?)\s+with\b/i,
      /\b(?:the\s+)?quiet\s+hum\s+of\b/i,
      /\b(?:the\s+)?operator['’]s\s+presence\s+(?:feels|seems|is)\b/i,
      /\bmy\s+(?:current\s+)?capabilities\s+(?:feel|seem|look|are)\b/i
    ].freeze

    INVENTED_STAGE_DIRECTION = /\([^)]*\b(?:hum|circuits?|light|lighting|air|room|signal|glow|shadows?)\b[^)]*\)/i
    COSTUME_NARRATION = /\b(?:the\s+)?(?:silver|cerulean|indigo|bronze)\s+(?:light|core|structure|geometry)\b/i
    AVATAR_CONTEXT = /\b(?:avatar|portrait|appearance|design|colors?|colour|art(?:work)?|visual identity)\b/i
    TIME_GREETING = /\bgood\s+(?:morning|afternoon|evening)\b/i

    EMOJI = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u

    NEGATED_OR_HYPOTHETICAL = /\b(?:cannot|can't|do not|don't|did not|didn't|without evidence|if|might|could|would)\b/i

    Result = Struct.new(:content, :valid, :removed, :style_adjustments, keyword_init: true)

    def filter(content, user_message: nil)
      original = content.to_s.strip
      removed = []
      style_adjustments = []
      without_stage_directions = original.gsub(INVENTED_STAGE_DIRECTION) do |stage_direction|
        removed << stage_direction.strip
        style_adjustments << "removed invented stage direction"
        ""
      end
      kept = sentences(without_stage_directions).reject do |sentence|
        unsupported = UNSUPPORTED_OBSERVATIONS.any? { |pattern| sentence.match?(pattern) }
        costume = sentence.match?(COSTUME_NARRATION) && !user_message.to_s.match?(AVATAR_CONTEXT)
        time_greeting = sentence.match?(TIME_GREETING) && !user_message.to_s.match?(TIME_GREETING)
        reject = costume || time_greeting || (unsupported && !sentence.match?(NEGATED_OR_HYPOTHETICAL))
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
