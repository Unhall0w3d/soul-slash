#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
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

puts "youtube.video_resolve verification:"

help_stdout, _help_stderr, help_status = Open3.capture3("ruby", skill, "--help")
help_ok = help_status.success? && help_stdout.include?("youtube.video_resolve") && help_stdout.include?("YOUTUBE_DATA_API_KEY")
puts "- help output: #{help_ok ? 'ok' : 'missing'}"
errors << "help output failed" unless help_ok

missing_query, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "")
missing_query_ok =
  !status.success? &&
  missing_query &&
  missing_query["outcome"] == "blocked_for_input" &&
  missing_query.dig("verification", "network_used") == false
puts "- missing query blocked: #{missing_query_ok ? 'ok' : 'missing'}"
errors << "missing query did not block" unless missing_query_ok

missing_key_env = ENV.to_h.reject { |key, _value| key == "YOUTUBE_DATA_API_KEY" }
missing_key_env["SOUL_SKIP_ENV_LOAD"] = "1"
missing_key, stdout, _stderr, status = run_json(missing_key_env, "ruby", skill, "--query", "Bohemian Rhapsody")
missing_key_ok =
  !status.success? &&
  missing_key &&
  missing_key["outcome"] == "blocked_for_input" &&
  missing_key["recommendation"].include?("YOUTUBE_DATA_API_KEY") &&
  missing_key.dig("verification", "api_key_values_printed") == false &&
  !stdout.include?("AIza")
puts "- missing API key blocked: #{missing_key_ok ? 'ok' : 'missing'}"
errors << "missing API key did not block safely" unless missing_key_ok

dry, stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "Bohemian Rhapsody", "--dry-run")
dry_ok =
  status.success? &&
  dry &&
  dry["outcome"] == "complete" &&
  dry["provider"] == "dry_run_fixture" &&
  dry.dig("candidate", "watch_url") == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ" &&
  dry.dig("verification", "network_used") == false &&
  dry.dig("verification", "browser_launch_attempted") == false &&
  dry.dig("verification", "download_attempted") == false &&
  dry.dig("verification", "scraping_attempted") == false &&
  dry.dig("verification", "api_key_values_printed") == false &&
  !stdout.include?("YOUTUBE_DATA_API_KEY=")
puts "- dry-run candidate: #{dry_ok ? 'ok' : 'missing'}"
errors << "dry-run candidate failed" unless dry_ok

maxed, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "Bohemian Rhapsody", "--max-results", "99", "--dry-run")
maxed_ok = status.success? && maxed && maxed["outcome"] == "complete"
puts "- max-results dry-run tolerated: #{maxed_ok ? 'ok' : 'missing'}"
errors << "max-results dry-run failed" unless maxed_ok

docs = File.exist?("docs/skills/YOUTUBE_VIDEO_RESOLVE.md") ? File.read("docs/skills/YOUTUBE_VIDEO_RESOLVE.md") : ""
docs_ok = docs.include?("youtube.video_resolve") && docs.include?("YOUTUBE_DATA_API_KEY") && docs.include?("does not open the browser")
puts "- docs updated: #{docs_ok ? 'ok' : 'missing'}"
errors << "docs missing implemented resolver details" unless docs_ok

registry_text = File.exist?("Soul/skills/registry.yaml") ? File.read("Soul/skills/registry.yaml") : ""
registry_ok = registry_text.include?("youtube.video_resolve") && registry_text.include?("risk")
puts "- registry entry present: #{registry_ok ? 'ok' : 'missing'}"
errors << "registry entry missing youtube.video_resolve or risk" unless registry_ok

if registry_ok
  bin_result, _stdout, _stderr, status = run_json({}, "ruby", "bin/soul", "skill", "youtube.video_resolve", "--", "--query", "Bohemian Rhapsody", "--dry-run")
  bin_ok =
    status.success? &&
    bin_result &&
    bin_result["skill"] == "youtube.video_resolve" &&
    bin_result["outcome"] == "complete" &&
    bin_result.dig("verification", "network_used") == false
  puts "- bin/soul skill invocation: #{bin_ok ? 'ok' : 'missing'}"
  errors << "bin/soul dry-run invocation failed" unless bin_ok
else
  puts "- bin/soul skill invocation: skipped"
end

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
