#!/usr/bin/env ruby
# frozen_string_literal: true

required_files = {
  "plan" => "docs/implementation/YOUTUBE_VIDEO_RESOLVER_PLAN.md",
  "skill docs" => "docs/skills/YOUTUBE_VIDEO_RESOLVE.md"
}

errors = []

required_files.each do |name, path|
  errors << "Missing #{name}: #{path}" unless File.exist?(path)
end

plan = File.exist?(required_files["plan"]) ? File.read(required_files["plan"]) : ""
skill_doc = File.exist?(required_files["skill docs"]) ? File.read(required_files["skill docs"]) : ""

required_plan_terms = [
  "youtube.video_resolve",
  "Official YouTube Data API",
  "YOUTUBE_DATA_API_KEY",
  "must not",
  "scrape YouTube",
  "download media",
  "bypass ads",
  "must not open the browser",
  "youtube.song_search --url",
  "scripts/verify-youtube-video-resolve.rb",
  "api_key_values_printed",
  "browser_launch_attempted",
  "Implementation should not proceed unless the user explicitly approves"
]

required_plan_terms.each do |term|
  errors << "Plan missing required term: #{term}" unless plan.include?(term)
end

required_skill_doc_terms = [
  "youtube.video_resolve",
  "YouTube Data API",
  "YOUTUBE_DATA_API_KEY",
  "planned",
  "scrape YouTube",
  "download media",
  "open a browser",
  "youtube.song_search --url"
]

required_skill_doc_terms.each do |term|
  errors << "Skill doc missing required term: #{term}" unless skill_doc.include?(term)
end

puts "YouTube video resolver plan verification:"
puts "- plan exists: #{File.exist?(required_files["plan"]) ? 'ok' : 'missing'}"
puts "- skill doc exists: #{File.exist?(required_files["skill docs"]) ? 'ok' : 'missing'}"
puts "- official API specified: #{plan.include?('Official YouTube Data API') ? 'ok' : 'missing'}"
puts "- API key boundary: #{plan.include?('YOUTUBE_DATA_API_KEY') && plan.include?('api_key_values_printed') ? 'ok' : 'missing'}"
puts "- unsafe behavior excluded: #{plan.include?('scrape YouTube') && plan.include?('download media') && plan.include?('bypass ads') ? 'ok' : 'missing'}"
puts "- browser launch separation: #{plan.include?('must not open the browser') && plan.include?('youtube.song_search --url') ? 'ok' : 'missing'}"
puts "- implementation approval gate: #{plan.include?('Implementation should not proceed unless the user explicitly approves') ? 'ok' : 'missing'}"

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
