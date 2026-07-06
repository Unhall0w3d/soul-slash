# frozen_string_literal: true

module SoulCore
  class IntentRouter
    Result = Struct.new(:ok, :intent, :parameters, :confidence, :reason, keyword_init: true)

    def route(text)
      input = text.to_s.strip
      normalized = input.downcase

      return no_match("empty request") if normalized.empty?

      if downloads_cleanup?(normalized)
        return Result.new(
          ok: true,
          intent: "downloads.cleanup",
          parameters: {
            "target_path" => File.join(Dir.home, "Downloads"),
            "older_than_days" => extract_days(normalized) || 30,
            "include_directories" => true,
            "recursive" => false
          },
          confidence: 0.92,
          reason: "Matched Downloads cleanup phrasing and age threshold."
        )
      end

      no_match("no deterministic workflow matched")
    end

    private

    def downloads_cleanup?(normalized)
      mentions_downloads =
        normalized.include?("downloads") ||
        normalized.include?("download folder") ||
        normalized.include?("downloads folder")

      cleanup_action =
        normalized.match?(/\bclean ?up\b/) ||
        normalized.match?(/\bcleanup\b/) ||
        normalized.match?(/\bclear\b/) ||
        normalized.match?(/\bremove\b/) ||
        normalized.match?(/\btrash\b/) ||
        normalized.match?(/\bdelete\b/)

      mentions_age =
        normalized.match?(/older than\s+\d+\s+days?/) ||
        normalized.match?(/\b\d+\s+days?\s+old\b/) ||
        normalized.include?("old")

      mentions_downloads && cleanup_action && mentions_age
    end

    def extract_days(normalized)
      match = normalized.match(/older than\s+(\d+)\s+days?/)
      return match[1].to_i if match

      match = normalized.match(/\b(\d+)\s+days?\s+old\b/)
      return match[1].to_i if match

      nil
    end

    def no_match(reason)
      Result.new(ok: false, intent: nil, parameters: {}, confidence: 0.0, reason: reason)
    end
  end
end
