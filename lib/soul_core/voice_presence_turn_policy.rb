# frozen_string_literal: true

module SoulCore
  class VoicePresenceTurnPolicy
    REPEAT_PATTERN = /\A(?:(?:please|could you|can you|would you) )?(?:repeat that|say that again|repeat your last response)(?: please)?\z/.freeze

    def repeat_request?(value)
      normalized = value.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
      REPEAT_PATTERN.match?(normalized)
    end
  end
end
