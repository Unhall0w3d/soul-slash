#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/notification_center_deployment"
require_relative "../lib/soul_core/notification_center_service"

def check(label, condition)
  raise "FAIL: #{label}" unless condition
  puts "PASS: #{label}"
end

class PresenceFixture
  attr_accessor :running, :state

  def initialize(running: false, state: nil)
    @running = running
    @state = state
  end

  def status
    { "data" => { "running" => @running, "presence_state" => @state } }
  end
end

Dir.mktmpdir("soul-notification-center-") do |root|
  state_root = File.join(root, "private-state")
  assets = File.join(root, "assets", "notifications")
  FileUtils.mkdir_p(assets)
  stems = SoulCore::NotificationCenterService::EVENTS.values.flat_map do |event|
    ["cue-#{event.fetch('cue')}"] + %w[f3 m3].filter_map { |voice| "#{voice}-#{event['spoken']}" if event["spoken"] }
  end.uniq
  stems.each { |stem| File.binwrite(File.join(assets, "#{stem}.wav"), "RIFF" + ("x" * 2_000)) }

  now = Time.utc(2026, 8, 31, 12, 0, 0)
  presence = PresenceFixture.new
  played = []
  service = SoulCore::NotificationCenterService.new(
    root: root,
    state_root: state_root,
    presence_service: presence,
    audio_player: ->(path) { played << File.basename(path); true },
    clock: -> { now }
  )

  status = service.status
  check("Notification Center is independent of Voice Presence", status["ok"] && status.dig("data", "voice_presence_required") == false)
  check("default priority mode speaks material attention while Presence is closed", service.deliver(event_name: "security_alert", unique_key: "event-1").dig("data", "spoken_played") == true && played == %w[cue-attention.wav f3-security-alert.wav])

  duplicate = service.deliver(event_name: "security_alert", unique_key: "event-1")
  check("persistent hashed event keys suppress duplicates", duplicate.dig("data", "delivery_state") == "duplicate" && played.length == 2)

  presence.running = true
  presence.state = "speaking"
  suppressed = service.deliver(event_name: "device_attention", unique_key: "event-2")
  check("active Voice Presence suppresses speech but preserves the cue", suppressed.dig("data", "delivery_state") == "voice_suppressed_active_presence" && suppressed.dig("data", "cue_played") == true && played.last == "cue-attention.wav")

  unavailable_presence = Object.new
  unavailable_presence.define_singleton_method(:status) { raise "fixture unavailable" }
  unavailable_service = SoulCore::NotificationCenterService.new(
    root: root, state_root: File.join(root, "unavailable-state"), presence_service: unavailable_presence,
    audio_player: ->(path) { played << File.basename(path); true }, clock: -> { now }
  )
  unavailable = unavailable_service.deliver(event_name: "attention", unique_key: "event-unavailable")
  check("unavailable collision evidence fails speech closed while preserving the cue", unavailable.dig("data", "delivery_state") == "voice_suppressed_presence_unavailable" && unavailable.dig("data", "spoken_played") == false)

  updated = service.update_settings(mode: "cues", voice: "M3")
  cues = service.deliver(event_name: "music_ready", unique_key: "event-3")
  check("owner settings select cues-only and persist privately", updated["ok"] && cues.dig("data", "spoken_played") == false && (File.stat(File.join(state_root, "settings.json")).mode & 0o077).zero?)

  service.update_settings(mode: "muted", voice: "M3")
  muted_count = played.length
  muted = service.deliver(event_name: "attention", unique_key: "event-4")
  check("muted mode performs no playback", muted.dig("data", "delivery_state") == "muted" && played.length == muted_count)
  check("unknown events fail closed", service.deliver(event_name: "run_command")["lifecycle_state"] == "awaiting_input")

  serialized = Dir.glob(File.join(state_root, "*.json")).map { |path| File.read(path) }.join
  check("durable state contains hashes and settings but no notification content", serialized.include?("seen_keys") && !serialized.include?("event-1") && !serialized.include?("run_command"))
end

