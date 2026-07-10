#!/usr/bin/env ruby
# frozen_string_literal: true

errors = []

puts "Soul personality foundation phase 40 verification:"

required = {
  "docs/SOUL_PERSONALITY.md" => [
    "Soul Personality Foundation",
    "Soul should have one personality.",
    "Soul began after the Soul slash.",
    "machine familiar",
    "prefer truth over confidence",
    "Codex, cloud models, and other assistants are not masters.",
    "A careful externalized soul."
  ],
  "docs/maintenance/PHASE40_SOUL_PERSONALITY_FOUNDATION.md" => [
    "Phase 40",
    "one core personality",
    "documentation-only",
    "not permission to fake capabilities"
  ]
}

required.each do |path, needles|
  exists = File.exist?(path)
  puts "- #{path}: #{exists ? 'ok' : 'missing'}"
  errors << "#{path} missing" unless exists
  next unless exists

  content = File.read(path)
  needles.each do |needle|
    ok = content.include?(needle)
    puts "  - contains #{needle.inspect}: #{ok ? 'ok' : 'missing'}"
    errors << "#{path} missing #{needle.inspect}" unless ok
  end
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
