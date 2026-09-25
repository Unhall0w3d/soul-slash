#!/usr/bin/env ruby
require_relative "../lib/soul_core/voice_presence_address_resolver"

resolver = SoulCore::VoicePresenceAddressResolver.new
{
  "Sol, what is the difference between memory and storage?" => "Soul, what is the difference between memory and storage?",
  "Sole, can you explain that?" => "Soul, can you explain that?",
  "Seoul, please tell me the weather." => "Soul, please tell me the weather.",
  "Seoul is the capital of South Korea." => "Seoul is the capital of South Korea.",
  "The word sole means one." => "The word sole means one.",
  "Sol, the sun god, appears here." => "Sol, the sun god, appears here.",
  "Seoul, South Korea is a city." => "Seoul, South Korea is a city."
}.each do |raw, expected|
  raise "incorrect address resolution for #{raw.inspect}" unless resolver.resolve(raw) == expected
end
bridge = File.read(File.expand_path("../scripts/soul-voice-presence-bridge", __dir__))
app = File.read(File.expand_path("../scripts/soul-voice-presence-app.py", __dir__))
raise "raw transcript is not preserved in UI" unless bridge.include?('"text" => raw_transcript') && app.include?('event.get("text"')
raise "resolved address not sent to chat" unless bridge.include?('"message" => transcript')
puts "PASS contextual Voice Presence address, raw display, geography preservation"
