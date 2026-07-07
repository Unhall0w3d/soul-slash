#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "tmpdir"

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

puts "youtube.song_search direct URL verification:"

help_stdout, _help_stderr, help_status = Open3.capture3("ruby", skill, "--help")
help_ok = help_status.success? && help_stdout.include?("--url URL") && help_stdout.include?("direct YouTube watch URL")
puts "- help documents URL mode: #{help_ok ? 'ok' : 'missing'}"
errors << "help output does not document URL mode" unless help_ok

watch, _stdout, _stderr, status = run_json({}, "ruby", skill, "--url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
watch_ok =
  status.success? &&
  watch &&
  watch["outcome"] == "awaiting_confirmation" &&
  watch["input_type"] == "youtube_url" &&
  watch["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ" &&
  watch.dig("verification", "direct_video_url_supported") == true &&
  watch.dig("verification", "search_query_resolves_video") == false
puts "- watch URL plan: #{watch_ok ? 'ok' : 'missing'}"
errors << "watch URL plan failed" unless watch_ok

share, _stdout, _stderr, status = run_json({}, "ruby", skill, "--url", "https://youtu.be/dQw4w9WgXcQ?si=abc123")
share_ok =
  status.success? &&
  share &&
  share["outcome"] == "awaiting_confirmation" &&
  share["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
puts "- youtu.be normalization: #{share_ok ? 'ok' : 'missing'}"
errors << "youtu.be normalization failed" unless share_ok

shorts, _stdout, _stderr, status = run_json({}, "ruby", skill, "--url", "https://youtube.com/shorts/dQw4w9WgXcQ")
shorts_ok =
  status.success? &&
  shorts &&
  shorts["outcome"] == "awaiting_confirmation" &&
  shorts["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
puts "- shorts URL normalization: #{shorts_ok ? 'ok' : 'missing'}"
errors << "shorts URL normalization failed" unless shorts_ok

bad_host, _stdout, _stderr, status = run_json({}, "ruby", skill, "--url", "https://example.com/watch?v=dQw4w9WgXcQ")
bad_host_ok =
  !status.success? &&
  bad_host &&
  bad_host["outcome"] == "blocked_for_input" &&
  bad_host["input_type"] == "youtube_url"
puts "- non-YouTube URL blocked: #{bad_host_ok ? 'ok' : 'missing'}"
errors << "non-YouTube URL did not block" unless bad_host_ok

bad_path, _stdout, _stderr, status = run_json({}, "ruby", skill, "--url", "https://www.youtube.com/results?search_query=test")
bad_path_ok =
  !status.success? &&
  bad_path &&
  bad_path["outcome"] == "blocked_for_input" &&
  bad_path["recommendation"].include?("Unsupported YouTube URL path")
puts "- YouTube search URL rejected as direct URL: #{bad_path_ok ? 'ok' : 'missing'}"
errors << "YouTube search URL was not rejected in URL mode" unless bad_path_ok

query, _stdout, _stderr, status = run_json({}, "ruby", skill, "--query", "Bohemian Rhapsody")
query_ok =
  status.success? &&
  query &&
  query["input_type"] == "search_query" &&
  query["url"] == "https://www.youtube.com/results?search_query=Bohemian+Rhapsody" &&
  query.dig("verification", "search_query_resolves_video") == false
puts "- search query mode preserved: #{query_ok ? 'ok' : 'missing'}"
errors << "search query mode changed unexpectedly" unless query_ok

fake_dir = Dir.mktmpdir("soul-youtube-url-launcher-")
fake_launcher = File.join(fake_dir, "fake-launcher")
capture_file = File.join(fake_dir, "launcher-args.txt")
File.write(fake_launcher, "#!/usr/bin/env ruby\nFile.write(ENV.fetch('SOUL_YOUTUBE_CAPTURE'), ARGV.join(\"\\n\"))\nexit 0\n")
FileUtils.chmod("+x", fake_launcher)

env = {
  "SOUL_YOUTUBE_LAUNCHER" => fake_launcher,
  "SOUL_YOUTUBE_CAPTURE" => capture_file
}
confirmed, _stdout, _stderr, status = run_json(env, "ruby", skill, "--url", "https://youtu.be/dQw4w9WgXcQ", "--confirm")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
confirmed_ok =
  status.success? &&
  confirmed &&
  confirmed["outcome"] == "complete" &&
  confirmed["input_type"] == "youtube_url" &&
  confirmed["url"] == "https://www.youtube.com/watch?v=dQw4w9WgXcQ" &&
  confirmed.dig("verification", "browser_launch_attempted") == true &&
  captured == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
puts "- fake launcher direct watch URL: #{confirmed_ok ? 'ok' : 'missing'}"
errors << "fake launcher did not receive normalized watch URL" unless confirmed_ok

FileUtils.rm_rf(fake_dir)

docs = File.exist?("docs/skills/YOUTUBE_SONG_SEARCH.md") ? File.read("docs/skills/YOUTUBE_SONG_SEARCH.md") : ""
docs_ok = docs.include?("--url") && docs.include?("direct YouTube watch URL") && docs.include?("does not resolve song-name searches")
puts "- docs updated: #{docs_ok ? 'ok' : 'missing'}"
errors << "docs missing direct URL explanation" unless docs_ok

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
