# frozen_string_literal: true

require_relative "llm_intent_classifier"

module SoulCore
  class IntentRouter
    Result = Struct.new(:ok, :intent, :parameters, :confidence, :reason, :source, keyword_init: true)

    def route(text)
      input = text.to_s.strip
      normalized = input.downcase
      return no_match("empty request", source: "deterministic") if normalized.empty?

      deterministic = route_deterministic(input, normalized)
      return deterministic if deterministic.ok

      llm_result = LlmIntentClassifier.new.classify(input)

      if llm_result[:ok]
        return Result.new(
          ok: true,
          intent: llm_result[:intent],
          parameters: llm_result[:parameters],
          confidence: llm_result[:confidence],
          reason: llm_result[:reason],
          source: llm_result[:source]
        )
      end

      no_match(llm_result[:reason] || deterministic.reason, source: "hybrid")
    end

    def inspect_route(text)
      route(text)
    end

    private

    def route_deterministic(input, normalized)
      if weather_report?(normalized)
        location = extract_weather_location(input) || ENV.fetch("SOUL_WEATHER_LOCATION", nil)
        return Result.new(
          ok: true,
          intent: "weather.report",
          parameters: {
            "location" => location,
            "units" => ENV.fetch("SOUL_WEATHER_UNITS", "fahrenheit")
          },
          confidence: location.to_s.strip.empty? ? 0.74 : 0.93,
          reason: location.to_s.strip.empty? ? "Matched weather phrasing but no location was found." : "Matched weather phrasing and extracted location.",
          source: "deterministic"
        )
      end

      if downloads_restore_last_cleanup?(normalized)
        return Result.new(
          ok: true,
          intent: "downloads.restore_last_cleanup",
          parameters: { "target_path" => File.join(Dir.home, "Downloads") },
          confidence: 0.91,
          reason: "Matched restore/undo phrasing for the last Downloads cleanup.",
          source: "deterministic"
        )
      end

      if downloads_cleanup?(normalized)
        days = extract_days(normalized) || 30
        return Result.new(
          ok: true,
          intent: "downloads.cleanup",
          parameters: {
            "target_path" => File.join(Dir.home, "Downloads"),
            "older_than_days" => days,
            "include_directories" => true,
            "recursive" => false
          },
          confidence: deterministic_confidence(normalized),
          reason: deterministic_reason(normalized, days),
          source: "deterministic"
        )
      end

      no_match("no deterministic workflow matched", source: "deterministic")
    end

    def weather_report?(normalized)
      weather_terms = normalized.match?(/\bweather\b/) ||
                      normalized.match?(/\bforecast\b/) ||
                      normalized.match?(/\btemperature\b/) ||
                      normalized.match?(/\bhumidity\b/) ||
                      normalized.match?(/\bair quality\b/) ||
                      normalized.match?(/\baqi\b/)

      today_context = normalized.match?(/\btoday\b/) ||
                      normalized.match?(/\bnow\b/) ||
                      normalized.match?(/\bcurrent\b/) ||
                      normalized.match?(/\bwhat'?s it like\b/) ||
                      normalized.match?(/\boutside\b/) ||
                      normalized.match?(/\bforecast\b/)

      weather_terms && today_context
    end

    def extract_weather_location(input)
      patterns = [
        /\bweather\s+(?:today\s+)?(?:in|for|near)\s+(.+)$/i,
        /\bforecast\s+(?:today\s+)?(?:in|for|near)\s+(.+)$/i,
        /\b(?:in|for|near)\s+([A-Za-z][A-Za-z0-9\s,.'-]+)\??$/i
      ]

      patterns.each do |pattern|
        match = input.match(pattern)
        next unless match

        location = match[1].to_s.strip
        location = location.sub(/[?.!]\z/, "").strip
        return location unless location.empty?
      end

      nil
    end

    def downloads_restore_last_cleanup?(normalized)
      restore_action = normalized.match?(/\brestore\b/) ||
                       normalized.match?(/\bundo\b/) ||
                       normalized.match?(/\brollback\b/) ||
                       normalized.match?(/\broll back\b/) ||
                       normalized.match?(/\bput back\b/)

      cleanup_context = normalized.include?("downloads") ||
                        normalized.include?("download folder") ||
                        normalized.include?("cleanup") ||
                        normalized.include?("clean up") ||
                        normalized.include?("trash")

      last_context = normalized.include?("last") ||
                     normalized.include?("latest") ||
                     normalized.include?("previous") ||
                     normalized.include?("what soul moved")

      restore_action && cleanup_context && last_context
    end

    def downloads_cleanup?(normalized)
      mentions_downloads = normalized.include?("downloads") ||
                           normalized.include?("download folder") ||
                           normalized.include?("downloads folder") ||
                           normalized.include?("download directory") ||
                           normalized.include?("downloads directory")

      cleanup_action = normalized.match?(/\bclean ?up\b/) ||
                       normalized.match?(/\bcleanup\b/) ||
                       normalized.match?(/\bclear\b/) ||
                       normalized.match?(/\bremove\b/) ||
                       normalized.match?(/\btrash\b/) ||
                       normalized.match?(/\bdelete\b/) ||
                       normalized.match?(/\bget rid of\b/) ||
                       normalized.match?(/\bfile cleanup\b/)

      mentions_downloads && cleanup_action
    end

    def extract_days(normalized)
      match = normalized.match(/older than\s+(\d+)\s+days?/)
      return match[1].to_i if match

      match = normalized.match(/\b(\d+)\s+days?\s+old\b/)
      return match[1].to_i if match

      match = normalized.match(/\b(\d+)\s+day\b/)
      return match[1].to_i if match

      nil
    end

    def deterministic_confidence(normalized)
      extract_days(normalized) ? 0.95 : 0.86
    end

    def deterministic_reason(normalized, days)
      if extract_days(normalized)
        "Matched Downloads cleanup phrasing and extracted age threshold of #{days} days."
      else
        "Matched Downloads cleanup phrasing. No age threshold was specified, so defaulted to #{days} days."
      end
    end

    def no_match(reason, source:)
      Result.new(
        ok: false,
        intent: nil,
        parameters: {},
        confidence: 0.0,
        reason: reason,
        source: source
      )
    end
  end
end
