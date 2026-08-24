# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "memory_core_aware_worker"

module SoulCore
  class MemoryCoreAwareWorkerDeployment
    SCHEMA = "soul.memory_core_aware_worker_deployment.a17.v1"
    CONFIRM_INSTALL = "INSTALL_SOUL_MEMORY_LIFECYCLE_TIMER"
    CONFIRM_UNINSTALL = "REMOVE_SOUL_MEMORY_LIFECYCLE_TIMER"
    SERVICE = "soul-memory-lifecycle.service"
    TIMER = "soul-memory-lifecycle.timer"

    def initialize(root: Dir.pwd, home: Dir.home, ruby_path: RbConfig.ruby,
                   systemctl_path: "/usr/bin/systemctl", runner: nil)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @ruby_path = File.expand_path(ruby_path)
      @systemctl_path = File.expand_path(systemctl_path)
      @runner = runner || method(:capture)
      @unit_root = File.join(@home, ".config", "systemd", "user")
    end

    def plan
      errors = []
      errors << "Ruby executable is unavailable" unless File.file?(@ruby_path) && File.executable?(@ruby_path)
      errors << "systemctl is unavailable" unless File.file?(@systemctl_path) && File.executable?(@systemctl_path)
      errors << "memory lifecycle worker command is unavailable" unless File.file?(worker_script) && File.executable?(worker_script)
      return result(false, "failed", errors.first, "errors" => errors) unless errors.empty?

      scope = plan_scope
      result(true, "blocked_for_human_review", "Review the exact Core-aware memory lifecycle timer.",
        scope.merge("confirmation_phrase" => CONFIRM_INSTALL, "expected_digest" => digest(scope)))
    end

    def install(confirmation:, expected_digest:)
      planned = plan
      return planned unless planned["ok"]
      data = planned.fetch("data")
      return result(false, "awaiting_input", "Exact timer installation confirmation and digest are required.", data) if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return result(false, "blocked_for_human_review", "Memory lifecycle timer plan changed; preview again.", data) unless confirmation == CONFIRM_INSTALL && secure_compare(expected_digest, data.fetch("expected_digest"))

      FileUtils.mkdir_p(@unit_root, mode: 0o700)
      rendered.each { |name, content| write_atomic(File.join(@unit_root, name), content, 0o644) }
      [[@systemctl_path, "--user", "daemon-reload"], [@systemctl_path, "--user", "enable", "--now", TIMER]].each do |command|
        execution = @runner.call(command)
        return result(false, "failed", "Memory lifecycle timer installation failed safely.", "stderr" => bounded(execution["stderr"])) unless execution["success"]
      end
      result(true, "complete", "Core-aware memory lifecycle timer installed.",
        { "timer" => TIMER, "installed_exact" => installed_exact? }, "deployment_state")
    rescue SystemCallError, IOError => error
      result(false, "failed", "Memory lifecycle timer installation failed safely: #{error.class}.", {})
    end

    def status
      execution = @runner.call([@systemctl_path, "--user", "show", TIMER,
        "--property=ActiveState,UnitFileState,NextElapseUSecRealtime", "--no-pager"])
      result(execution["success"], "complete", "Memory lifecycle timer status collected.",
        { "timer" => bounded(execution["stdout"]), "installed_exact" => installed_exact? })
    end

    def uninstall(confirmation:)
      return result(false, "awaiting_input", "Exact timer removal confirmation is required.",
        "confirmation_phrase" => CONFIRM_UNINSTALL) unless confirmation == CONFIRM_UNINSTALL
      @runner.call([@systemctl_path, "--user", "disable", "--now", TIMER])
      paths.each_value { |path| File.delete(path) if safe_file?(path) }
      @runner.call([@systemctl_path, "--user", "daemon-reload"])
      result(true, "complete", "Memory lifecycle timer removed.", { "removed" => paths.values }, "deployment_state")
    rescue SystemCallError, IOError => error
      result(false, "failed", "Memory lifecycle timer removal failed safely: #{error.class}.", {})
    end

    def rendered
      private_root = File.join(@root, "Soul", "private", "memory")
      runtime_root = File.join(@root, "Soul", "runtime", "model_runtime")
      {
        SERVICE => <<~UNIT,
          [Unit]
          Description=Soul bounded Core-aware memory lifecycle cycle
          After=default.target

          [Service]
          Type=oneshot
          WorkingDirectory=#{unit_path(@root)}
          ExecStart=#{unit_quote(@ruby_path)} #{unit_quote(worker_script)} run
          TimeoutStartSec=12min
          UMask=0077
          NoNewPrivileges=true
          PrivateTmp=true
          ProtectSystem=strict
          ProtectHome=read-only
          ReadWritePaths=#{unit_path(private_root)} #{unit_path(runtime_root)}
          ProtectControlGroups=true
          ProtectKernelModules=true
          ProtectKernelTunables=true
          RestrictSUIDSGID=true
          LockPersonality=true
          RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
        UNIT
        TIMER => <<~UNIT
          [Unit]
          Description=Schedule bounded Soul memory lifecycle cycles

          [Timer]
          OnBootSec=10min
          OnUnitInactiveSec=15min
          AccuracySec=1min
          RandomizedDelaySec=60s
          Persistent=false
          Unit=#{SERVICE}

          [Install]
          WantedBy=timers.target
        UNIT
      }
    end

    private

    def worker_script = File.join(@root, "scripts", "soul-memory-lifecycle-worker")
    def paths = { SERVICE => File.join(@unit_root, SERVICE), TIMER => File.join(@unit_root, TIMER) }
    def plan_scope
      { "schema" => SCHEMA, "files" => paths, "units" => rendered,
        "on_boot_seconds" => 600, "interval_seconds" => 900,
        "randomized_delay_seconds" => 60, "persistent" => false,
        "eligible_cores" => MemoryCoreAwareWorker::ELIGIBLE_CORES,
        "skipped_cores" => MemoryCoreAwareWorker::SKIPPED_CORES,
        "max_cycles_per_activation" => 1 }
    end
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value) + "\n")
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |sum, pair| sum | (pair[0] ^ pair[1]) }.zero?
    def installed_exact? = rendered.all? { |name, content| safe_file?(paths.fetch(name)) && File.binread(paths.fetch(name), 128 * 1024) == content }
    def safe_file?(path) = File.file?(path) && !File.symlink?(path) && File.size(path) <= 128 * 1024
    def bounded(value) = value.to_s.byteslice(0, 4096).to_s
    def unit_path(value) = value.to_s.gsub(" ", "\\x20")
    def unit_quote(value) = "\"#{value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')}\""

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
      { "success" => status.success?, "stdout" => stdout, "stderr" => stderr }
    end

    def result(ok, lifecycle, reason, data, mutation = "none")
      { "ok" => ok, "lifecycle_state" => lifecycle, "schema" => SCHEMA,
        "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
