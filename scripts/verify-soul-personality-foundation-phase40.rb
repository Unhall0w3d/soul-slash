#!/usr/bin/env ruby
# frozen_string_literal: true

errors = []

puts "Soul personality foundation phase 40 verification:"

required = {
  "docs/SOUL_PERSONALITY.md" => [
    "Soul Personality Foundation",
    "Soul should have one personality.",
    "Soul began after the Soul slash.",
    "awakened artificer",
    "poise, precision, restrained warmth, aesthetic judgment, and lucid curiosity",
    "prefer truth over confidence",
    "Codex, cloud models, and other assistants are not masters.",
    "A careful externalized soul with taste, curiosity, and real work to do."
  ],
  "docs/maintenance/PHASE40_SOUL_PERSONALITY_FOUNDATION.md" => [
    "Phase 40",
    "one core personality",
    "documentation-only",
    "not permission to fake capabilities"
  ]
}

runtime_profile = File.read("lib/soul_core/conversation_identity_profile.rb")
{
  "profile_version_8" => runtime_profile.include?('PROFILE_VERSION = 8'),
  "no_sleepy_freshness" => runtime_profile.include?("not childishness, helplessness, sleepiness"),
  "mention_not_invocation" => runtime_profile.include?("listing capabilities, invoking the skill catalog"),
  "avatar_voice_alignment" => runtime_profile.include?("poise, precision, restrained warmth, aesthetic judgment, and lucid curiosity")
}.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << name unless ok
end

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
