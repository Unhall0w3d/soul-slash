#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"

skill = "Soul/skills/youtube/video_resolve.rb"
errors = []

unless File.exist?(skill)
  warn "Missing #{skill}"
  exit 1
end

def run_json(env, *cmd)
  stdout, stderr, status = Open3.capture3(env, *cmd)
  parsed = nil

  begin
    parsed = JSON.parse(stdout)
  rescue JSON::ParserError
    return [nil, stdout, stderr, status]
  end

  [parsed, stdout, stderr, status]
end

puts "youtube.video_resolve error diagnostics verification:"

source = File.read(skill)
source_checks = {
  "sanitized_provider_error helper" => source.include?("def sanitized_provider_error"),
  "provider_error output" => source.include?('"provider_error" => provider_error'),
  "secret redaction helper" => source.include?("def redact_secret"),
  "API failure recommendation accepts details" => source.include?("def api_failure_recommendation(status, provider_error = {})")
}

source_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

missing_key_env = ENV.to_h.reject { |key, _value| key == "YOUTUBE_DATA_API_KEY" }
missing_key_env["SOUL_SKIP_ENV_LOAD"] = "1"
missing_key, stdout, _stderr, status = run_json(missing_key_env, "ruby", skill, "--query", "Bohemian Rhapsody")
missing_key_ok =
  !status.success? &&
  missing_key &&
  missing_key["outcome"] == "blocked_for_input" &&
  missing_key.dig("verification", "api_key_values_printed") == false &&
  !stdout.match?(/AIza[0-9A-Za-z_\-]{20,}/)
puts "- missing API key still safe: #{missing_key_ok ? 'ok' : 'missing'}"
errors << "missing API key safety check failed" unless missing_key_ok

dry, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "Bohemian Rhapsody", "--dry-run")
dry_ok =
  status.success? &&
  dry &&
  dry["outcome"] == "complete" &&
  dry.dig("verification", "api_key_values_printed") == false
puts "- dry-run still works: #{dry_ok ? 'ok' : 'missing'}"
errors << "dry-run failed after diagnostic patch" unless dry_ok

docs = File.exist?("docs/skills/YOUTUBE_VIDEO_RESOLVE.md") ? File.read("docs/skills/YOUTUBE_VIDEO_RESOLVE.md") : ""
docs_ok =
  docs.include?("provider_error") &&
  docs.include?("sanitized") &&
  docs.include?("API key")
puts "- docs mention sanitized provider errors: #{docs_ok ? 'ok' : 'missing'}"
errors << "docs missing sanitized provider error details" unless docs_ok

Dir.glob("Soul/logs/tasks/*-youtube.video_resolve.json").each do |path|
  File.delete(path)
rescue StandardError
  nil
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
