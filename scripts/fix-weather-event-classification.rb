#!/usr/bin/env ruby
# frozen_string_literal: true

path = "Soul/skills/weather/report.rb"

unless File.exist?(path)
  warn "Missing #{path}"
  exit 1
end

content = File.read(path)

old = %q{elsif code.to_i.between?(71, 86)
      events << "#{day}: snow or snow showers possible."}

new = %q{elsif code.to_i.between?(71, 77) || code.to_i.between?(85, 86)
      events << "#{day}: snow or snow showers possible."}

if content.include?(new)
  puts "Weather event classification is already patched."
  exit 0
end

unless content.include?(old)
  warn "Could not find expected weather-code classification block."
  warn "No files changed."
  warn
  warn "Search manually with:"
  warn "  grep -n \"snow or snow showers\" Soul/skills/weather/report.rb"
  exit 1
end

updated = content.sub(old, new)
File.write(path, updated)

puts "Patched #{path}"
puts "Snow classification now covers Open-Meteo snow codes 71..77 and 85..86."
puts "Rain shower codes 80..82 now fall through to the precipitation/rain branch."
