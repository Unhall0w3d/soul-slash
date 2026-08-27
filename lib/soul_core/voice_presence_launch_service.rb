# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module SoulCore
  class VoicePresenceLaunchService
    START_TIMEOUT_SECONDS = 3.0

    def initialize(
      root: Dir.pwd,
      state_root: ENV.fetch("SOUL_VOICE_PRESENCE_STATE_ROOT", File.join(Dir.home, ".local", "state", "soul", "voice-presence")),
      launcher: nil,
      process_env: ENV,
      clock: -> { Time.now },
      spawner: nil
    )
      @root = File.expand_path(root)
      @state_root = File.expand_path(state_root)
      @launcher = File.expand_path(launcher || File.join(@root, "scripts", "soul-voice-presence"))
      @process_env = process_env.to_h
      @clock = clock
      @spawner = spawner || method(:spawn_process)
    end

    def status
      presence = presence_state
      outcome("complete", true, running? ? "Voice Presence is open" : "Voice Presence is closed", {
        "running" => running?,
        "visible_window_required" => true,
        "wake_phrases" => ["Hey Soul", "Hey Slash"],
        "survives_window_close" => false,
        "presence_state" => presence["state"],
        "notification_voice" => presence["notification_voice"]
      })
    end

    def launch
      return outcome("complete", true, "Voice Presence is already open", { "running" => true, "already_running" => true }) if running?
      return outcome("blocked_for_human_review", false, "Voice Presence launcher is unavailable") unless File.executable?(@launcher) && !File.symlink?(@launcher)

      FileUtils.mkdir_p(@state_root, mode: 0o700)
      @spawner.call(@launcher, launch_environment)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + START_TIMEOUT_SECONDS
      sleep(0.05) until running? || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      return outcome("failed", false, "Voice Presence did not open; inspect the owner-private launch log") unless running?

      outcome("complete", true, "Voice Presence opened on the local desktop", { "running" => true, "already_running" => false })
    rescue SystemCallError => error
      outcome("failed", false, "Voice Presence launch failed safely: #{error.class}")
    end

    private

    def running?
      return false unless File.directory?(@state_root) && !File.symlink?(@state_root)

      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        acquired = lock.flock(File::LOCK_EX | File::LOCK_NB)
        lock.flock(File::LOCK_UN) if acquired
        !acquired
      end
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def lock_path = File.join(@state_root, "run.lock")

    def presence_state
      path = File.join(@state_root, "presence.json")
      return {} unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 4096

      record = JSON.parse(File.binread(path, 4096))
      state = record["state"].to_s
      voice = record["notification_voice"].to_s
      {
        "state" => %w[starting listening paused awakened hearing thinking speaking followup failed].include?(state) ? state : nil,
        "notification_voice" => %w[F3 M3].include?(voice) ? voice : nil
      }.compact
    rescue JSON::ParserError, Errno::ENOENT
      {}
    end

    def launch_environment
      runtime = @process_env["XDG_RUNTIME_DIR"].to_s
      runtime = "/run/user/#{Process.uid}" if runtime.empty?
      wayland = @process_env["WAYLAND_DISPLAY"].to_s
      if wayland.empty?
        socket = Dir.glob(File.join(runtime, "wayland-*")).find { |path| File.socket?(path) rescue false }
        wayland = File.basename(socket) if socket
      end
      {
        "XDG_RUNTIME_DIR" => runtime,
        "WAYLAND_DISPLAY" => wayland,
        "DBUS_SESSION_BUS_ADDRESS" => @process_env["DBUS_SESSION_BUS_ADDRESS"].to_s.empty? ? "unix:path=#{runtime}/bus" : @process_env["DBUS_SESSION_BUS_ADDRESS"],
        "SOUL_VOICE_PRESENCE_STATE_ROOT" => @state_root
      }.reject { |_key, value| value.to_s.empty? }
    end

    def spawn_process(launcher, environment)
      log = File.join(@state_root, "launch.log")
      pid = Process.spawn(environment, launcher, chdir: @root, out: log, err: [:child, :out], pgroup: true)
      Process.detach(pid)
    end

    def outcome(state, ok, message, data = {})
      {
        "lifecycle_state" => state,
        "ok" => ok,
        "message" => message,
        "data" => data.merge("checked_at" => @clock.call.utc.iso8601),
        "mutation" => ok && data["already_running"] == false ? "voice_presence_launched" : "none"
      }
    end
  end
end
