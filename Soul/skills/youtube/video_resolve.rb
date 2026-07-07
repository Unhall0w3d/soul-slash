#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require "uri"
require "net/http"

ROOT = File.expand_path("../../..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

begin
  require "soul_core/env_loader"
  if defined?(SoulCore::EnvLoader) && ENV["SOUL_SKIP_ENV_LOAD"] != "1"
    SoulCore::EnvLoader.load
  end
rescue LoadError
  # .env loading is optional. Shell environment still works.
end

module SoulSkills
  module YouTube
    class VideoResolve
      MAX_QUERY_LENGTH = 240
      DEFAULT_MAX_RESULTS = 1
      MAX_ALLOWED_RESULTS = 5
      API_ENDPOINT = "https://www.googleapis.com/youtube/v3/search"
      API_KEY_ENV = "YOUTUBE_DATA_API_KEY"

      DRY_RUN_CANDIDATE = {
        "rank" => 1,
        "title" => "Queen – Bohemian Rhapsody (Official Video Remastered)",
        "channel_title" => "Queen Official",
        "video_id" => "fJ9rUzIMcZQ",
        "watch_url" => "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
      }.freeze

      def initialize(argv, env = ENV)
        @argv = argv
        @env = env
      end

      def run
        if @argv.include?("--help") || @argv.include?("-h")
          puts help_text
          return 0
        end

        query = normalize_query(option_value("--query") || option_value("--song") || positional_query)

        result =
          if query.empty?
            blocked_for_input("Missing song/search query. Provide --query \"Song Name\".")
          elsif query.length > MAX_QUERY_LENGTH
            blocked_for_input("Query is too long. Maximum supported length is #{MAX_QUERY_LENGTH} characters.", query: query)
          elsif dry_run?
            dry_run_result(query)
          elsif api_key.empty?
            blocked_for_input("#{API_KEY_ENV} is required for live resolution. Use --dry-run for verifier fixtures.", query: query)
          else
            live_resolve(query)
          end

        log_path = write_log(result)
        result["task_log"] = log_path if log_path

        puts JSON.pretty_generate(result)
        terminal_success?(result) ? 0 : 1
      rescue StandardError => e
        result = {
          "skill" => "youtube.video_resolve",
          "generated_at" => Time.now.iso8601,
          "status" => "error",
          "outcome" => "failed",
          "error" => {
            "class" => e.class.name,
            "message" => e.message
          },
          "verification" => verification(
            network_used: false,
            complete: false,
            final_state: "failed",
            dry_run: dry_run?
          )
        }

        log_path = write_log(result)
        result["task_log"] = log_path if log_path

        puts JSON.pretty_generate(result)
        1
      end

      private

      def live_resolve(query)
        max_results = requested_max_results
        uri = build_api_uri(query, max_results)

        started = Time.now
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
          request = Net::HTTP::Get.new(uri)
          http.request(request)
        end
        duration = (Time.now - started).round(3)

unless response.is_a?(Net::HTTPSuccess)
  provider_error = sanitized_provider_error(response.body)

  return {
    "skill" => "youtube.video_resolve",
    "generated_at" => Time.now.iso8601,
    "status" => "error",
    "outcome" => "failed",
    "query" => query,
    "provider" => "youtube_data_api",
    "http_status" => response.code.to_i,
    "duration_seconds" => duration,
    "provider_error" => provider_error,
    "recommendation" => api_failure_recommendation(response.code.to_i, provider_error),
    "verification" => verification(
      network_used: true,
      complete: false,
      final_state: "failed",
      dry_run: false
    )
  }
end

        parsed = JSON.parse(response.body)
        candidates = parse_candidates(parsed)

        if candidates.empty?
          {
            "skill" => "youtube.video_resolve",
            "generated_at" => Time.now.iso8601,
            "status" => "warning",
            "outcome" => "no_match",
            "query" => query,
            "provider" => "youtube_data_api",
            "http_status" => response.code.to_i,
            "duration_seconds" => duration,
            "candidates" => [],
            "recommendation" => "No video candidate was returned. Try a more specific query or use youtube.song_search search mode.",
            "verification" => verification(
              network_used: true,
              complete: false,
              final_state: "no_match",
              dry_run: false
            )
          }
        else
          complete_result(
            query: query,
            provider: "youtube_data_api",
            candidates: candidates,
            http_status: response.code.to_i,
            duration_seconds: duration,
            dry_run: false,
            recommendation: "Review the resolved YouTube video candidate before opening it."
          )
        end
      end

      def dry_run_result(query)
        complete_result(
          query: query,
          provider: "dry_run_fixture",
          candidates: [DRY_RUN_CANDIDATE],
          http_status: nil,
          duration_seconds: 0,
          dry_run: true,
          recommendation: "Dry-run resolver fixture returned a candidate. No live API call was made."
        )
      end

      def complete_result(query:, provider:, candidates:, http_status:, duration_seconds:, dry_run:, recommendation:)
        {
          "skill" => "youtube.video_resolve",
          "generated_at" => Time.now.iso8601,
          "status" => "ok",
          "outcome" => "complete",
          "query" => query,
          "provider" => provider,
          "http_status" => http_status,
          "duration_seconds" => duration_seconds,
          "candidate" => candidates.first,
          "candidates" => candidates,
          "recommendation" => recommendation,
          "verification" => verification(
            network_used: !dry_run,
            complete: true,
            final_state: "complete",
            dry_run: dry_run
          )
        }
      end

      def blocked_for_input(message, query: nil)
        out = {
          "skill" => "youtube.video_resolve",
          "generated_at" => Time.now.iso8601,
          "status" => "warning",
          "outcome" => "blocked_for_input",
          "recommendation" => message,
          "verification" => verification(
            network_used: false,
            complete: false,
            final_state: "blocked_for_input",
            dry_run: dry_run?
          )
        }
        out["query"] = query if query
        out
      end

      def build_api_uri(query, max_results)
        uri = URI(API_ENDPOINT)
        uri.query = URI.encode_www_form(
          "part" => "snippet",
          "type" => "video",
          "q" => query,
          "maxResults" => max_results,
          "safeSearch" => "none",
          "videoEmbeddable" => "any",
          "key" => api_key
        )
        uri
      end

      def parse_candidates(parsed)
        items = parsed.fetch("items", [])
        items.each_with_index.filter_map do |item, index|
          video_id = item.dig("id", "videoId").to_s.strip
          next unless valid_video_id?(video_id)

          snippet = item.fetch("snippet", {})
          {
            "rank" => index + 1,
            "title" => snippet.fetch("title", "").to_s,
            "channel_title" => snippet.fetch("channelTitle", "").to_s,
            "video_id" => video_id,
            "watch_url" => "https://www.youtube.com/watch?v=#{video_id}"
          }
        end
      end

      def valid_video_id?(video_id)
        video_id.match?(/\A[A-Za-z0-9_-]{6,20}\z/)
      end

      def requested_max_results
        raw = option_value("--max-results")
        return DEFAULT_MAX_RESULTS if raw.to_s.strip.empty?

        value = raw.to_i
        return DEFAULT_MAX_RESULTS if value < 1

        [value, MAX_ALLOWED_RESULTS].min
      end
def api_failure_recommendation(status, provider_error = {})
  detail = provider_error["message"].to_s.strip
  suffix = detail.empty? ? "" : " Provider message: #{detail}"

  case status
  when 400
    "YouTube Data API rejected the request. Check query parameters and API key restrictions.#{suffix}"
  when 401, 403
    "YouTube Data API authorization failed. Check #{API_KEY_ENV}, API enablement, quota, and key restrictions.#{suffix}"
  when 429
    "YouTube Data API rate limit or quota was reached. Try later or review quota usage.#{suffix}"
  else
    "YouTube Data API request failed. Review HTTP status and provider configuration.#{suffix}"
  end
end

def sanitized_provider_error(body)
  parsed = JSON.parse(body.to_s)
  error = parsed.fetch("error", {})
  first = Array(error["errors"]).find { |item| item.is_a?(Hash) } || {}

  {
    "message" => redact_secret(error["message"].to_s),
    "reason" => redact_secret(first["reason"].to_s),
    "domain" => redact_secret(first["domain"].to_s),
    "location" => redact_secret(first["location"].to_s),
    "location_type" => redact_secret(first["locationType"].to_s)
  }.reject { |_key, value| value.to_s.empty? }
rescue JSON::ParserError
  {
    "message" => "Provider returned a non-JSON error response."
  }
end

def redact_secret(value)
  text = value.to_s
  key = api_key
  text = text.gsub(key, "[REDACTED_API_KEY]") unless key.empty?
  text.gsub(/AIza[0-9A-Za-z_\-]{20,}/, "[REDACTED_API_KEY]")
end

      def normalize_query(value)
        value.to_s.strip.gsub(/\s+/, " ")
      end

      def option_value(flag)
        idx = @argv.index(flag)
        return nil unless idx

        @argv[idx + 1]
      end

      def positional_query
        remaining = []
        skip = false

        @argv.each_with_index do |arg, idx|
          if skip
            skip = false
            next
          end

          if arg.start_with?("--")
            skip = %w[--query --song --max-results].include?(arg) && @argv[idx + 1]
            next
          end

          remaining << arg
        end

        remaining.join(" ")
      end

      def api_key
        @env[API_KEY_ENV].to_s.strip
      end

      def dry_run?
        @argv.include?("--dry-run")
      end

      def terminal_success?(result)
        result["status"] == "ok"
      end

      def verification(network_used:, complete:, final_state:, dry_run:)
        {
          "read_only" => true,
          "network_used" => network_used,
          "browser_launch_attempted" => false,
          "download_attempted" => false,
          "scraping_attempted" => false,
          "ad_bypass_attempted" => false,
          "persistent_process_started" => false,
          "secrets_printed" => false,
          "api_key_values_printed" => false,
          "api_key_logged" => false,
          "opens_browser" => false,
          "dry_run" => dry_run,
          "complete" => complete,
          "final_state" => final_state
        }
      end

      def write_log(result)
        dir = File.join(ROOT, "Soul", "logs", "tasks")
        FileUtils.mkdir_p(dir)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        path = File.join(dir, "#{stamp}-youtube.video_resolve.json")

        # Result intentionally excludes request URL so API key query parameter cannot leak.
        File.write(path, JSON.pretty_generate(result) + "\n")
        path.sub("#{ROOT}/", "")
      rescue StandardError
        nil
      end

      def help_text
        <<~TEXT
          youtube.video_resolve

          Resolves a song/search query to a YouTube video candidate.

          Usage:
            ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody" --dry-run
            ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody"
            ruby Soul/skills/youtube/video_resolve.rb --song "Miles Davis So What" --max-results 3

          Options:
            --query TEXT       Song/search query.
            --song TEXT        Alias for --query.
            --max-results N    Number of API candidates to request. Clamped to 1..5. Default: 1.
            --dry-run          Return a static fixture candidate without a live API call.
            --help             Show this help.

          Live mode requires:
            #{API_KEY_ENV}

          Boundary:
            - Uses the official YouTube Data API v3 in live mode.
            - Does not scrape YouTube.
            - Does not download media.
            - Does not bypass ads or access controls.
            - Does not open the browser.
            - Does not print or log API key values.
        TEXT
      end
    end
  end
end

exit SoulSkills::YouTube::VideoResolve.new(ARGV).run
