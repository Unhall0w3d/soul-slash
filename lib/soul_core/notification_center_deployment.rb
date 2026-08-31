# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

module SoulCore
  class NotificationCenterDeployment
    UNIT = "soul-notification-center.service"
    CONFIRM_INSTALL = "INSTALL_SOUL_NOTIFICATION_CENTER"
    CONFIRM_REMOVE = "REMOVE_SOUL_NOTIFICATION_CENTER"

    def initialize(root: Dir.pwd, home: Dir.home, ruby_path: RbConfig.ruby, executor: nil)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @ruby_path = File.expand_path(ruby_path)
      @executor = executor || method(:capture)
    end

    def plan
      content = unit_content
      digest = Digest::SHA256.hexdigest(content)
      result(true, "blocked_for_human_review", "Review the exact independent Notification Center user service", {
        "unit" => UNIT,
        "unit_path" => unit_path,
        "unit_sha256" => digest,
        "expected_digest" => digest,
        "confirmation_phrase" => CONFIRM_INSTALL,
        "enabled_after_install" => true,
        "network_listener" => false,
        "llm_or_core_dependency" => false,
        "notification_content_retained" => false,
        "voice_presence_required" => false,
        "user_manager_lifecycle" => true
      })
    end

    def install(expected_digest:, confirmation:)
      planned = plan.fetch("data")
      return result(false, "awaiting_input", "Exact Notification Center installation confirmation is required", planned) unless confirmation == CONFIRM_INSTALL
      return result(false, "awaiting_input", "Notification Center unit digest changed; review the new plan", planned) unless expected_digest == planned.fetch("expected_digest")

      validate_runtime!
      FileUtils.mkdir_p(File.dirname(unit_path), mode: 0o700)
      FileUtils.mkdir_p(File.join(@home, ".local", "state", "soul", "notification-center"), mode: 0o700)
      write_atomic(unit_path, unit_content, 0o600)
      reload = @executor.call(["systemctl", "--user", "daemon-reload"])
      enable = reload["success"] ? @executor.call(["systemctl", "--user", "enable", "--now", UNIT]) : { "success" => false }
      return result(false, "failed", "Notification Center installation failed safely", planned) unless reload["success"] && enable["success"]

      result(true, "complete", "Independent Notification Center installed and started", planned.merge("installed_exact" => installed_exact?), "notification_center_deployment")
    rescue StandardError => error
      result(false, "failed", "Notification Center installation failed safely: #{error.class}", {})
    end

    def status
      active = @executor.call(["systemctl", "--user", "is-active", UNIT])
      enabled = @executor.call(["systemctl", "--user", "is-enabled", UNIT])
      result(true, "complete", "Notification Center deployment status collected", {
        "unit" => UNIT,
        "installed_exact" => installed_exact?,
        "active" => active["success"] && active["stdout"].to_s.strip == "active",
        "enabled" => enabled["success"] && enabled["stdout"].to_s.strip == "enabled"
      })
    end

    def uninstall(confirmation:)
      return result(false, "awaiting_input", "Exact Notification Center removal confirmation is required", { "confirmation_phrase" => CONFIRM_REMOVE }) unless confirmation == CONFIRM_REMOVE
      @executor.call(["systemctl", "--user", "disable", "--now", UNIT])
      File.delete(unit_path) if File.file?(unit_path) && !File.symlink?(unit_path)
      @executor.call(["systemctl", "--user", "daemon-reload"])
      result(true, "complete", "Notification Center user service removed; owner settings were retained", { "unit" => UNIT }, "notification_center_deployment")
    rescue StandardError => error
      result(false, "failed", "Notification Center removal failed safely: #{error.class}", {})
    end

    private

    def unit_content
      observer = File.join(@root, "scripts", "soul-notification-center-observer.py")
      cli = File.join(@root, "scripts", "soul-notification-center")
      state = File.join(@home, ".local", "state", "soul", "notification-center")
      <<~UNIT
        [Unit]
        Description=Soul independent local Notification Center
        After=pipewire.service
        StartLimitIntervalSec=120
        StartLimitBurst=3

        [Service]
        Type=simple
        ExecStart=/usr/bin/python3 #{unit_quote(observer)} --project-root #{unit_quote(@root)} --ruby #{unit_quote(@ruby_path)} --cli #{unit_quote(cli)}
        Restart=on-failure
        RestartSec=5
        TimeoutStopSec=5
        NoNewPrivileges=yes
        PrivateTmp=yes
        ProtectSystem=strict
        ProtectHome=read-only
        ReadWritePaths=#{unit_quote(state)}
        RestrictAddressFamilies=AF_UNIX
        LockPersonality=yes
        UMask=0077

        [Install]
        WantedBy=default.target
      UNIT
    end

    def validate_runtime!
      %w[soul-notification-center soul-notification-center-observer.py soul_voice_notification_observer.py].each do |name|
        path = File.join(@root, "scripts", name)
        raise "runtime unavailable" unless File.file?(path) && !File.symlink?(path)
      end
      raise "Ruby runtime unavailable" unless File.file?(@ruby_path) && File.executable?(@ruby_path) && !File.symlink?(@ruby_path)
    end

    def installed_exact?
      File.file?(unit_path) && !File.symlink?(unit_path) && File.binread(unit_path, 128 * 1024) == unit_content
    end

    def unit_path = File.join(@home, ".config", "systemd", "user", UNIT)

    def write_atomic(path, content, mode)
      raise "refusing symlink destination" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def capture(command)
      stdout, stderr, status = Open3.capture3(*command)
      { "success" => status.success?, "stdout" => stdout, "stderr" => stderr }
    end

    def unit_quote(value) = "\"#{value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')}\""
    def result(ok, lifecycle, message, data, mutation = "none") = { "ok" => ok, "lifecycle_state" => lifecycle, "message" => message, "data" => data, "mutation" => mutation }
  end
end
