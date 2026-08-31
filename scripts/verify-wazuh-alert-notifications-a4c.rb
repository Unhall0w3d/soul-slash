#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/wazuh_alert_notification_service"
require_relative "../lib/soul_core/application_facade"

def check(label, condition)
  raise "FAIL: #{label}" unless condition
  puts "PASS: #{label}"
end

class AlertFixture
  attr_accessor :alerts, :enabled

  def initialize(alerts)
    @alerts = alerts
    @enabled = true
  end

  def collect
    {
      "data" => {
        "available" => true,
        "dashboard_url" => "https://vigil.herz.soul:443",
        "alerts" => @alerts,
        "notification_policy" => {"enabled" => @enabled, "minimum_level" => 10, "cooldown_seconds" => 900}
      }
    }
  end
end

class NotificationCenterFixture
  attr_accessor :delivery_state, :voice
  attr_reader :events

  def initialize
    @delivery_state = "voice_suppressed_active_presence"
    @voice = "F3"
    @events = []
  end

  def deliver(event_name:, unique_key:)
    @events << [event_name, unique_key]
    {
      "ok" => true,
      "data" => {
        "delivery_state" => @delivery_state,
        "cue_played" => @delivery_state != "voice_suppressed_active_presence",
        "spoken_played" => @delivery_state == "voice_delivered",
        "voice" => @voice
      }
    }
  end
end

def alert(id, timestamp, level, description = "private fixture description")
  {
    "event_id" => id * 64,
    "occurred_at" => timestamp,
    "level" => level,
    "severity" => level >= 13 ? "critical" : (level >= 10 ? "high" : "elevated"),
    "agent_id" => "002",
    "agent_name" => "Atelier",
    "description" => description
  }
end

Dir.mktmpdir("soul-wazuh-alert-a4c-") do |root|
  FileUtils.mkdir_p(File.join(root, "assets", "notifications"))
  FileUtils.mkdir_p(File.join(root, "Soul", "private", "security", "wazuh"), mode: 0o700)
  %w[f3 m3].each do |voice|
    File.binwrite(File.join(root, "assets", "notifications", "#{voice}-security-alert.wav"), "RIFF" + ("x" * 2_000))
  end
  now = Time.utc(2026, 8, 2, 20, 0, 0)
  baseline = [alert("a", "2026-08-02T19:58:00Z", 7), alert("b", "2026-08-02T19:59:00Z", 10)]
  alert_fixture = AlertFixture.new(baseline)
  notification_center = NotificationCenterFixture.new
  service = SoulCore::WazuhAlertNotificationService.new(
    root: root,
    process_env: {"SOUL_WAZUH_ALERTS_INTEGRATION_FILE" => "/private/fixture.json"},
    clock: -> { now },
    alert_service: alert_fixture,
    notification_center: notification_center
  )

  seeded = service.poll
  check("first poll seeds a durable baseline without speaking old alerts", seeded.dig("data", "delivery_state") == "baseline_seeded" && notification_center.events.empty?)

  now += 60
  alert_fixture.alerts = [alert("c", "2026-08-02T20:00:30Z", 13)] + baseline
  deferred = service.poll
  check("active Voice Presence suppresses speech but the independent cue completes delivery", deferred.dig("data", "delivery_state") == "voice_suppressed_active_presence" && deferred.dig("data", "pending_alerts") == 0 && notification_center.events.length == 1)

  now += 901
  notification_center.delivery_state = "voice_delivered"
  alert_fixture.alerts = [alert("f", "2026-08-02T20:15:30Z", 13)] + alert_fixture.alerts
  delivered = service.poll
  check("independent Notification Center receives one static privacy-safe notice", delivered.dig("data", "delivery_state") == "voice_delivered" && delivered.dig("data", "delivery", "batched_alerts") == 1 && notification_center.events.length == 2)

  now += 60
  unchanged = service.poll
  check("durable event IDs prevent duplicate playback", unchanged.dig("data", "new_alerts") == 0 && notification_center.events.length == 2)

  now += 60
  notification_center.voice = "M3"
  alert_fixture.alerts = [alert("d", "2026-08-02T20:03:30Z", 10)] + alert_fixture.alerts
  cooled = service.poll
  check("cooldown retains rather than replays a new alert", cooled.dig("data", "delivery_state") == "cooldown" && cooled.dig("data", "pending_alerts") == 1 && notification_center.events.length == 2)

  now += 901
  delivered_after_cooldown = service.poll
  check("pending batch delivers once after cooldown", delivered_after_cooldown.dig("data", "delivery_state") == "voice_delivered" && notification_center.events.length == 3)

  now += 60
  alert_fixture.enabled = false
  alert_fixture.alerts = [alert("e", "2026-08-02T20:20:00Z", 15)] + alert_fixture.alerts
  disabled = service.poll
  check("explicit disable suppresses and does not backlog alerts", disabled.dig("data", "delivery_state") == "disabled" && disabled.dig("data", "pending_alerts") == 0 && notification_center.events.length == 3)

  state_path = File.join(root, "Soul", "private", "security", "wazuh", "notification-state.json")
  receipt_path = File.join(root, "Soul", "private", "security", "wazuh", "notification-last-run.json")
  serialized = File.read(state_path) + File.read(receipt_path)
  check("durable state is owner-only and excludes alert descriptions", (File.stat(state_path).mode & 0o077).zero? && (File.stat(receipt_path).mode & 0o077).zero? && !serialized.include?("private fixture description"))
  check("notification receipts cannot grant remediation", service.status.dig("data", "last_receipt", "data", "remediation_authority") == false)
  facade = SoulCore::ApplicationFacade.new(root: root, wazuh_alert_notification_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "wazuh-alert-a4c-fixture",
    "operation" => "security.wazuh.notifications.status",
    "parameters" => {},
    "context" => {"interface" => "dashboard_test"}
  })
  check("Dashboard can read notification status but cannot trigger polling", envelope.fetch("lifecycle_state") == "complete" && envelope.dig("data", "initialized") == true)
end

puts "Wazuh alert notifications A4c verification complete."
