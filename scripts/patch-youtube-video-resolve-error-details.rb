#!/usr/bin/env ruby
# frozen_string_literal: true

path = "Soul/skills/youtube/video_resolve.rb"

unless File.exist?(path)
  warn "Missing #{path}"
  exit 1
end

text = File.read(path)

unless text.include?("def live_resolve(query)")
  warn "Could not find live_resolve in #{path}"
  exit 1
end

old_failure = <<~'RUBY'
        unless response.is_a?(Net::HTTPSuccess)
          return {
            "skill" => "youtube.video_resolve",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "query" => query,
            "provider" => "youtube_data_api",
            "http_status" => response.code.to_i,
            "duration_seconds" => duration,
            "recommendation" => api_failure_recommendation(response.code.to_i),
            "verification" => verification(
              network_used: true,
              complete: false,
              final_state: "failed",
              dry_run: false
            )
          }
        end
RUBY

new_failure = <<~'RUBY'
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
RUBY

unless text.include?(old_failure)
  if text.include?("sanitized_provider_error")
    puts "#{path} already appears to include provider error diagnostics."
    exit(system("ruby", "-c", path) ? 0 : 1)
  end

  warn "Could not find exact API failure block in #{path}"
  exit 1
end

text = text.sub(old_failure, new_failure)

old_recommendation = <<~'RUBY'
      def api_failure_recommendation(status)
        case status
        when 400
          "YouTube Data API rejected the request. Check query parameters and API key restrictions."
        when 401, 403
          "YouTube Data API authorization failed. Check #{API_KEY_ENV}, API enablement, quota, and key restrictions."
        when 429
          "YouTube Data API rate limit or quota was reached. Try later or review quota usage."
        else
          "YouTube Data API request failed. Review HTTP status and provider configuration."
        end
      end
RUBY

new_recommendation = <<~'RUBY'
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
RUBY

unless text.include?(old_recommendation)
  warn "Could not find api_failure_recommendation block in #{path}"
  exit 1
end

text = text.sub(old_recommendation, new_recommendation)

insert_before = <<~'RUBY'
      def normalize_query(value)
RUBY

diagnostic_helpers = <<~'RUBY'
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

RUBY

unless text.include?("def sanitized_provider_error")
  unless text.include?(insert_before)
    warn "Could not find insertion point for diagnostic helpers in #{path}"
    exit 1
  end

  text = text.sub(insert_before, diagnostic_helpers + insert_before)
end

File.write(path, text)

puts "Patched #{path}: added sanitized provider error diagnostics."
exit(system("ruby", "-c", path) ? 0 : 1)
