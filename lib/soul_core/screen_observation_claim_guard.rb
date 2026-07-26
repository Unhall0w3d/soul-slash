# frozen_string_literal: true

module SoulCore
  class ScreenObservationClaimGuard
    LITERAL_CUE = /\b(?:applications?|apps?|browsers?|buttons?|channels?|controls?|headings?|labels?|menus?|names?|tabs?|texts?|titles?|videos?)\b/i
    QUOTED_CLAIM = /["“”']([^"“”'\n]{2,160})["“”']|\*\*([^*\n]{2,160})\*\*|\*([^*\n]{2,160})\*/.freeze
    PROPER_NAME_CLAIM = /\b([A-Z][A-Za-z0-9\/&'-]*(?:\s+[A-Z][A-Za-z0-9\/&'-]*)+)\b/.freeze

    def apply(content:, verification_context:)
      evidence = normalize(verification_context)
      removed = 0
      kept = content.to_s.strip.lines.reject do |line|
        claims = literal_claims(line)
        unsupported = line.match?(LITERAL_CUE) && claims.any? do |claim|
          normalized = normalize(claim)
          normalized.length >= 2 && !evidence.include?(normalized)
        end
        removed += 1 if unsupported
        unsupported
      end

      filtered = kept.join.strip
      if filtered.empty?
        filtered = "I captured the current view, but I could not verify enough literal interface detail to describe it reliably."
      elsif removed.positive?
        filtered = "#{filtered}\n\nI omitted one or more interface names or labels that the fresh capture did not verify."
      end

      {
        "content" => filtered,
        "applied" => true,
        "removed_claim_lines" => removed
      }
    end

    private

    def literal_claims(line)
      quoted = line.to_s.scan(QUOTED_CLAIM).map { |groups| groups.compact.first.to_s.strip }
      proper_names = line.to_s.gsub(/[*_]/, "").scan(PROPER_NAME_CLAIM).flatten.map(&:strip)
      (quoted + proper_names).reject(&:empty?).uniq
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end
  end
end
