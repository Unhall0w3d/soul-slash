# frozen_string_literal: true

module SoulCore
  # Only a direct spoken address may resolve an ASR homophone. The raw
  # transcript remains visible; geography and ordinary prose stay untouched.
  class VoicePresenceAddressResolver
    ADDRESS = /\A(?<name>Sol|Sole|Seoul)\s*,\s*(?<request>(?:what|how|why|when|where|can|could|would|will|please|tell|show|explain|describe)\b.*)\z/i

    def resolve(transcript)
      text = transcript.to_s.strip
      match = ADDRESS.match(text)
      match ? "Soul, #{match[:request]}" : text
    end
  end
end
