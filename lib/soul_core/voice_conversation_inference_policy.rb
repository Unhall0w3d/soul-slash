# frozen_string_literal: true

module SoulCore
  class VoiceConversationInferencePolicy
    DEFAULT_MAX_OUTPUT_TOKENS = 384
    DEEP_REASONING_PATTERN = /\b(?:think (?:carefully|deeply)|reason (?:carefully|through)|analy[sz]e in depth|deep analysis|detailed analysis|take your time)\b/i.freeze

    Decision = Struct.new(:reasoning_mode, :max_output_tokens, :reason, keyword_init: true)

    def decide(interface:, message:, provider_supports_reasoning_control:, default_max_output_tokens:)
      maximum = Integer(default_max_output_tokens)
      return default_decision(maximum, "the request did not originate in Voice Presence") unless interface.to_s == "voice_presence"
      return default_decision(maximum, "the Operator explicitly requested deeper reasoning") if message.to_s.match?(DEEP_REASONING_PATTERN)
      unless provider_supports_reasoning_control
        return default_decision(maximum, "the selected provider does not expose reviewed reasoning control")
      end

      Decision.new(
        reasoning_mode: "disabled",
        max_output_tokens: [maximum, DEFAULT_MAX_OUTPUT_TOKENS].min,
        reason: "ordinary spoken conversation favors low-latency local inference"
      )
    rescue ArgumentError, TypeError
      default_decision(1_024, "the configured output bound was invalid")
    end

    private

    def default_decision(maximum, reason)
      Decision.new(reasoning_mode: "default", max_output_tokens: maximum, reason: reason)
    end
  end
end
