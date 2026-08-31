#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

assets = %w[
  cue-submit cue-wake cue-complete cue-attention
  f3-chat-ready m3-chat-ready f3-music-ready m3-music-ready
  f3-visual-ready m3-visual-ready f3-lyrics-ready m3-lyrics-ready
  f3-improvement-ready m3-improvement-ready f3-backup-ready m3-backup-ready
  f3-attention m3-attention
  f3-device-attention m3-device-attention
  f3-reboot-required m3-reboot-required
  f3-backup-attention m3-backup-attention
  f3-communication-urgent m3-communication-urgent
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
observer = File.read(File.join(ROOT, "scripts", "soul_voice_notification_observer.py"))
center = File.read(File.join(ROOT, "lib", "soul_core", "notification_center_service.rb"))
desktop_observer = File.read(File.join(ROOT, "scripts", "soul-notification-center-observer.py"))

check("Dashboard exposes full voice, priority voice, cues, and muted preferences", html.include?('id="notification-mode"') && %w[voice priority cues muted].all? { |mode| javascript.include?(mode) })
notification_source = javascript[/async function deliverSoulNotification.*?^}/m].to_s
check("notifications use the independent center rather than synthesis", notification_source.include?("/api/v1/notifications/deliver") && !notification_source.include?("voice/synthesize"))
check("spoken notices do not require Voice Presence to be open", center.include?('"voice_presence_required" => false') && !notification_source.include?("/api/v1/voice/presence/status"))
check("terminal notices are session-deduplicated", javascript.include?("state.notificationKeys") && javascript.include?("uniqueKey"))
check("terminal notices serialize delivery and priority mode is enforced centrally", javascript.include?("state.notificationQueue") && center.include?("spoken_eligible?") && center.include?('event["priority"] == true'))
check("fleet notices establish a silent baseline and report later degradations", javascript.include?("state.maintenanceNotificationStates") && javascript.include?("if (!prior || prior === next) return") && javascript.include?("emitMaintenanceTransitions"))
check("improvement and recovery notices remain review-only", javascript.include?("improvement_ready") && javascript.include?("backup_ready") && javascript.include?("backup_attention"))
check("notification cannot authorize application operations", !notification_source.match?(/callSoul|confirmation|execute/) && center.include?('"execution_authority" => false'))
check("all notification assets are explicit static routes", assets.all? { |name| http.include?("/notifications/#{name}.wav") })
check("Presence publishes collision state without owning notification delivery", presence.include?("presence.json") && !presence.include?("dbus-monitor") && !presence.include?("play_notification"))
check("wake uses a distinct static cue", presence.include?("play_wake_cue") && presence.include?("notification_wake"))
check("standalone desktop observer reuses the reviewed metadata classifier", observer.include?("communication-urgent") && desktop_observer.include?("NotificationMonitorParser") && desktop_observer.include?("communication_urgent"))

puts "Notification Cues A1 verification complete."
