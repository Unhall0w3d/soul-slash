# frozen_string_literal: true

module SoulCore
  module MemoryProtectionPolicy
    POLICY_VERSION = "soul.memory.protection.v1"
    PATTERNS = [
      /\b(?:password|passphrase|credential|secret|api[ _-]?key|private key|token)\b/i,
      /\b(?:permission|authority|authorization|sudo|root access|access grant)\b/i,
      /\b(?:delete permanently|destructive|wipe|purge|empty trash|format disk)\b/i,
      /\b(?:safety policy|security policy|firewall rule|protection boundary)\b/i,
      /\b(?:operator identity|owner identity|persona rule|system prompt)\b/i,
      /\b(?:export externally|publish private|retention policy|irreversible|bulk delete)\b/i
    ].freeze

    module_function

    def classify(content)
      PATTERNS.any? { |pattern| content.to_s.match?(pattern) } ?
        "protected_review_required" : "ordinary_candidate"
    end
  end
end
