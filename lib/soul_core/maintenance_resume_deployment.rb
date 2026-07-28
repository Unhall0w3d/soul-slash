# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"

module SoulCore
  class MaintenanceResumeDeployment
    UNIT_NAME = "soul-maintenance-resume.service"
    CONFIRM_INSTALL = "INSTALL_SOUL_MAINTENANCE_RESUME"
    CONFIRM_UNINSTALL = "REMOVE_SOUL_MAINTENANCE_RESUME"

    def initialize(
      root: Dir.pwd,
      home: Dir.home,
      ruby_path: "/usr/bin/ruby",
      systemctl_path: "/usr/bin/systemctl",
      command_runner: nil
    )
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @ruby_path = File.expand_path(ruby_path)
      @systemctl_path = systemctl_path
      @command_runner = command_runner || method(:capture)
      @unit_path = File.join(@home, ".config", "systemd", "user", UNIT_NAME)
    end

    def plan
      errors = []
      errors << "Ruby executable is unavailable" unless File.file?(@ruby_path) && File.executable?(@ruby_path)
      errors << "systemctl is unavailable" unless File.file?(@systemctl_path) && File.executable?(@systemctl_path)
      errors << "maintenance resume entrypoint is unavailable" unless File.file?(resume_script)
      return result(false, "failed", errors.first, {"errors" => errors}) unless errors.empty?

      result(true, "blocked_for_human_review", "Review the exact one-shot resume unit before installation.", {
        "unit_name" => UNIT_NAME,
        "unit_path" => @unit_path,
        "unit" => unit_content,
        "confirmation_phrase" => CONFIRM_INSTALL,
        "persistent_process" => false,
        "restart_policy" => "none",
        "timer" => false
      })
    end

    def install(confirmation:)
      planned = plan
      return planned unless planned["ok"]
      return result(false, "awaiting_input", "Exact resume-unit installation confirmation is required.", planned["details"]) unless confirmation == CONFIRM_INSTALL

      ensure_private_directory(File.dirname(@unit_path))
      atomic_write(@unit_path, unit_content, 0o600)
      %w[daemon-reload].each do |action|
        execution = run(@systemctl_path, "--user", action)
        return result(false, "failed", "systemd user manager reload failed safely.", {"stderr" => bounded(execution["stderr"])}) unless execution["success"]
      end
      enabled = run(@systemctl_path, "--user", "enable", UNIT_NAME)
      return result(false, "failed", "one-shot resume unit could not be enabled.", {"stderr" => bounded(enabled["stderr"])}) unless enabled["success"]

      result(true, "complete", "One-shot maintenance resume unit installed and enabled.", status["details"], mutation: "local_service_configuration")
    rescue SystemCallError, IOError => error
      result(false, "failed", "resume-unit installation failed safely: #{error.class}", {})
    end

    def uninstall(confirmation:)
      return result(false, "awaiting_input", "Exact resume-unit removal confirmation is required.", {"confirmation_phrase" => CONFIRM_UNINSTALL}) unless confirmation == CONFIRM_UNINSTALL
      run(@systemctl_path, "--user", "disable", "--now", UNIT_NAME)
      FileUtils.rm_f(@unit_path) if File.file?(@unit_path) && !File.symlink?(@unit_path)
      run(@systemctl_path, "--user", "daemon-reload")
      result(true, "complete", "One-shot maintenance resume unit removed.", {"unit_path" => @unit_path}, mutation: "local_service_configuration")
    end

    def status
      exact = File.file?(@unit_path) && !File.symlink?(@unit_path) &&
        File.size(@unit_path) <= 64 * 1024 && File.binread(@unit_path, 64 * 1024) == unit_content
      enabled = run(@systemctl_path, "--user", "is-enabled", UNIT_NAME)
      enabled_exact = enabled["success"] && enabled["stdout"].to_s.strip == "enabled"
      enabled_exact ||= enabled_symlink_exact?
      result(true, "complete", "One-shot maintenance resume status collected.", {
        "unit_name" => UNIT_NAME,
        "unit_path" => @unit_path,
        "installed_exact" => exact,
        "enabled" => enabled_exact,
        "ready" => exact && enabled_exact,
        "persistent_process" => false,
        "restart_policy" => "none",
        "timer" => false
      })
    end

    def unit_content
      <<~UNIT
        [Unit]
        Description=Soul one-shot maintenance workspace restoration
        After=graphical-session.target
        ConditionPathExists=#{unit_path(pending_journal)}

        [Service]
        Type=oneshot
        WorkingDirectory=#{unit_path(@root)}
        ExecStart=#{unit_quote(@ruby_path)} #{unit_quote(resume_script)} --root #{unit_quote(@root)}
        TimeoutStartSec=600
        UMask=0077
        NoNewPrivileges=true
        PrivateTmp=true
        ProtectSystem=strict
        ReadWritePaths=#{unit_path(File.join(@root, "Soul", "private", "host_maintenance"))}
        ProtectControlGroups=true
        ProtectKernelModules=true
        ProtectKernelTunables=true
        RestrictSUIDSGID=true
        LockPersonality=true
        RestrictAddressFamilies=AF_UNIX

        [Install]
        WantedBy=default.target
      UNIT
    end

    private

    def resume_script = File.join(@root, "scripts", "soul-maintenance-resume")
    def pending_journal = File.join(@root, "Soul", "private", "host_maintenance", "pending_restore.json")

    def enabled_symlink_exact?
      link = File.join(@home, ".config", "systemd", "user", "default.target.wants", UNIT_NAME)
      File.symlink?(link) && File.realpath(link) == File.realpath(@unit_path)
    rescue SystemCallError
      false
    end

    def ensure_private_directory(directory)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise IOError, "resume-unit directory is unsafe" if File.symlink?(directory)
      File.chmod(0o700, directory)
    end

    def atomic_write(path, content, mode)
      raise IOError, "refusing symlink destination" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def capture(argv)
      stdout, stderr, status = Open3.capture3(*argv)
      {"success" => status.success?, "stdout" => stdout, "stderr" => stderr}
    end

    def run(*argv)
      @command_runner.call(argv)
    rescue SystemCallError => error
      {"success" => false, "stdout" => "", "stderr" => error.class.to_s}
    end

    def bounded(value) = value.to_s.byteslice(0, 4_096).to_s
    def unit_quote(value) = %Q{"#{value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')}"}

    def unit_path(value)
      value.to_s.bytes.map do |byte|
        character = byte.chr
        character.match?(/[A-Za-z0-9_.\/-]/) ? character : format("\\x%02x", byte)
      end.join
    end

    def result(ok, lifecycle, reason, details, mutation: "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "details" => details, "data" => details, "mutation" => ok ? mutation : "none"}
    end
  end
end
