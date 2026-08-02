# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "voice_presence_launch_service"
require_relative "wazuh_alert_evidence_service"

module SoulCore
  class WazuhAlertNotificationService
    STATE_SCHEMA = "soul.security.wazuh-alert-notification-state.v1"
    RECEIPT_SCHEMA = "soul.security.wazuh-alert-notification-receipt.v1"
    MAX_STATE_BYTES = 512 * 1024
    MAX_SEEN_EVENTS = 2048
    MAX_PENDING_EVENTS = 128
    PENDING_TTL_SECONDS = 24 * 60 * 60
    PLAYER_TIMEOUT_SECONDS = 20

    def initialize(
      root: Dir.pwd,
      process_env: ENV,
      clock: -> { Time.now.utc },
      alert_service: nil,
      presence_service: nil,
      audio_player: nil
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
      @alert_service = alert_service || WazuhAlertEvidenceService.new(root: @root, process_env: @process_env, clock: @clock)
      @presence_service = presence_service || VoicePresenceLaunchService.new(root: @root, process_env: @process_env)
      @audio_player = audio_player || method(:play_audio)
      @state_root = File.join(@root, "Soul", "private", "security", "wazuh")
      @state_path = File.join(@state_root, "notification-state.json")
      @receipt_path = File.join(@state_root, "notification-last-run.json")
    end

    def poll
      now = @clock.call.utc
      evidence_result = if @alert_service.respond_to?(:notification_candidates)
                          @alert_service.notification_candidates
                        else
                          @alert_service.collect
                        end
      evidence = evidence_result.fetch("data")
      unless evidence["available"] == true
        return finish(false, "failed", "Wazuh alert notification poll failed safely", now, {
          "delivery_state" => "evidence_unavailable",
          "reason" => bounded(evidence["reason"], 240),
          "new_alerts" => 0,
          "pending_alerts" => current_pending_count
        })
      end

      alerts = Array(evidence["alerts"]).select { |alert| valid_alert?(alert) }
      policy = normalize_policy(evidence.fetch("notification_policy", {}))
      state = load_state
      unless state
        seeded = fresh_state(now, alerts.map { |alert| alert.fetch("event_id") })
        persist_state(seeded)
        return finish(true, "complete", "Wazuh alert notification baseline seeded without playback", now, {
          "delivery_state" => "baseline_seeded",
          "new_alerts" => 0,
          "pending_alerts" => 0,
          "voice_enabled" => policy.fetch("enabled")
        })
      end

      seen = Array(state["seen_event_ids"])
      new_alerts = alerts.reject { |alert| seen.include?(alert.fetch("event_id")) }
      state["seen_event_ids"] = (seen + alerts.map { |alert| alert.fetch("event_id") }).uniq.last(MAX_SEEN_EVENTS)
      state["last_poll_at"] = now.iso8601
      pending = prune_pending(Array(state["pending_alerts"]), now)
      high_new = new_alerts.select { |alert| alert.fetch("level") >= policy.fetch("minimum_level") }
      if policy.fetch("enabled")
        pending = merge_pending(pending, high_new)
      else
        pending = []
      end
      state["pending_alerts"] = pending

      delivery_state = policy.fetch("enabled") ? "nothing_to_deliver" : "disabled"
      delivery = {"attempted" => false, "played" => false, "voice" => nil, "batched_alerts" => 0}
      if policy.fetch("enabled") && pending.any?
        if cooldown_ready?(state["last_voice_attempt_at"], policy.fetch("cooldown_seconds"), now)
          presence = @presence_service.status.fetch("data", {})
          if presence["running"] == true && presence["presence_state"] == "listening"
            voice = presence["notification_voice"] == "M3" ? "M3" : "F3"
            batch = pending.dup
            state["pending_alerts"] = []
            state["last_voice_attempt_at"] = now.iso8601
            persist_state(state)
            played = @audio_player.call(notification_asset(voice))
            state["last_voice_result"] = played ? "played" : "failed_safely"
            state["last_voice_completed_at"] = now.iso8601
            delivery = {"attempted" => true, "played" => played, "voice" => voice, "batched_alerts" => batch.length}
            delivery_state = played ? "voice_delivered" : "voice_failed_safely"
          else
            delivery_state = "deferred_until_presence_idle"
          end
        else
          delivery_state = "cooldown"
        end
      end

      persist_state(state)
      finish(delivery_state != "voice_failed_safely", delivery_state == "voice_failed_safely" ? "failed" : "complete", "Wazuh alert notification poll complete", now, {
        "delivery_state" => delivery_state,
        "new_alerts" => new_alerts.length,
        "high_priority_new_alerts" => high_new.length,
        "pending_alerts" => state.fetch("pending_alerts").length,
        "highest_new_level" => new_alerts.map { |alert| alert.fetch("level") }.max,
        "voice_enabled" => policy.fetch("enabled"),
        "delivery" => delivery,
        "dashboard_url" => evidence["dashboard_url"],
        "raw_alert_payload_retained" => false,
        "remediation_authority" => false
      })
    rescue StandardError => error
      finish(false, "failed", "Wazuh alert notification poll failed safely", @clock.call.utc, {
        "delivery_state" => "failed_safely",
        "reason" => safe_reason(error),
        "new_alerts" => 0,
        "pending_alerts" => current_pending_count
      })
    end

    def status
      state = load_state
      receipt = read_private_json(@receipt_path, MAX_STATE_BYTES) if File.file?(@receipt_path)
      success({
        "configured" => !@process_env.fetch("SOUL_WAZUH_ALERTS_INTEGRATION_FILE", "").to_s.empty?,
        "initialized" => !state.nil?,
        "last_poll_at" => state&.fetch("last_poll_at", nil),
        "pending_alerts" => Array(state&.fetch("pending_alerts", [])).length,
        "last_voice_attempt_at" => state&.fetch("last_voice_attempt_at", nil),
        "last_voice_result" => state&.fetch("last_voice_result", nil),
        "last_receipt" => receipt
      })
    rescue StandardError => error
      success({"configured" => false, "initialized" => false, "reason" => safe_reason(error)})
    end

    private

    def valid_alert?(alert)
      alert.is_a?(Hash) && alert["event_id"].to_s.match?(/\A[a-f0-9]{64}\z/) && alert["level"].is_a?(Integer) && alert["level"].between?(0, 15) && parse_time(alert["occurred_at"])
    end

    def normalize_policy(policy)
      enabled = policy["enabled"] == true
      minimum = policy["minimum_level"].is_a?(Integer) ? policy["minimum_level"] : 10
      cooldown = policy["cooldown_seconds"].is_a?(Integer) ? policy["cooldown_seconds"] : 900
      {"enabled" => enabled, "minimum_level" => [[minimum, 1].max, 15].min, "cooldown_seconds" => [[cooldown, 60].max, 86_400].min}
    end

    def fresh_state(now, seen)
      {
        "schema_version" => STATE_SCHEMA,
        "baseline_seeded_at" => now.iso8601,
        "last_poll_at" => now.iso8601,
        "seen_event_ids" => seen.uniq.last(MAX_SEEN_EVENTS),
        "pending_alerts" => [],
        "last_voice_attempt_at" => nil,
        "last_voice_result" => nil
      }
    end

    def load_state
      return nil unless File.file?(@state_path)
      state = read_private_json(@state_path, MAX_STATE_BYTES)
      raise "Wazuh notification state schema is unsupported" unless state["schema_version"] == STATE_SCHEMA
      raise "Wazuh notification state event inventory is invalid" unless Array(state["seen_event_ids"]).all? { |id| id.to_s.match?(/\A[a-f0-9]{64}\z/) }
      state
    end

    def prune_pending(records, now)
      records.select do |record|
        record.is_a?(Hash) && record["event_id"].to_s.match?(/\A[a-f0-9]{64}\z/) &&
          (time = parse_time(record["occurred_at"])) && now - time <= PENDING_TTL_SECONDS
      end.last(MAX_PENDING_EVENTS)
    end

    def merge_pending(pending, alerts)
      by_id = pending.to_h { |record| [record.fetch("event_id"), record] }
      alerts.each do |alert|
        by_id[alert.fetch("event_id")] = {
          "event_id" => alert.fetch("event_id"),
          "occurred_at" => alert.fetch("occurred_at"),
          "level" => alert.fetch("level"),
          "severity" => alert.fetch("severity"),
          "agent_id" => bounded(alert["agent_id"], 16)
        }
      end
      by_id.values.sort_by { |record| [record.fetch("occurred_at"), record.fetch("event_id")] }.last(MAX_PENDING_EVENTS)
    end

    def cooldown_ready?(last_attempt, cooldown, now)
      return true if last_attempt.to_s.empty?
      time = parse_time(last_attempt)
      time.nil? || now - time >= cooldown
    end

    def notification_asset(voice)
      path = File.join(@root, "assets", "notifications", "#{voice.downcase}-security-alert.wav")
      raise "security notification audio is unavailable" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1_000, 2_000_000) && File.binread(path, 4) == "RIFF"
      path
    end

    def play_audio(path)
      player = "/usr/bin/pw-play"
      raise "PipeWire audio player is unavailable" unless File.executable?(player)
      pid = Process.spawn(player, path, in: :close, out: File::NULL, err: File::NULL)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PLAYER_TIMEOUT_SECONDS
      loop do
        waited = Process.waitpid(pid, Process::WNOHANG)
        return $?.success? if waited
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep(0.05)
      end
      Process.kill("TERM", pid)
      Process.waitpid(pid)
      false
    rescue SystemCallError
      false
    end

    def persist_state(state)
      persist_json(@state_path, state)
    end

    def finish(ok, lifecycle, message, now, data)
      receipt = {
        "schema_version" => RECEIPT_SCHEMA,
        "checked_at" => now.iso8601,
        "lifecycle_state" => lifecycle,
        "ok" => ok,
        "message" => message,
        "data" => data
      }
      persist_json(@receipt_path, receipt)
      success(data.merge("checked_at" => now.iso8601), ok: ok, lifecycle: lifecycle, message: message, mutation: "notification_state")
    end

    def persist_json(path, data)
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      File.chmod(0o700, @state_root)
      raise "refusing symlink Wazuh notification destination" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.binwrite(temporary, "#{JSON.pretty_generate(data)}\n", mode: "wx", perm: 0o600)
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def current_pending_count
      Array(load_state&.fetch("pending_alerts", [])).length
    rescue StandardError
      0
    end

    def read_private_json(path, maximum)
      raise "private JSON path is unsafe" if File.symlink?(path)
      stat = File.stat(path)
      raise "private JSON file is not owner-private" unless stat.file? && (stat.mode & 0o077).zero?
      raise "private JSON file exceeds its size bound" if stat.size > maximum
      JSON.parse(File.binread(path, maximum + 1))
    end

    def parse_time(value)
      Time.iso8601(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def safe_reason(error)
      bounded(error.message.to_s.gsub(%r{/(?:home|run|etc)/[^\s]+}, "[private path]"), 240)
    end

    def bounded(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def success(data, ok: true, lifecycle: "complete", message: nil, mutation: "none")
      result = {"ok" => ok, "lifecycle_state" => lifecycle, "data" => data, "mutation" => mutation}
      result["message"] = message if message
      result
    end
  end
end
