# frozen_string_literal: true

module SoulCore
  class SelectionParser
    Result = Struct.new(:ok, :action, :selected_ids, :excluded_ids, :message, keyword_init: true)

    CANCEL_PATTERNS = [
      /\bcancel\b/,
      /\bstop\b/,
      /\bnever mind\b/,
      /\bdo nothing\b/,
      /\bno\b/
    ].freeze

    ALL_PATTERNS = [
      /\ball\b/,
      /\beverything\b/,
      /\ball of (it|them|these)\b/,
      /\bdelete all\b/,
      /\btrash all\b/,
      /\bmove all\b/,
      /\brestore all\b/
    ].freeze

    ONLY_PATTERNS = [
      /\bonly\b/,
      /\bjust\b/
    ].freeze

    EXCEPT_PATTERNS = [
      /\bexcept\b/,
      /\bexclude\b/,
      /\bskip\b/,
      /\bkeep\b/,
      /\bdon'?t (move|delete|trash|remove|restore)\b/
    ].freeze

    def parse(text, candidates)
      normalized = normalize(text)
      ids = candidates.map { |candidate| candidate.fetch("id") }

      if cancel?(normalized)
        return Result.new(
          ok: true,
          action: "cancel",
          selected_ids: [],
          excluded_ids: [],
          message: "Workflow cancelled."
        )
      end

      mentioned_ids = extract_ids(normalized, ids)
      mentioned_by_name = extract_name_matches(normalized, candidates)
      mentioned = (mentioned_ids + mentioned_by_name).uniq

      if except?(normalized)
        excluded = mentioned
        selected = ids - excluded

        return Result.new(
          ok: true,
          action: "select",
          selected_ids: selected,
          excluded_ids: excluded,
          message: excluded.empty? ? "Selected all candidates." : "Selected all candidates except #{excluded.join(', ')}."
        )
      end

      if only?(normalized)
        selected = mentioned

        return Result.new(
          ok: false,
          action: "clarify",
          selected_ids: [],
          excluded_ids: [],
          message: "I could not tell which items you meant."
        ) if selected.empty?

        return Result.new(
          ok: true,
          action: "select",
          selected_ids: selected,
          excluded_ids: ids - selected,
          message: "Selected only #{selected.join(', ')}."
        )
      end

      if all?(normalized)
        return Result.new(
          ok: true,
          action: "select",
          selected_ids: ids,
          excluded_ids: [],
          message: "Selected all candidates."
        )
      end

      unless mentioned.empty?
        return Result.new(
          ok: true,
          action: "select",
          selected_ids: mentioned,
          excluded_ids: ids - mentioned,
          message: "Selected #{mentioned.join(', ')}."
        )
      end

      Result.new(
        ok: false,
        action: "clarify",
        selected_ids: [],
        excluded_ids: [],
        message: "I could not determine whether to select all candidates, selected candidates, exclude candidates, or cancel."
      )
    end

    private

    def normalize(text)
      text.to_s.downcase.strip
    end

    def cancel?(normalized)
      CANCEL_PATTERNS.any? { |pattern| normalized.match?(pattern) }
    end

    def all?(normalized)
      ALL_PATTERNS.any? { |pattern| normalized.match?(pattern) }
    end

    def only?(normalized)
      ONLY_PATTERNS.any? { |pattern| normalized.match?(pattern) }
    end

    def except?(normalized)
      EXCEPT_PATTERNS.any? { |pattern| normalized.match?(pattern) }
    end

    def extract_ids(normalized, ids)
      ids.select { |id| normalized.match?(/\b#{Regexp.escape(id.downcase)}\b/) }
    end

    def extract_name_matches(normalized, candidates)
      matches = []

      candidates.each do |candidate|
        id = candidate.fetch("id")
        name = candidate.fetch("name", "").to_s.downcase
        path = candidate.fetch("path", "").to_s.downcase
        original_path = candidate.fetch("original_path", "").to_s.downcase

        base_names = [path, original_path]
                     .reject(&:empty?)
                     .map { |item| File.basename(item).downcase }

        values = ([name] + base_names).reject(&:empty?).uniq
        matches << id if values.any? { |value| normalized.include?(value) }
      end

      matches
    end
  end
end
