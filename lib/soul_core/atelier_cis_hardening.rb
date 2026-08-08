# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "tmpdir"

require_relative "bounded_command_runner"

module SoulCore
  class AtelierCisHardening
    VERSION = "soul-atelier-cis-hardening-a1-v1"
    CONFIRM_INSTALL = "INSTALL_ATELIER_CIS_HARDENING"
    CONFIRM_REMOVE = "REMOVE_ATELIER_CIS_HARDENING"
    MAX_OUTPUT_BYTES = 64 * 1024

    ManagedFile = Struct.new(:path, :mode, :content, keyword_init: true)

    def initialize(system_root: "/", runner: BoundedCommandRunner.new, euid: Process.euid)
      @system_root = File.expand_path(system_root)
      @runner = runner
      @euid = Integer(euid)
    end

    def plan
      files = managed_files
      basis = {
        "operation" => "atelier_cis_hardening_install",
        "version" => VERSION,
        "implemented_controls" => [
          "dedicated rotated sudo command log",
          "explicit DCCP module deny",
          "DAC permission and ownership audit events",
          "failed unauthorized file-access audit events",
          "file deletion and rename audit events"
        ],
        "reviewed_exceptions" => [
          "periodic password expiration",
          "minimum password age",
          "password-expiration warning",
          "SELinux or AppArmor policy auditing on a host where neither MAC framework is active"
        ],
        "managed_files" => files.map do |file|
          {
            "path" => file.path,
            "mode" => format("%04o", file.mode),
            "sha256" => Digest::SHA256.hexdigest(file.content)
          }
        end,
        "retained_log" => "/var/log/sudo.log",
        "password_storage" => false,
        "passwordless_authority" => false,
        "arbitrary_command_forwarding" => false,
        "persistent_process_added" => false
      }
      digest = Digest::SHA256.hexdigest(JSON.generate(basis))
      outcome("blocked_for_human_review", true, "Review the exact Atelier CIS hardening plan.", basis.merge(
        "expected_digest" => digest,
        "confirmation_phrase" => CONFIRM_INSTALL
      ))
    end

    def status
      file_results = managed_files.map { |file| inspect_file(file) }
      commands = command_status
      ready = file_results.all? { |entry| entry.fetch("state") == "exact" } &&
        commands.values.all? { |entry| entry.fetch("ok") }
      outcome("complete", true, "Atelier CIS hardening status collected.", {
        "ready" => ready,
        "version" => VERSION,
        "files" => file_results,
        "runtime" => commands,
        "reviewed_exception_count" => 4,
        "implemented_control_count" => 5
      })
    end

    def install(expected_digest:, confirmation:)
      authorize!(expected_digest, confirmation, CONFIRM_INSTALL)
      require_root!
      collisions = managed_files.filter_map do |file|
        state = inspect_file(file).fetch("state")
        file.path unless %w[missing exact].include?(state)
      end
      raise "managed hardening path collision: #{collisions.join(', ')}" unless collisions.empty?

      validate_candidate_files!
      installed = []
      managed_files.each do |file|
        next if inspect_file(file).fetch("state") == "exact"

        atomic_install(file)
        installed << file
      end
      ensure_sudo_log
      validate_installed_files!
      if @system_root == "/"
        audit_load = run("/usr/bin/augenrules", "--load", timeout: 20)
        raise "audit rule load failed: #{safe_error(audit_load)}" unless audit_load.success?
      end

      result = status
      raise "Atelier CIS hardening did not pass exact post-install verification" unless result.dig("data", "ready")

      outcome("complete", true, "Atelier CIS hardening installed and verified.", result.fetch("data"), "host_hardening_installed")
    rescue StandardError
      rollback_new_files(installed) if defined?(installed)
      raise
    end

    def remove(expected_digest:, confirmation:)
      authorize!(expected_digest, confirmation, CONFIRM_REMOVE)
      require_root!
      drifted = managed_files.filter_map do |file|
        state = inspect_file(file).fetch("state")
        file.path unless %w[missing exact].include?(state)
      end
      raise "refusing to remove drifted hardening paths: #{drifted.join(', ')}" unless drifted.empty?

      managed_files.each do |file|
        absolute = system_path(file.path)
        File.unlink(absolute) if File.file?(absolute) && !File.symlink?(absolute)
      end
      if @system_root == "/"
        audit_load = run("/usr/bin/augenrules", "--load", timeout: 20)
        raise "audit rule reload failed after removal: #{safe_error(audit_load)}" unless audit_load.success?
      end

      outcome("complete", true, "Atelier CIS hardening configuration removed; retained sudo evidence was not deleted.", {
        "retained_log" => "/var/log/sudo.log"
      }, "host_hardening_removed")
    end

    private

    def managed_files
      @managed_files ||= [
        ManagedFile.new(
          path: "/etc/sudoers.d/85-soul-sudo-audit",
          mode: 0o440,
          content: <<~SUDOERS
            # Soul/ Atelier CIS hardening A1. Generated; do not edit.
            Defaults logfile="/var/log/sudo.log"
          SUDOERS
        ),
        ManagedFile.new(
          path: "/etc/logrotate.d/soul-sudo-audit",
          mode: 0o644,
          content: <<~LOGROTATE
            /var/log/sudo.log {
                weekly
                rotate 8
                maxsize 8M
                compress
                delaycompress
                missingok
                notifempty
                create 0600 root root
            }
          LOGROTATE
        ),
        ManagedFile.new(
          path: "/etc/modprobe.d/soul-disable-dccp.conf",
          mode: 0o644,
          content: <<~MODPROBE
            # Soul/ Atelier CIS hardening A1. DCCP is not required on this workstation.
            install dccp /bin/false
            blacklist dccp
          MODPROBE
        ),
        ManagedFile.new(
          path: "/etc/audit/rules.d/70-soul-workstation-events.rules",
          mode: 0o640,
          content: audit_rules
        )
      ]
    end

    def audit_rules
      <<~RULES
        ## Soul/ Atelier CIS hardening A1. User-originated file security events.
        -a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -k perm_mod
        -a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -k perm_mod
        -a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=unset -k perm_mod
        -a always,exit -F arch=b32 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=unset -k perm_mod
        -a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -k perm_mod
        -a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -k perm_mod

        -a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
        -a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
        -a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access
        -a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access

        -a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -k delete
        -a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -k delete
      RULES
    end

    def authorize!(expected_digest, confirmation, phrase)
      expected = plan.dig("data", "expected_digest")
      raise "reviewed hardening plan digest changed" unless secure_equal?(expected_digest, expected)
      raise "exact hardening confirmation is required" unless confirmation.to_s == phrase
    end

    def require_root!
      raise "Atelier CIS hardening requires root" unless @euid.zero?
    end

    def validate_candidate_files!
      temp_root = Dir.mktmpdir("soul-atelier-cis")
      begin
        sudoers = managed_files.find { |file| file.path.include?("sudoers.d") }
        logrotate = managed_files.find { |file| file.path.include?("logrotate.d") }
        sudoers_path = File.join(temp_root, "sudoers")
        logrotate_path = File.join(temp_root, "logrotate")
        File.binwrite(sudoers_path, sudoers.content)
        File.binwrite(logrotate_path, logrotate.content)
        result = run("/usr/bin/visudo", "-cf", sudoers_path)
        raise "sudoers candidate is invalid: #{safe_error(result)}" unless result.success?
        result = run("/usr/bin/logrotate", "--debug", logrotate_path)
        raise "logrotate candidate is invalid: #{safe_error(result)}" unless result.success?
      ensure
        FileUtils.remove_entry_secure(temp_root) if temp_root && File.directory?(temp_root)
      end
    end

    def validate_installed_files!
      sudoers = system_path("/etc/sudoers.d/85-soul-sudo-audit")
      logrotate = system_path("/etc/logrotate.d/soul-sudo-audit")
      result = run("/usr/bin/visudo", "-cf", sudoers)
      raise "installed sudoers policy is invalid: #{safe_error(result)}" unless result.success?
      result = run("/usr/bin/logrotate", "--debug", logrotate)
      raise "installed logrotate policy is invalid: #{safe_error(result)}" unless result.success?
    end

    def command_status
      return fixture_command_status unless @system_root == "/" && @euid.zero?

      modprobe = run("/usr/bin/modprobe", "-n", "-v", "dccp")
      audit = run("/usr/bin/auditctl", "-l")
      sudoers = run("/usr/bin/visudo", "-cf", "/etc/sudoers.d/85-soul-sudo-audit")
      logrotate = run("/usr/bin/logrotate", "--debug", "/etc/logrotate.d/soul-sudo-audit")
      rules = audit.stdout.to_s
      {
        "dccp_denied" => command_entry(modprobe.success? && modprobe.stdout.include?("install /bin/false"), modprobe),
        "sudoers_valid" => command_entry(sudoers.success?, sudoers),
        "logrotate_valid" => command_entry(logrotate.success?, logrotate),
        "audit_perm_mod_active" => command_entry(audit.success? && rules.include?("key=perm_mod"), audit),
        "audit_failed_access_active" => command_entry(audit.success? && rules.include?("key=access"), audit),
        "audit_delete_active" => command_entry(audit.success? && rules.include?("key=delete"), audit)
      }
    end

    def fixture_command_status
      exact = managed_files.all? { |file| inspect_file(file).fetch("state") == "exact" }
      %w[dccp_denied sudoers_valid logrotate_valid audit_perm_mod_active audit_failed_access_active audit_delete_active].to_h do |key|
        [key, {"ok" => exact, "state" => exact ? "verified" : "unavailable"}]
      end
    end

    def command_entry(ok, result)
      {"ok" => ok, "state" => ok ? "verified" : "unavailable", "exit_status" => result.exit_status}
    end

    def inspect_file(file)
      absolute = system_path(file.path)
      return file_result(file, "missing") unless File.exist?(absolute) || File.symlink?(absolute)
      return file_result(file, "unsafe_symlink") if File.symlink?(absolute)
      return file_result(file, "not_regular") unless File.file?(absolute)

      stat = File.stat(absolute)
      exact = File.binread(absolute) == file.content && (stat.mode & 0o777) == file.mode
      exact &&= stat.uid.zero? && stat.gid.zero? if @system_root == "/"
      file_result(file, exact ? "exact" : "drifted")
    rescue Errno::EACCES
      file_result(file, "permission_denied")
    end

    def file_result(file, state)
      {"path" => file.path, "state" => state, "expected_mode" => format("%04o", file.mode), "expected_sha256" => Digest::SHA256.hexdigest(file.content)}
    end

    def atomic_install(file)
      destination = system_path(file.path)
      directory = File.dirname(destination)
      FileUtils.mkdir_p(directory, mode: 0o755)
      raise "managed directory is unsafe: #{file.path}" if File.symlink?(directory)

      temporary = File.join(directory, ".#{File.basename(destination)}.soul-#{Process.pid}-#{SecureRandom.hex(6)}")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, file.mode) do |handle|
        handle.write(file.content)
        handle.flush
        handle.fsync
      end
      File.chown(0, 0, temporary) if @system_root == "/"
      File.chmod(file.mode, temporary)
      File.rename(temporary, destination)
      fsync_directory(directory)
    ensure
      File.unlink(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def ensure_sudo_log
      path = system_path("/var/log/sudo.log")
      return if File.file?(path) && !File.symlink?(path)
      raise "sudo log path is unsafe" if File.exist?(path) || File.symlink?(path)

      FileUtils.mkdir_p(File.dirname(path), mode: 0o755)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |handle| handle.fsync }
      File.chown(0, 0, path) if @system_root == "/"
      File.chmod(0o600, path)
    end

    def rollback_new_files(files)
      Array(files).reverse_each do |file|
        absolute = system_path(file.path)
        next unless File.file?(absolute) && !File.symlink?(absolute)
        next unless File.binread(absolute) == file.content

        File.unlink(absolute)
      end
      run("/usr/bin/augenrules", "--load", timeout: 20) if @system_root == "/" && @euid.zero?
    rescue StandardError
      nil
    end

    def system_path(path)
      relative = path.delete_prefix("/")
      candidate = File.expand_path(relative, @system_root)
      prefix = @system_root == "/" ? "/" : "#{@system_root}/"
      raise "managed path escaped system root" unless candidate.start_with?(prefix)

      candidate
    end

    def fsync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::EINVAL, Errno::EISDIR
      nil
    end

    def run(*argv, timeout: 10)
      @runner.run(*argv, timeout_seconds: timeout, max_output_bytes: MAX_OUTPUT_BYTES, env: {"LC_ALL" => "C"})
    end

    def safe_error(result)
      text = [result.stderr, result.stdout].join(" ").strip.gsub(/\s+/, " ")
      text.empty? ? result.status.to_s : text[0, 400]
    end

    def secure_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == 64 && right.bytesize == 64

      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def outcome(lifecycle, ok, reason, data = {}, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => ok ? mutation : "none"}
    end
  end
end
