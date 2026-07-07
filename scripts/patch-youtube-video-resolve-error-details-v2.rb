#!/usr/bin/env ruby
# frozen_string_literal: true

path = "Soul/skills/youtube/video_resolve.rb"

unless File.exist?(path)
  warn "Missing #{path}"
  exit 1
end

text = File.read(path)

if text.include?("def sanitized_provider_error") && text.include?('"provider_error" => provider_error')
  puts "#{path} already appears to include provider error diagnostics."
  exit(system("ruby", "-c", path) ? 0 : 1)
end

def replace_unless_httpsuccess_block(text)
  marker = "        unless response.is_a?(Net::HTTPSuccess)\n"
  start_index = text.index(marker)
  raise "Could not find Net::HTTPSuccess failure block" unless start_index

  index = start_index + marker.length
  depth = 1

  text[index..].each_line do |line|
    stripped = line.strip

    if stripped.start_with?("if ", "unless ", "case ", "begin", "while ", "until ", "for ", "def ", "class ", "module ")
      depth += 1 unless stripped.end_with?(" end")
    end

    depth -= 1 if stripped == "end"

    index += line.length
    break if depth.zero?
  end

  raise "Could not find end of Net::HTTPSuccess failure block" unless depth.zero?

  replacement = <<~'RUBY'
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

  text[0...start_index] + replacement + text[index..]
end

def replace_api_failure_recommendation(text)
  marker = /^(\s*)def api_failure_recommendation\b.*$/
  match = text.match(marker)
  raise "Could not find api_failure_recommendation method" unless match

  start_index = match.begin(0)
  index = match.end(0)
  depth = 1

  text[index..].each_line do |line|
    stripped = line.strip

    if stripped.start_with?("def ", "if ", "unless ", "case ", "begin", "while ", "until ", "for ", "class ", "module ")
      depth += 1 unless stripped.end_with?(" end")
    end

    depth -= 1 if stripped == "end"

    index += line.length
    break if depth.zero?
  end

  raise "Could not find end of api_failure_recommendation method" unless depth.zero?

  replacement = <<~'RUBY'
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

  text[0...start_index] + replacement + text[index..]
end

def insert_helpers(text)
  return text if text.include?("def sanitized_provider_error")

  insertion_point = text.index("      def normalize_query(value)\n")
  raise "Could not find normalize_query insertion point" unless insertion_point

  helpers = <<~'RUBY'
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

  text[0...insertion_point] + helpers + text[insertion_point..]
end

begin
  text = replace_unless_httpsuccess_block(text)
  text = replace_api_failure_recommendation(text)
  text = insert_helpers(text)
rescue StandardError => e
  warn e.message
  exit 1
end

File.write(path, text)

puts "Patched #{path}: added sanitized provider error diagnostics."
exit(system("ruby", "-c", path) ? 0 : 1)
