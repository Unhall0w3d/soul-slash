#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/voice_presence_launch_service"

ROOT = File.expand_path("..", __dir__)

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

assets = %w[
  cue-submit cue-wake cue-complete cue-attention
  f3-chat-ready m3-chat-ready f3-music-ready m3-music-ready
  f3-visual-ready m3-visual-ready f3-lyrics-ready m3-lyrics-ready
  f3-attention m3-attention
  f3-security-alert m3-security-alert
]
assets.each do |name|
  path = File.join(ROOT, "assets", "notifications", "#{name}.wav")
  check("#{name} is a bounded WAV asset", File.file?(path) && File.binread(path, 4) == "RIFF" && File.size(path).between?(1_000, 2_000_000))
end

javascript = File.read(File.join(ROOT, "assets", "dashboard", "dashboard.js"))
html = File.read(File.join(ROOT, "assets", "dashboard", "index.html"))
http = File.read(File.join(ROOT, "lib", "soul_core", "dashboard_http_application.rb"))
presence = File.read(File.join(ROOT, "scripts", "soul-voice-presence-app.py"))

check("Dashboard exposes voice cues and muted preferences", html.include?('id="notification-mode"') && %w[voice cues muted].all? { |mode| javascript.include?(mode) })
notification_source = javascript[/async function emitSoulNotification.*?^}/m].to_s
check("notifications use static assets rather than synthesis", javascript.include?("/notifications/") && !notification_source.include?("voice/synthesize"))
check("spoken notice requires fresh idle Presence receipt", javascript.include?('presence.presence_state !== "listening"') && javascript.include?("/api/v1/voice/presence/status"))
check("terminal notices are session-deduplicated", javascript.include?("state.notificationKeys") && javascript.include?("uniqueKey"))
check("notification cannot authorize application operations", !notification_source.match?(/callSoul|confirmation|execute/))
check("all notification assets are explicit static routes", assets.all? { |name| http.include?("/notifications/#{name}.wav") })
check("Presence publishes state and selected voice without an IPC or network listener", presence.include?("presence.json") && presence.include?("notification_voice") && !presence.match?(/QTcpServer|QLocalServer|AF_UNIX|TCPServer|\.bind\(|\.listen\(/))
check("wake uses a distinct static cue", presence.include?("play_wake_cue") && presence.include?("notification_wake"))

puts "Notification Cues A1 verification complete."
