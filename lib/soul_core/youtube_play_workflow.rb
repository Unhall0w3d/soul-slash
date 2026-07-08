# frozen_string_literal: true

# Compatibility glue for youtube.play intent routing.
#
# Workflow execution and response handling live in:
#
#   SoulCore::Workflows::YouTubePlayHandler
#
# This file intentionally only teaches IntentRouter how to recognize a YouTube
# play/search/open request and extract the song/search query. It must not own
# browser launch, resolver calls, workflow state writes, session response
# handling, or response rendering.

module SoulCore
  module YouTubePlayIntentPatch
    def route(text)
      input = text.to_s.strip
      normalized = input.downcase

      if youtube_play_request?(normalized)
        query = extract_youtube_query(input)
        result_class = self.class.const_get(:Result)

        return result_class.new(
          ok: true,
          intent: "youtube.play",
          parameters: {
            "query" => query,
            "query_source" => query.empty? ? "missing" : "extracted"
          },
          confidence: query.empty? ? 0.72 : 0.91,
          reason: query.empty? ? "Matched YouTube playback phrasing, but no song/query was found." : "Matched YouTube playback phrasing and extracted a song/search query.",
          source: "deterministic"
        )
      end

      super
    end

    private

    def youtube_play_request?(normalized)
      mentions_youtube = normalized.match?(/\byoutube\b/) || normalized.match?(/\byt\b/)
      action =
        normalized.match?(/\bplay\b/) ||
        normalized.match?(/\bopen\b/) ||
        normalized.match?(/\bsearch\b/) ||
        normalized.match?(/\bfind\b/)

      mentions_youtube && action
    end

    def extract_youtube_query(input)
      value = input.to_s.strip
      value = value.sub(/[?.!]\z/, "").strip

      patterns = [
        /\A(?:please\s+)?(?:can you\s+)?(?:search|find)\s+(?:youtube|yt)\s+(?:for\s+)?(.+)\z/i,
        /\A(?:please\s+)?(?:can you\s+)?(?:search|find)\s+(.+?)\s+(?:on|in)\s+(?:youtube|yt)\z/i,
        /\A(?:please\s+)?(?:can you\s+)?(?:play|open)\s+(.+?)\s+(?:on|in)\s+(?:youtube|yt)\z/i,
        /\A(?:please\s+)?(?:can you\s+)?(?:play|open)\s+(?:youtube|yt)\s+(.+)\z/i
      ]

      patterns.each do |pattern|
        match = value.match(pattern)
        next unless match

        return clean_youtube_query(match[1])
      end

      cleaned = value.dup
      cleaned.gsub!(/\A(?:please\s+)?(?:can you\s+)?/, "")
      cleaned.gsub!(/\b(?:play|open|search|find)\b/i, "")
      cleaned.gsub!(/\b(?:on|in)\s+(?:youtube|yt)\b/i, "")
      cleaned.gsub!(/\b(?:youtube|yt)\b/i, "")
      clean_youtube_query(cleaned)
    end

    def clean_youtube_query(value)
      value.to_s.strip.gsub(/\s+/, " ").sub(/\A["']/, "").sub(/["']\z/, "").strip
    end
  end
end

SoulCore::IntentRouter.prepend(SoulCore::YouTubePlayIntentPatch)
