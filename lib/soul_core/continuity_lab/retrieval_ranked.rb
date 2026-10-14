# frozen_string_literal: true

module SoulCore
  module ContinuityLab
    # Opt-in lexical fallback. Retrieval is intentionally loaded by the caller;
    # this module stays pure and consumes the already-selected document set.
    module RankedRetrieval
      STOP_WORDS = %w[
        a an and are as at be been being but by can could did do does for from had
        has have he her hers him his how i if in into is it its may might my of on
        or our ours she should so than that the their theirs them then there these
        they this those to was we were what when where which who why will with would
        you your yours
      ].to_h { |word| [word, true] }.freeze
      UNINFLECTED = %w[news series species].to_h { |word| [word, true] }.freeze

      TOKEN_PATTERN = /[\p{L}\p{N}]+/.freeze

      def self.search(state, args, event_id, docs)
        # Preserve the historical result, including exact ranking, snippets,
        # truncation, and all error outcomes. Exact matches always win.
        legacy = Retrieval.result(state, "search", args, event_id)
        return legacy unless legacy["ok"]

        query_terms = meaningful_terms(args.fetch("query"))
        return legacy if query_terms.empty?

        normalized_docs = docs.map do |doc|
          tokens = token_rows(doc.fetch("content"))
          [doc, tokens]
        end
        exact_query = Retrieval.terms(args.fetch("query"))
        exact = normalized_docs.any? do |_doc, _tokens|
          words = _doc.fetch("content").downcase(:fold).scan(TOKEN_PATTERN)
          exact_query.all? { |term| words.include?(term) }
        end
        return legacy if exact

        minimum_matches = query_terms.length > 1 ? 2 : 1
        document_frequency = query_terms.to_h do |term|
          [term, normalized_docs.count { |_doc, tokens| tokens.any? { |row| row.fetch(:term) == term } }]
        end
        ranked = normalized_docs.filter_map do |doc, tokens|
          by_term = tokens.group_by { |row| row.fetch(:term) }
          matched = query_terms.select { |term| by_term.key?(term) }
          next if matched.length < minimum_matches

          missing = query_terms - matched
          # Summed inverse document frequency rewards distinctive overlap.
          score = matched.sum { |term| Rational(1, document_frequency.fetch(term)) }
          [doc, tokens, matched, missing, score]
        end.sort_by do |doc, _tokens, matched, _missing, score|
          [-score, -matched.length, doc.fetch("id")]
        end

        value = { "ok" => true, "hits" => [], "truncated" => false }
        ranked.first(args.fetch("limit")).each do |doc, tokens, matched, missing, _score|
          matched_rows = matched.filter_map do |term|
            token = tokens.find { |row| row.fetch(:term) == term }
            [term, [token.fetch(:start), token.fetch(:end)]] if token
          end
          anchor = matched_rows.map { |_term, span| span.first }.min || 0
          excerpt_start = [anchor - 32, 0].max
          source = Retrieval.source(state, args.fetch("collection"), doc, excerpt_start, 160)
          hit = source.merge(
            "matched_terms" => matched,
            "missing_terms" => missing,
            "coverage" => matched.length.to_f / query_terms.length,
            "matched_spans" => matched_rows.map { |term, span| { "term" => term, "span" => span } }
          )
          candidate = value.merge("hits" => value.fetch("hits") + [hit])
          if ContinuityLab.encode(candidate).bytesize > Retrieval::RESULT_BYTES
            value["truncated"] = true
            break
          end
          value = candidate
        end
        value["truncated"] = true if ranked.length > value.fetch("hits").length
        value
      end

      def self.meaningful_terms(text)
        text.downcase(:fold).scan(TOKEN_PATTERN).filter_map do |word|
          next if STOP_WORDS.key?(word)

          normalized = normalize(word)
          normalized unless STOP_WORDS.key?(normalized)
        end.uniq
      end

      def self.normalize(word)
        folded = word.downcase(:fold)
        return folded if UNINFLECTED.key?(folded)
        return folded.sub(/ies\z/, "y") if folded.length > 4 && folded.match?(/[^aeiou]ies\z/)
        return folded.delete_suffix("es") if folded.length > 4 && folded.match?(/(?:x|z|ch|sh)es\z/)
        return folded.delete_suffix("s") if folded.length > 3 && folded.end_with?("s") && !folded.match?(/(?:ss|us|is)\z/)

        folded
      end

      def self.token_rows(text)
        rows = []
        text.to_enum(:scan, TOKEN_PATTERN).each do
          match = Regexp.last_match
          rows << { term: normalize(match[0]), start: match.begin(0), end: match.end(0) }
        end
        rows
      end
      private_class_method :meaningful_terms, :normalize, :token_rows
    end
  end
end
