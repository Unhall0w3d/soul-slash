#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "tmpdir"
require "shellwords"

skill = "Soul/skills/youtube/song_search.rb"
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

puts "youtube.song_search verification:"

help_stdout, help_stderr, help_status = Open3.capture3("ruby", skill, "--help")
help_ok = help_status.success? && help_stdout.include?("youtube.song_search")
puts "- help output: #{help_ok ? 'ok' : 'missing'}"
errors << "help output failed" unless help_ok

empty, _stdout, stderr, status = run_json({}, "ruby", skill, "--query", "")
empty_ok = !status.success? && empty && empty["outcome"] == "blocked_for_input" && empty.dig("verification", "browser_launch_attempted") == false
puts "- empty query blocked: #{empty_ok ? 'ok' : 'missing'}"
errors << "empty query did not block correctly" unless empty_ok

spacey, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "   ")
spacey_ok = !status.success? && spacey && spacey["outcome"] == "blocked_for_input"
puts "- whitespace query blocked: #{spacey_ok ? 'ok' : 'missing'}"
errors << "whitespace query did not block correctly" unless spacey_ok

plan, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "Bohemian   Rhapsody", "--plan-only")
plan_ok =
  status.success? &&
  plan &&
  plan["outcome"] == "awaiting_confirmation" &&
  plan["query"] == "Bohemian Rhapsody" &&
  plan["url"] == "https://www.youtube.com/results?search_query=Bohemian+Rhapsody" &&
  plan.dig("verification", "network_used") == false &&
  plan.dig("verification", "browser_launch_attempted") == false &&
  plan.dig("verification", "download_attempted") == false &&
  plan.dig("verification", "scraping_attempted") == false
puts "- plan-only URL construction: #{plan_ok ? 'ok' : 'missing'}"
errors << "plan-only behavior failed" unless plan_ok

special, _stdout, _stderr, status = run_json({}, "ruby", skill, "--song", "AC/DC Thunderstruck live")
special_ok =
  status.success? &&
  special &&
  special["url"] == "https://www.youtube.com/results?search_query=AC%2FDC+Thunderstruck+live"
puts "- special character encoding: #{special_ok ? 'ok' : 'missing'}"
errors << "special character encoding failed" unless special_ok

dry, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "Dry Run Song", "--confirm", "--dry-run")
dry_ok =
  status.success? &&
  dry &&
  dry["outcome"] == "complete" &&
  dry.dig("verification", "dry_run") == true &&
  dry.dig("verification", "browser_launch_attempted") == false
puts "- dry-run confirm skips launcher: #{dry_ok ? 'ok' : 'missing'}"
errors << "dry-run confirmed behavior failed" unless dry_ok

fake_dir = Dir.mktmpdir("soul-youtube-launcher-")
fake_launcher = File.join(fake_dir, "fake-launcher")
capture_file = File.join(fake_dir, "launcher-args.txt")
File.write(fake_launcher, "#!/usr/bin/env ruby\nFile.write(ENV.fetch('SOUL_YOUTUBE_CAPTURE'), ARGV.join(\"\\n\"))\nexit 0\n")
FileUtils.chmod("+x", fake_launcher)

env = {
  "SOUL_YOUTUBE_LAUNCHER" => fake_launcher,
  "SOUL_YOUTUBE_CAPTURE" => capture_file
}
confirmed, _stdout, _stderr, status = run_json(env, "ruby", skill, "--query", "Fake Browser Song", "--confirm")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
confirmed_ok =
  status.success? &&
  confirmed &&
  confirmed["outcome"] == "complete" &&
  confirmed.dig("verification", "browser_launch_attempted") == true &&
  captured == "https://www.youtube.com/results?search_query=Fake+Browser+Song"
puts "- fake launcher confirm: #{confirmed_ok ? 'ok' : 'missing'}"
errors << "fake launcher confirmed behavior failed" unless confirmed_ok

FileUtils.rm_rf(fake_dir)

registry_text = File.exist?("Soul/skills/registry.yaml") ? File.read("Soul/skills/registry.yaml") : ""
registry_ok = registry_text.include?("youtube.song_search") && registry_text.include?("risk")
puts "- registry entry present: #{registry_ok ? 'ok' : 'missing'}"
errors << "registry entry missing youtube.song_search or risk" unless registry_ok

if registry_ok
  bin_plan, _stdout, _stderr, status = run_json({}, "ruby", "bin/soul", "skill", "youtube.song_search", "--", "--query", "Registry Song", "--plan-only")
  bin_ok =
    status.success? &&
    bin_plan &&
    bin_plan["skill"] == "youtube.song_search" &&
    bin_plan["outcome"] == "awaiting_confirmation"
  puts "- bin/soul skill invocation: #{bin_ok ? 'ok' : 'missing'}"
  errors << "bin/soul skill invocation failed" unless bin_ok
else
  puts "- bin/soul skill invocation: skipped"
end

Dir.glob("Soul/logs/tasks/*-youtube.song_search.json").each do |path|
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
