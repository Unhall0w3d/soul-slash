# frozen_string_literal: true

module SoulCore
  class ConversationStyleAnalyzer
    DEFAULT_WINDOW = 8
    MINIMUM_SAMPLE = 3
    MAX_GUIDANCE = 4

    DISCLAIMER_PATTERN = /\b(?:as an ai|i (?:cannot|can't|can not)\b|i(?:'m| am) unable\b|i (?:do not|don't) have (?:access|the ability|permission)\b)/i

    def initialize(window: DEFAULT_WINDOW)
      @window = positive_integer(window, DEFAULT_WINDOW)
    end

    def analyze(messages:)
      assistant_messages = Array(messages).select do |message|
        message["role"].to_s == "assistant" && !message["content"].to_s.strip.empty?
      end.last(@window)

      texts = assistant_messages.map { |message| message["content"].to_s.strip }
      signals = []
      signals.concat(repeated_signature_signals(texts, :opening))
      signals.concat(repeated_signature_signals(texts, :closing))
      signals.concat(repeated_sentence_signals(texts))
      signals.concat(repeated_structure_signals(texts))
      signals.concat(disclaimer_signals(texts))
      signals = signals.sort_by { |signal| [-signal.fetch("count"), signal.fetch("type")] }

      guidance = build_guidance(signals).first(MAX_GUIDANCE)

      {
        "window_size" => @window,
        "assistant_sample_count" => texts.length,
        "minimum_sample" => MINIMUM_SAMPLE,
        "eligible" => texts.length >= MINIMUM_SAMPLE,
        "signals" => texts.length >= MINIMUM_SAMPLE ? signals : [],
        "guidance" => texts.length >= MINIMUM_SAMPLE ? guidance : [],
        "automatic_identity_mutation" => false,
        "persistent_style_profile" => false
      }
    end

    def render_system_guidance(analysis)
      guidance = Array(analysis["guidance"])
      return "" if guidance.empty?

      lines = [
        "Recent style awareness:",
        "- This is bounded, observational guidance derived from recent assistant turns.",
        "- It never overrides truth, safety, deterministic routing, evidence, approvals, or the user's requested format.",
        "- Do not mention this analysis unless the user asks about response style."
      ]
      guidance.each { |item| lines << "- Variation guidance: #{item}" }
      lines.join("\n")
    end

    def policy
      {
        "window_size" => @window,
        "minimum_sample" => MINIMUM_SAMPLE,
        "signal_types" => %w[
          repeated_opening
          repeated_closing
          repeated_sentence
          repeated_structure
          disclaimer_overuse
        ],
        "maximum_guidance_items" => MAX_GUIDANCE,
        "stores_raw_responses" => false,
        "automatic_identity_mutation" => false,
        "persistent_style_profile" => false,
        "priority_boundary" => "truth_safety_evidence_approvals_and_user_format_precede_variation"
      }
    end

    private

    def repeated_signature_signals(texts, position)
      signatures = texts.filter_map do |text|
        position == :opening ? opening_signature(text) : closing_signature(text)
      end
      duplicate_counts(signatures).filter_map do |signature, count|
        next unless count >= 2

        {
          "type" => position == :opening ? "repeated_opening" : "repeated_closing",
          "value" => signature,
          "count" => count,
          "severity" => count >= 3 ? "high" : "moderate"
        }
      end
    end

    def repeated_sentence_signals(texts)
      sentences = texts.flat_map do |text|
        text.split(/(?<=[.!?])\s+|\n+/).filter_map do |sentence|
          normalized = normalize_words(sentence)
          words = normalized.split
          next if words.length < 4 || words.length > 18

          normalized
        end.uniq
      end

      duplicate_counts(sentences).filter_map do |sentence, count|
        next unless count >= 2

        {
          "type" => "repeated_sentence",
          "value" => sentence,
          "count" => count,
          "severity" => count >= 3 ? "high" : "moderate"
        }
      end
    end

    def repeated_structure_signals(texts)
      fingerprints = texts.map { |text| structure_fingerprint(text) }
      duplicate_counts(fingerprints).filter_map do |fingerprint, count|
        next unless count >= 3
        next if fingerprint == "unheaded/prose/no-code-fence/compact"

        {
          "type" => "repeated_structure",
          "value" => fingerprint,
          "count" => count,
          "severity" => "moderate"
        }
      end
    end

    def disclaimer_signals(texts)
      count = texts.count { |text| text.match?(DISCLAIMER_PATTERN) }
      return [] unless count >= 2

      [{
        "type" => "disclaimer_overuse",
        "value" => "limitation disclaimer",
        "count" => count,
        "severity" => count >= 3 ? "high" : "moderate"
      }]
    end

    def build_guidance(signals)
      signals.map do |signal|
        case signal.fetch("type")
        when "repeated_opening"
          "Avoid reopening with '#{signal.fetch('value')}'. Start directly with a different construction."
        when "repeated_closing"
          "Avoid repeating the closing '#{signal.fetch('value')}'. End when the answer is complete."
        when "repeated_sentence"
          "Do not reuse the sentence '#{signal.fetch('value')}'. Express the point only if it is relevant, using fresh wording."
        when "repeated_structure"
          "Vary the response shape from the recent #{signal.fetch('value')} pattern when the user's request permits it."
        when "disclaimer_overuse"
          "State a limitation once, specifically and close to the affected claim; do not repeat generic disclaimers."
        end
      end.compact.uniq
    end

    def opening_signature(text)
      first = text.lines.map(&:strip).find { |line| !line.empty? }
      signature(first, take: 5, from_end: false)
    end

    def closing_signature(text)
      last = text.lines.map(&:strip).reverse.find { |line| !line.empty? }
      signature(last, take: 5, from_end: true)
    end

    def signature(text, take:, from_end:)
      words = normalize_words(text).split
      return nil if words.length < 3

      selected = from_end ? words.last(take) : words.first(take)
      selected.join(" ")
    end

    def structure_fingerprint(text)
      lines = text.lines.map(&:rstrip)
      headings = lines.count { |line| line.match?(/\A\s{0,3}\#{1,6}\s+/) }
      bullets = lines.count { |line| line.match?(/\A\s*(?:[-*+] |\d+[.)] )/) }
      fences = lines.count { |line| line.strip.start_with?("```") }
      paragraphs = text.split(/\n\s*\n/).count { |part| !part.strip.empty? }

      shape = []
      shape << (headings.positive? ? "headed" : "unheaded")
      shape << (bullets >= 3 ? "list-heavy" : bullets.positive? ? "light-list" : "prose")
      shape << (fences >= 2 ? "code-fenced" : "no-code-fence")
      shape << (paragraphs >= 4 ? "multi-section" : "compact")
      shape.join("/")
    end

    def duplicate_counts(values)
      values.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }
    end

    def normalize_words(text)
      text.to_s.downcase
        .gsub(/[`*_>#\[\](){}]/, " ")
        .gsub(/[^a-z0-9'\-\s]/, " ")
        .gsub(/\s+/, " ")
        .strip
    end

    def positive_integer(value, fallback)
      number = value.to_i
      number.positive? ? number : fallback
    end
  end
end