Dir.mktmpdir("soul-notification-deployment-") do |root|
  scripts = File.join(root, "scripts")
  home = File.join(root, "home")
  FileUtils.mkdir_p(scripts)
  %w[soul-notification-center soul-notification-center-observer.py soul_voice_notification_observer.py].each do |name|
    File.write(File.join(scripts, name), "fixture\n")
  end
  commands = []
  executor = lambda do |command|
    commands << command
    stdout = command.include?("is-active") ? "active\n" : (command.include?("is-enabled") ? "enabled\n" : "")
    { "success" => true, "stdout" => stdout, "stderr" => "" }
  end
  deployment = SoulCore::NotificationCenterDeployment.new(root: root, home: home, executor: executor)
  plan = deployment.plan
  check("deployment is exact-digest and human-gated", plan["lifecycle_state"] == "blocked_for_human_review" && plan.dig("data", "confirmation_phrase") == "INSTALL_SOUL_NOTIFICATION_CENTER" && plan.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/))
  check("deployment declares no network, Core, or content-retention dependency", plan.dig("data", "network_listener") == false && plan.dig("data", "llm_or_core_dependency") == false && plan.dig("data", "notification_content_retained") == false)
  rejected = deployment.install(expected_digest: plan.dig("data", "expected_digest"), confirmation: "wrong")
  check("installation rejects an inexact confirmation", rejected["lifecycle_state"] == "awaiting_input" && commands.empty?)
  installed = deployment.install(expected_digest: plan.dig("data", "expected_digest"), confirmation: "INSTALL_SOUL_NOTIFICATION_CENTER")
  unit = File.read(plan.dig("data", "unit_path"))
  check("reviewed install writes an exact enabled user unit", installed["ok"] && installed.dig("data", "installed_exact") == true && commands.any? { |command| command.include?("enable") })
  check("unit follows the active user manager, remains local-only, and is hardened", unit.include?("WantedBy=default.target") && unit.include?("RestrictAddressFamilies=AF_UNIX") && unit.include?("ProtectSystem=strict") && !unit.match?(/Listen|curl|wget|http/i))
end

auth = Object.new
auth.define_singleton_method(:session) do |token|
  token == "session" ? { "authenticated" => true, "username" => "admin", "password_change_required" => false } : nil
end
center = Object.new
center.define_singleton_method(:status) { { "ok" => true, "lifecycle_state" => "complete", "data" => { "mode" => "priority", "voice" => "F3" } } }
center.define_singleton_method(:update_settings) { |mode:, voice:| { "ok" => true, "lifecycle_state" => "complete", "data" => { "mode" => mode, "voice" => voice } } }
center.define_singleton_method(:deliver) { |event_name:, unique_key:| { "ok" => true, "lifecycle_state" => "complete", "data" => { "event_name" => event_name, "unique_key" => unique_key } } }
app = SoulCore::DashboardHttpApplication.new(
  root: File.expand_path("..", __dir__), facade: Object.new, bind_host: "127.0.0.1", port: 4567,
  csrf_token: "notification-csrf", authentication: auth, notification_center: center
)
headers = {
  "Host" => "127.0.0.1:4567", "Origin" => "http://127.0.0.1:4567",
  "Cookie" => "soul_session=session", "Content-Type" => "application/json",
  "X-Soul-CSRF" => "notification-csrf"
}
check("Notification Center status requires an authenticated session", app.call(method: "GET", target: "/api/v1/notifications/status", headers: headers.reject { |key, _| key == "Cookie" }).status == 401)
check("Notification Center delivery rejects a missing CSRF token", app.call(method: "POST", target: "/api/v1/notifications/deliver", headers: headers.reject { |key, _| key == "X-Soul-CSRF" }, body: '{"event_name":"attention"}').status == 403)
check("authenticated Dashboard can persist settings and deliver allowlisted events", app.call(method: "POST", target: "/api/v1/notifications/settings", headers: headers, body: '{"mode":"cues","voice":"M3"}').status == 200 && app.call(method: "POST", target: "/api/v1/notifications/deliver", headers: headers, body: '{"event_name":"attention","unique_key":"fixture"}').status == 200)

voice = File.read(File.expand_path("soul-voice-presence-app.py", __dir__))
observer = File.read(File.expand_path("soul-notification-center-observer.py", __dir__))
dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
check("Voice Presence no longer owns the desktop observer", !voice.include?("dbus-monitor") && !voice.include?("Observe desktop notifications"))
check("standalone observer classifies metadata and dispatches allowlisted static events", observer.include?("dbus-monitor") && observer.include?("NotificationMonitorParser") && observer.include?("communication_urgent") && !observer.include?("summary") && !observer.include?("body"))
check("Dashboard uses authenticated and CSRF-bound Notification Center endpoints", dashboard.include?("/api/v1/notifications/deliver") && http.include?("notification_center_deliver") && http.include?("mutation_boundary_error(headers, body)") && http.include?("authenticated_session_error(headers)"))

puts "Independent Notification Center A4-A6 verification complete."
