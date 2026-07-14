# frozen_string_literal: true

module SoulCore
  class ConversationArtifactReferenceResolver
    ARTIFACT_ID = /art_[a-z0-9_]+/i

    KIND_CUES = {
      "report" => %w[report assessment],
      "document" => %w[document markdown notes],
      "dataset" => %w[dataset data json csv],
      "spreadsheet" => %w[spreadsheet workbook csv],
      "code" => %w[code script source],
      "overlay" => %w[overlay],
      "package" => %w[package bundle archive]
    }.freeze

    GENERIC_REFERENCE = /\b(?:attached artifact|attached file|this artifact|that artifact|the artifact|earlier artifact)\b/i

    def resolve(message:, records:, limit: 2)
      text = message.to_s.strip
      available = Array(records).select { |record| record.is_a?(Hash) }
      maximum = normalize_limit(limit)

      ids = text.scan(ARTIFACT_ID).map(&:downcase).uniq
      unless ids.empty?
        selected = ids.filter_map do |artifact_id|
          available.find { |record| record["artifact_id"].to_s.downcase == artifact_id }
        end.first(maximum)
        missing = ids - selected.map { |record| record["artifact_id"].to_s.downcase }
        return result(selected, "explicit_artifact_id", ambiguous: !missing.empty? || ids.length > maximum, missing_ids: missing)
      end

      title_matches = match_titles(text, available)
      unless title_matches.empty?
        ambiguous = title_matches.length > 1 && !plural_reference?(text)
        return result(title_matches.first(maximum), "title_reference", ambiguous: ambiguous || title_matches.length > maximum)
      end

      kind_matches = match_kinds(text, available)
      unless kind_matches.empty?
        ambiguous = kind_matches.length > 1 && !plural_reference?(text)
        return result(kind_matches.first(maximum), "kind_reference", ambiguous: ambiguous || kind_matches.length > maximum)
      end

      if text.match?(GENERIC_REFERENCE) && available.length == 1
        return result(available.first(1), "single_attached_artifact", ambiguous: false)
      end

      result([], available.empty? ? "no_attached_artifacts" : "no_unambiguous_reference", ambiguous: false)
    end

    private

    def match_titles(text, records)
      normalized_message = normalize(text)
      records.select do |record|
        title = normalize(record["title"])
        next false if title.length < 4

        normalized_message.include?(title) || significant_words(title).any? do |word|
          word.length >= 5 && normalized_message.match?(/\b#{Regexp.escape(word)}\b/)
        end
      end
    end

    def match_kinds(text, records)
      normalized_message = normalize(text)
      cues = KIND_CUES.select do |_kind, words|
        words.any? { |word| normalized_message.match?(/\b#{Regexp.escape(word)}s?\b/) }
      end
      return [] if cues.empty?

      records.select do |record|
        kind = record["kind"].to_s.downcase
        media = record["media_type"].to_s.downcase
        path = record["relative_path"].to_s.downcase
        cues.any? do |expected_kind, words|
          kind == expected_kind || words.any? { |word| path.include?(word) || media.include?(word) }
        end
      end
    end

    def plural_reference?(text)
      text.match?(/\b(?:artifacts|files|reports|documents|datasets|spreadsheets|workbooks|scripts|overlays|packages)\b/i) ||
        text.match?(/\bcompare\b/i)
    end

    def significant_words(text)
      text.scan(/[a-z0-9]+/).reject do |word|
        word.length < 4 || %w[this that with from into file artifact document].include?(word)
      end
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def normalize_limit(value)
      number = value.to_i
      number = 2 unless number.positive?
      [number, 5].min
    end

    def result(records, reason, ambiguous:, missing_ids: [])
      {
        "records" => records,
        "artifact_ids" => records.map { |record| record["artifact_id"] },
        "reason" => reason,
        "ambiguous" => ambiguous,
        "missing_ids" => missing_ids
      }
    end
  end
end
