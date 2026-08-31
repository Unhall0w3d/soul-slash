# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "timeout"
require "time"
require_relative "voice_presence_launch_service"

module SoulCore
  class NotificationCenterService
    SETTINGS_SCHEMA = "soul.notification-center.settings.v1"
    STATE_SCHEMA = "soul.notification-center.delivery-state.v1"
    MODES = %w[voice priority cues muted].freeze
    VOICES = %w[F3 M3].freeze
    MAX_KEYS = 256
    PLAYER_TIMEOUT_SECONDS = 20
    EVENTS = {
      "submit" => { "cue" => "submit" },
      "chat_ready" => { "cue" => "complete", "spoken" => "chat-ready" },
      "music_ready" => { "cue" => "complete", "spoken" => "music-ready" },
      "visual_ready" => { "cue" => "complete", "spoken" => "visual-ready" },
      "lyrics_ready" => { "cue" => "complete", "spoken" => "lyrics-ready" },
      "improvement_ready" => { "cue" => "complete", "spoken" => "improvement-ready" },
      "backup_ready" => { "cue" => "complete", "spoken" => "backup-ready" },
      "attention" => { "cue" => "attention", "spoken" => "attention", "priority" => true },
      "device_attention" => { "cue" => "attention", "spoken" => "device-attention", "priority" => true },
      "reboot_required" => { "cue" => "attention", "spoken" => "reboot-required", "priority" => true },
      "backup_attention" => { "cue" => "attention", "spoken" => "backup-attention", "priority" => true },
      "communication_urgent" => { "cue" => "attention", "spoken" => "communication-urgent", "priority" => true },
      "security_alert" => { "cue" => "attention", "spoken" => "security-alert", "priority" => true }
    }.freeze

    def initialize(
      root: Dir.pwd,
      state_root: ENV.fetch("SOUL_NOTIFICATION_CENTER_STATE_ROOT", File.join(Dir.home, ".local", "state", "soul", "notification-center")),
      presence_service: nil,
      audio_player: nil,
      clock: -> { Time.now.utc }
    )
      @root = File.expand_path(root)
      @state_root = File.expand_path(state_root)
      @presence_service = presence_service || VoicePresenceLaunchService.new(root: @root)
      @audio_player = audio_player || method(:play_audio)
      @clock = clock
    end

    def status
      settings = load_settings
      presence = presence_snapshot
      outcome(true, "complete", "Notification Center is available", settings.merge(
        "voice_presence_required" => false,
        "voice_presence_available" => !presence.nil?,
        "voice_presence_running" => presence&.fetch("running", false) == true,
        "voice_presence_state" => presence&.fetch("presence_state", nil),
        "supported_events" => EVENTS.keys,
        "desktop_observer" => "separate_runtime"
      ))
    rescue StandardError => error
      outcome(false, "failed", "Notification Center status failed safely: #{error.class}", {})
    end

    def update_settings(mode:, voice:)
      normalized_mode = mode.to_s
      normalized_voice = voice.to_s.upcase
      return outcome(false, "awaiting_input", "notification mode is invalid", {}) unless MODES.include?(normalized_mode)
      return outcome(false, "awaiting_input", "notification voice is invalid", {}) unless VOICES.include?(normalized_voice)

      settings = default_settings.merge("mode" => normalized_mode, "voice" => normalized_voice, "updated_at" => @clock.call.utc.iso8601)
      persist_json(settings_path, settings)
      outcome(true, "complete", "Notification Center settings updated", settings, "notification_settings_updated")
    rescue StandardError => error
      outcome(false, "failed", "Notification Center settings failed safely: #{error.class}", {})
    end

    def deliver(event_name:, unique_key: nil)
      event_name = event_name.to_s
      event = EVENTS[event_name]
      return outcome(false, "awaiting_input", "notification event is not allowlisted", {}) unless event
      return outcome(false, "awaiting_input", "notification key is invalid", {}) unless valid_key?(unique_key)

      ensure_state_root!
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        settings = load_settings
        return delivery_outcome(event_name, settings, "muted", false, false) if settings["mode"] == "muted"

        key_digest = unique_key.to_s.empty? ? nil : Digest::SHA256.hexdigest("#{event_name}\0#{unique_key}")
        state = load_delivery_state
        return delivery_outcome(event_name, settings, "duplicate", false, false) if key_digest && state["seen_keys"].include?(key_digest)

        remember_key(state, key_digest)
        cue_played = @audio_player.call(notification_asset("cue-#{event.fetch('cue')}"))
        spoken_played = false
        delivery_state = cue_played ? "cue_delivered" : "cue_failed_safely"
        if spoken_eligible?(settings.fetch("mode"), event)
          presence = presence_snapshot
          if presence.nil?
            delivery_state = "voice_suppressed_presence_unavailable"
          elsif presence_active?(presence)
            delivery_state = "voice_suppressed_active_presence"
          elsif event["spoken"]
            spoken_played = @audio_player.call(notification_asset("#{settings.fetch('voice').downcase}-#{event.fetch('spoken')}"))
            delivery_state = spoken_played ? "voice_delivered" : "voice_failed_safely"
          end
        end
        state["last_delivery_at"] = @clock.call.utc.iso8601
        state["last_delivery_state"] = delivery_state
        persist_json(delivery_state_path, state)
        delivery_outcome(event_name, settings, delivery_state, cue_played, spoken_played)
      end
    rescue StandardError => error
      outcome(false, "failed", "Notification Center delivery failed safely: #{error.class}", { "event_name" => event_name })
    end

    private

    def default_settings
      { "schema_version" => SETTINGS_SCHEMA, "mode" => "priority", "voice" => "F3", "updated_at" => nil }
    end

    def load_settings
      return default_settings unless safe_private_json?(settings_path, 16 * 1024)
      record = JSON.parse(File.binread(settings_path, 16 * 1024))
      raise "unsupported settings" unless record["schema_version"] == SETTINGS_SCHEMA
      raise "invalid mode" unless MODES.include?(record["mode"])
      raise "invalid voice" unless VOICES.include?(record["voice"])
      default_settings.merge(record.slice("mode", "voice", "updated_at"))
    rescue JSON::ParserError
      default_settings
    end

    def load_delivery_state
      return { "schema_version" => STATE_SCHEMA, "seen_keys" => [], "last_delivery_at" => nil, "last_delivery_state" => nil } unless safe_private_json?(delivery_state_path, 128 * 1024)
      record = JSON.parse(File.binread(delivery_state_path, 128 * 1024))
      raise "unsupported delivery state" unless record["schema_version"] == STATE_SCHEMA
      record["seen_keys"] = Array(record["seen_keys"]).select { |value| value.to_s.match?(/\A[a-f0-9]{64}\z/) }.last(MAX_KEYS)
      record
    rescue JSON::ParserError
      { "schema_version" => STATE_SCHEMA, "seen_keys" => [], "last_delivery_at" => nil, "last_delivery_state" => nil }
    end

    def remember_key(state, digest)
      return unless digest
      state["seen_keys"] = (Array(state["seen_keys"]) + [digest]).uniq.last(MAX_KEYS)
    end

    def spoken_eligible?(mode, event)
      mode == "voice" || (mode == "priority" && event["priority"] == true)
    end

    def presence_active?(presence)
      presence["running"] == true && presence["presence_state"] != "listening"
    end

    def valid_key?(value)
      value.nil? || (value.is_a?(String) && value.bytesize.between?(1, 512) && value.valid_encoding?)
    end

    def notification_asset(stem)
      path = File.join(@root, "assets", "notifications", "#{stem}.wav")
      raise "notification asset unavailable" unless File.file?(path) && !File.symlink?(path) && File.size(path).between?(1_000, 2_000_000) && File.binread(path, 4) == "RIFF"
      path
    end

    def play_audio(path)
      Timeout.timeout(PLAYER_TIMEOUT_SECONDS) do
        _stdout, _stderr, status = Open3.capture3("pw-play", path)
        status.success?
      end
    rescue Timeout::Error, SystemCallError
      false
    end

    def presence_snapshot
      result = @presence_service.status
      return nil unless result.is_a?(Hash) && result["data"].is_a?(Hash)
      result["data"]
    rescue StandardError
      nil
    end

    def safe_private_json?(path, maximum)
      File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, maximum) && (File.stat(path).mode & 0o077).zero?
    end

    def persist_json(path, payload)
      ensure_state_root!
      raise "refusing symlink destination" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(payload) + "\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def ensure_state_root!
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      raise "refusing symlink state root" if File.symlink?(@state_root)
      File.chmod(0o700, @state_root)
    end

    def settings_path = File.join(@state_root, "settings.json")
    def delivery_state_path = File.join(@state_root, "delivery-state.json")
    def lock_path = File.join(@state_root, "delivery.lock")

    def delivery_outcome(event_name, settings, delivery_state, cue_played, spoken_played)
      ok = !delivery_state.end_with?("failed_safely")
      outcome(ok, ok ? "complete" : "failed", "Notification Center delivery #{delivery_state.tr('_', ' ')}", {
        "event_name" => event_name,
        "delivery_state" => delivery_state,
        "cue_played" => cue_played,
        "spoken_played" => spoken_played,
        "mode" => settings["mode"],
        "voice" => settings["voice"],
        "voice_presence_required" => false,
        "execution_authority" => false
      }, "notification_delivery")
    end

    def outcome(ok, lifecycle, message, data, mutation = "none")
      { "ok" => ok, "lifecycle_state" => lifecycle, "message" => message, "data" => data.merge("checked_at" => @clock.call.utc.iso8601), "mutation" => mutation }
    end
  end
end
