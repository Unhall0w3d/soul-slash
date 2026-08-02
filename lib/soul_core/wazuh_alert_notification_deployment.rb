# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"

module SoulCore
  class WazuhAlertNotificationDeployment
    CONFIRM_INSTALL = "INSTALL_SOUL_WAZUH_ALERT_NOTIFICATIONS"
    CONFIRM_UNINSTALL = "REMOVE_SOUL_WAZUH_ALERT_NOTIFICATIONS"
    SERVICE = "soul-wazuh-alert-notifications.service"
    TIMER = "soul-wazuh-alert-notifications.timer"

    def initialize(root: Dir.pwd, home: Dir.home, integration_file:, ruby_path: RbConfig.ruby, systemctl_path: "/usr/bin/systemctl", runner: nil)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @integration_file = File.expand_path(integration_file.to_s)
      @ruby_path = File.expand_path(ruby_path)
      @systemctl_path = File.expand_path(systemctl_path)
      @runner = runner || method(:capture)
      @unit_root = File.join(@home, ".config", "systemd", "user")
    end

    def plan
      errors = []
      errors << "Ruby executable is unavailable" unless File.file?(@ruby_path) && File.executable?(@ruby_path)
      errors << "systemctl is unavailable" unless File.file?(@systemctl_path) && File.executable?(@systemctl_path)
      errors << "Wazuh notification poller is unavailable" unless File.file?(poller_script)
      errors << "Wazuh alert integration manifest must be an owner-private regular file" unless private_file?(@integration_file)
      return result(false, "failed", errors.first, {"errors" => errors}) unless errors.empty?

      result(true, "blocked_for_human_review", "Review the exact closed-page Wazuh alert notification timer.", {
        "confirmation" => CONFIRM_INSTALL,
        "files" => paths,
        "on_boot_seconds" => 120,
        "interval_seconds" => 60,
        "randomized_delay_seconds" => 10,
        "persistent" => true,
        "integration_file" => @integration_file,
        "remote_authority" => "read_only_alert_search",
        "notification_authority" => "static_local_audio_only",
        "remediation_authority" => false,
        "units" => rendered
      })
    end

    def install(confirmation:)
      planned = plan
      return planned unless planned["ok"]
      return result(false, "awaiting_input", "Exact Wazuh notification installation confirmation is required.", planned["data"]) unless confirmation == CONFIRM_INSTALL

      FileUtils.mkdir_p(@unit_root, mode: 0o700)
      rendered.each { |name, content| write_atomic(File.join(@unit_root, name), content, 0o644) }
      [[@systemctl_path, "--user", "daemon-reload"], [@systemctl_path, "--user", "enable", "--now", TIMER]].each do |command|
        execution = @runner.call(command)
        return result(false, "failed", "Wazuh notification timer installation failed safely.", {"stderr" => bounded(execution["stderr"])}) unless execution["success"]
      end
      result(true, "complete", "Closed-page Wazuh alert notification timer installed.", {"files" => paths, "timer" => TIMER}, "deployment_state")
    rescue SystemCallError, IOError => error
      result(false, "failed", "Wazuh notification timer installation failed safely: #{error.class}.", {})
    end

    def status
      execution = @runner.call([@systemctl_path, "--user", "show", TIMER, "--property=ActiveState,UnitFileState,NextElapseUSecRealtime", "--no-pager"])
      result(execution["success"], "complete", "Wazuh notification timer status collected.", {"timer" => bounded(execution["stdout"]), "installed_exact" => installed_exact?})
    end

    def uninstall(confirmation:)
      return result(false, "awaiting_input", "Exact Wazuh notification timer removal confirmation is required.", {"confirmation" => CONFIRM_UNINSTALL}) unless confirmation == CONFIRM_UNINSTALL

      @runner.call([@systemctl_path, "--user", "disable", "--now", TIMER])
      paths.each_value { |path| File.delete(path) if safe_file?(path) }
      @runner.call([@systemctl_path, "--user", "daemon-reload"])
      result(true, "complete", "Wazuh notification timer removed.", {"removed" => paths.values}, "deployment_state")
    rescue SystemCallError, IOError => error
      result(false, "failed", "Wazuh notification timer removal failed safely: #{error.class}.", {})
    end

    def rendered
      private_root = File.join(@root, "Soul", "private", "security", "wazuh")
      {
        SERVICE => <<~UNIT,
          [Unit]
          Description=Soul bounded Wazuh alert notification poll
          Wants=network-online.target
          After=network-online.target

          [Service]
          Type=oneshot
          WorkingDirectory=#{unit_path(@root)}
          ExecStart=#{unit_quote(@ruby_path)} #{unit_quote(poller_script)} --root #{unit_quote(@root)} --integration-file #{unit_quote(@integration_file)}
          TimeoutStartSec=45
          UMask=0077
          NoNewPrivileges=true
          PrivateTmp=true
          ProtectSystem=strict
          ProtectHome=read-only
          ReadWritePaths=#{unit_path(private_root)}
          ProtectControlGroups=true
          ProtectKernelModules=true
          ProtectKernelTunables=true
          RestrictSUIDSGID=true
          LockPersonality=true
          RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
        UNIT
        TIMER => <<~UNIT
          [Unit]
          Description=Poll bounded Wazuh alerts for durable local notification

          [Timer]
          OnBootSec=2min
          OnUnitActiveSec=60s
          AccuracySec=10s
          RandomizedDelaySec=10s
          Persistent=true
          Unit=#{SERVICE}

          [Install]
          WantedBy=timers.target
        UNIT
      }
    end

    private

    def poller_script = File.join(@root, "scripts", "poll-wazuh-alert-notifications")
    def paths = {SERVICE => File.join(@unit_root, SERVICE), TIMER => File.join(@unit_root, TIMER)}

    def installed_exact?
      rendered.all? do |name, content|
        path = File.join(@unit_root, name)
        safe_file?(path) && File.binread(path, 128 * 1024) == content
      end
    end

    def private_file?(path)
      File.file?(path) && !File.symlink?(path) && File.size(path).between?(1, 64 * 1024) && (File.stat(path).mode & 0o077).zero?
    end

    def safe_file?(path)
      File.file?(path) && !File.symlink?(path) && File.size(path) <= 128 * 1024
    end

    def write_atomic(path, content, mode)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def capture(command)
      stdout, stderr, status = Open3.capture3(*command)
      {"success" => status.success?, "stdout" => stdout, "stderr" => stderr}
    end

    def result(ok, lifecycle, reason, data, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => mutation}
    end

    def bounded(value) = value.to_s.byteslice(0, 4096).to_s
    def unit_path(value) = value.to_s.gsub(" ", "\\x20")
    def unit_quote(value) = "\"#{value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')}\""
  end
end
