#!/usr/bin/env ruby
# frozen_string_literal: true

required_files = {
  "plan" => "docs/implementation/YOUTUBE_SONG_LAUNCHER_PLAN.md",
  "skill docs" => "docs/skills/YOUTUBE_SONG_SEARCH.md"
}

errors = []

required_files.each do |name, path|
  errors << "Missing #{name}: #{path}" unless File.exist?(path)
end

plan = File.exist?(required_files["plan"]) ? File.read(required_files["plan"]) : ""
skill_doc = File.exist?(required_files["skill docs"]) ? File.read(required_files["skill docs"]) : ""

required_plan_terms = [
  "youtube.song_search",
  "Linux only",
  "xdg-open",
  "No Windows support is planned",
  "No macOS support is planned",
  "must not",
  "download media",
  "scrape YouTube",
  "bypass ads",
  "SOUL_YOUTUBE_LAUNCHER",
  "scripts/verify-youtube-song-search.rb",
  "network_used",
  "browser_launch_attempted",
  "Implementation should not proceed unless the user explicitly approves"
]

required_plan_terms.each do |term|
  errors << "Plan missing required term: #{term}" unless plan.include?(term)
end

required_skill_doc_terms = [
  "youtube.song_search",
  "Linux only",
  "xdg-open",
  "planned",
  "download media",
  "scrape YouTube",
  "bypass ads"
]

required_skill_doc_terms.each do |term|
  errors << "Skill doc missing required term: #{term}" unless skill_doc.include?(term)
end

puts "YouTube song launcher plan verification:"
puts "- plan exists: #{File.exist?(required_files["plan"]) ? 'ok' : 'missing'}"
puts "- skill doc exists: #{File.exist?(required_files["skill docs"]) ? 'ok' : 'missing'}"
puts "- Linux-only boundary: #{plan.include?('Linux only') && plan.include?('No Windows support is planned') ? 'ok' : 'missing'}"
puts "- xdg-open specified: #{plan.include?('xdg-open') ? 'ok' : 'missing'}"
puts "- unsafe behavior excluded: #{plan.include?('download media') && plan.include?('scrape YouTube') && plan.include?('bypass ads') ? 'ok' : 'missing'}"
puts "- implementation approval gate: #{plan.include?('Implementation should not proceed unless the user explicitly approves') ? 'ok' : 'missing'}"

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
