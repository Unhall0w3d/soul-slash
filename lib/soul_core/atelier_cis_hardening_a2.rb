# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"

require_relative "bounded_command_runner"

module SoulCore
  class AtelierCisHardeningA2
    VERSION = "soul-atelier-cis-hardening-a2-v1"
    CONFIRM_INSTALL = "INSTALL_ATELIER_CIS_HARDENING_A2"
    CONFIRM_REMOVE = "REMOVE_ATELIER_CIS_HARDENING_A2"

    SYSCTL_PATH = "/etc/sysctl.d/70-soul-workstation-network.conf"
    AUDIT_PATH = "/etc/audit/rules.d/71-soul-mount-events.rules"
    PAM_PATH = "/etc/pam.d/su"

    SYSCTL_CONTENT = <<~CONF.freeze
      # Soul/ Atelier workstation hardening. Preserve forwarding; disable IPv4 redirects only.
      net.ipv4.conf.all.send_redirects = 0
      net.ipv4.conf.default.send_redirects = 0
      net.ipv4.conf.all.secure_redirects = 0
      net.ipv4.conf.default.secure_redirects = 0
    CONF

    AUDIT_CONTENT = <<~RULES.freeze
      ## Soul/ Atelier workstation hardening. User-originated filesystem mount events.
      -a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=unset -k mounts
      -a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=unset -k mounts
    RULES

    AUDIT_RULE_ARGUMENTS = %w[b64 b32].to_h do |arch|
      [arch, ["-a", "always,exit", "-F", "arch=#{arch}", "-S", "mount", "-F", "auid>=1000", "-F", "auid!=unset", "-k", "mounts"]]
    end.freeze

    PAM_ORIGINAL = <<~PAM.freeze
      #%PAM-1.0
      auth            sufficient      pam_rootok.so
      # Uncomment the following line to implicitly trust users in the "wheel" group.
      #auth           sufficient      pam_wheel.so trust use_uid
      # Uncomment the following line to require a user to be in the "wheel" group.
      #auth           required        pam_wheel.so use_uid
      auth            required        pam_unix.so
      account         required        pam_unix.so
      session	        required        pam_unix.so
      password        include         system-auth
    PAM

    PAM_RESTRICTED = PAM_ORIGINAL.sub(
      "#auth           required        pam_wheel.so use_uid",
      "auth            required        pam_wheel.so use_uid"
    ).freeze

    ManagedFile = Struct.new(:path, :mode, :content, keyword_init: true)

    def initialize(system_root: "/", runner: BoundedCommandRunner.new, euid: Process.euid)
      @system_root = File.expand_path(system_root)
      @runner = runner
      @euid = Integer(euid)
    end

    def plan
      basis = {
        "operation" => "atelier_cis_hardening_a2_install",
        "version" => VERSION,
        "implemented_controls" => [
          "disable IPv4 redirect sending and secure-redirect acceptance without changing forwarding",
          "audit user-originated filesystem mount syscalls",
          "restrict su authentication to wheel members"
        ],
        "already_effective" => ["dedicated rotated sudo command log"],
        "reviewed_exceptions" => [
          "periodic password aging and warning policy",
          "separate or restricted /var/tmp mount on the existing Omarchy Btrfs layout"
        ],
        "managed_files" => managed_files.map { |file| file_record(file) },
        "pam_transition" => {
          "path" => PAM_PATH,
          "required_current_sha256" => Digest::SHA256.hexdigest(PAM_ORIGINAL),
          "installed_sha256" => Digest::SHA256.hexdigest(PAM_RESTRICTED),
          "change" => "uncomment the existing required pam_wheel.so use_uid rule"
        },
        "ipv4_forwarding_changed" => false,
        "password_policy_changed" => false,
        "var_tmp_layout_changed" => false,
        "persistent_process_added" => false
      }
      outcome("blocked_for_human_review", "Review the exact Atelier A2 hardening plan.", basis.merge(
        "expected_digest" => Digest::SHA256.hexdigest(JSON.generate(basis)),
        "confirmation_phrase" => CONFIRM_INSTALL
      ))
    end

    def status
      files = managed_files.map { |file| inspect_file(file) }
      pam = inspect_pam
      runtime = runtime_status
      ready = files.all? { |entry| entry["state"] == "exact" } && pam["state"] == "exact" &&
        runtime.values.all? { |entry| entry["ok"] }
      outcome("complete", "Atelier A2 hardening status collected.", {
        "ready" => ready,
        "version" => VERSION,
        "files" => files,
        "pam" => pam,
        "runtime" => runtime
      })
    end

    def install(expected_digest:, confirmation:)
      authorize!(expected_digest, confirmation, CONFIRM_INSTALL)
      require_root!
      reject_collisions!
      validate_candidates!

      prior_sysctls = current_sysctls if live_root?
      installed = []
      pam_changed = false
      added_audit = []
      managed_files.each do |file|
        next if inspect_file(file)["state"] == "exact"

        atomic_install(file)
        installed << file
      end
      if inspect_pam["state"] == "baseline"
        atomic_write(PAM_PATH, 0o644, PAM_RESTRICTED)
        pam_changed = true
      end
      added_audit = activate! if live_root?
      result = status
      raise "Atelier A2 hardening failed exact post-install verification" unless result.dig("data", "ready")

      outcome("complete", "Atelier A2 hardening installed and verified.", result.fetch("data"), "host_hardening_installed")
    rescue StandardError
      rollback(installed, pam_changed, prior_sysctls, added_audit) if defined?(installed)
      raise
    end

    def remove(expected_digest:, confirmation:)
      authorize!(expected_digest, confirmation, CONFIRM_REMOVE)
      require_root!
      drifted = managed_files.filter_map do |file|
        state = inspect_file(file)["state"]
        file.path unless %w[missing exact].include?(state)
      end
      raise "refusing to remove drifted A2 files: #{drifted.join(', ')}" unless drifted.empty?
      raise "refusing to restore drifted PAM configuration" unless %w[baseline exact].include?(inspect_pam["state"])

      managed_files.each { |file| unlink_exact(file) }
      atomic_write(PAM_PATH, 0o644, PAM_ORIGINAL) if inspect_pam["state"] == "exact"
      if live_root?
        run("/usr/bin/sysctl", "-w", "net.ipv4.conf.all.send_redirects=1")
        run("/usr/bin/sysctl", "-w", "net.ipv4.conf.default.send_redirects=1")
        run("/usr/bin/sysctl", "-w", "net.ipv4.conf.all.secure_redirects=1")
        run("/usr/bin/sysctl", "-w", "net.ipv4.conf.default.secure_redirects=1")
        deactivate_mount_audit!(AUDIT_RULE_ARGUMENTS.keys)
        generate_audit_rules!
      end
      outcome("complete", "Atelier A2 hardening removed and the reviewed PAM baseline restored.", {}, "host_hardening_removed")
    end

    private

    def managed_files
      @managed_files ||= [
        ManagedFile.new(path: SYSCTL_PATH, mode: 0o644, content: SYSCTL_CONTENT),
        ManagedFile.new(path: AUDIT_PATH, mode: 0o640, content: AUDIT_CONTENT)
      ]
    end

    def file_record(file)
      {"path" => file.path, "mode" => format("%04o", file.mode), "sha256" => Digest::SHA256.hexdigest(file.content)}
    end

    def authorize!(digest, confirmation, phrase)
      raise "reviewed A2 plan digest changed" unless secure_equal?(digest.to_s, plan.dig("data", "expected_digest"))
      raise "exact A2 hardening confirmation is required" unless confirmation.to_s == phrase
    end

    def require_root!
      raise "Atelier A2 hardening requires root" unless @euid.zero?
    end

    def reject_collisions!
      collisions = managed_files.filter_map do |file|
        state = inspect_file(file)["state"]
        file.path unless %w[missing exact].include?(state)
      end
      raise "managed A2 path collision: #{collisions.join(', ')}" unless collisions.empty?
      raise "PAM su configuration does not match the reviewed baseline" unless %w[baseline exact].include?(inspect_pam["state"])
    end

    def validate_candidates!
      raise "PAM restriction is not exact" unless PAM_RESTRICTED.lines.count { |line| line.match?(/^auth\s+required\s+pam_wheel\.so\s+use_uid\s*$/) } == 1
      raise "PAM restriction accidentally enables wheel trust" if PAM_RESTRICTED.match?(/^auth\s+sufficient\s+pam_wheel\.so/m)
      raise "sysctl candidate changes forwarding" if SYSCTL_CONTENT.include?("ip_forward")
      raise "mount audit candidate is incomplete" unless %w[b64 b32].all? { |arch| AUDIT_CONTENT.include?("arch=#{arch} -S mount") }
    end

    def activate!
      sysctl = run("/usr/bin/sysctl", "--load=#{SYSCTL_PATH}", timeout: 10)
      raise "sysctl activation failed" unless sysctl.success?
      generate_audit_rules!
      activate_mount_audit!
    end

    def generate_audit_rules!
      result = run("/usr/bin/augenrules", timeout: 20)
      return if result.success?

      detail = [result.stderr, result.stdout].map(&:to_s).join(" ").gsub(/\s+/, " ").strip.byteslice(0, 500)
      raise "audit rule generation failed: #{detail}"
    end

    def activate_mount_audit!
      existing = active_audit_rules
      added = []
      AUDIT_RULE_ARGUMENTS.each do |arch, arguments|
        already_active = existing.lines.any? do |line|
          line.include?("arch=#{arch}") && line.include?("-S mount") && line.match?(/(?:key=mounts|-k mounts)/)
        end
        next if already_active

        result = run("/usr/bin/auditctl", *arguments, timeout: 10)
        raise "#{arch} mount audit activation failed" unless result.success?
        added << arch
      end
      added
    rescue StandardError
      deactivate_mount_audit!(added)
      raise
    end

    def deactivate_mount_audit!(arches)
      Array(arches).reverse_each do |arch|
        arguments = AUDIT_RULE_ARGUMENTS.fetch(arch).dup
        arguments[0] = "-d"
        run("/usr/bin/auditctl", *arguments, timeout: 10)
      end
    end

    def active_audit_rules
      result = run("/usr/bin/auditctl", "-l", timeout: 10)
      raise "unable to inspect active audit rules" unless result.success?

      result.stdout.to_s
    end

    def runtime_status
      return fixture_runtime_status unless live_root?

      audit = run("/usr/bin/auditctl", "-l", timeout: 10)
      rules = audit.stdout.to_s
      values = current_sysctls
      {
        "redirects_disabled" => {"ok" => values.values.all? { |value| value == "0" }},
        "ipv4_forwarding_preserved" => {"ok" => current_sysctl("net.ipv4.ip_forward") == "1"},
        "mount_audit_active" => {"ok" => audit.success? && %w[b64 b32].all? { |arch|
          rules.lines.any? { |line| line.include?("arch=#{arch}") && line.include?("-S mount") && line.match?(/(?:key=mounts|-k mounts)/) }
        }},
        "su_restricted_to_wheel" => {"ok" => inspect_pam["state"] == "exact"}
      }
    end

    def fixture_runtime_status
      exact = managed_files.all? { |file| inspect_file(file)["state"] == "exact" } && inspect_pam["state"] == "exact"
      %w[redirects_disabled ipv4_forwarding_preserved mount_audit_active su_restricted_to_wheel].to_h do |key|
        [key, {"ok" => exact}]
      end
    end

    def current_sysctls
      %w[
        net.ipv4.conf.all.send_redirects
        net.ipv4.conf.default.send_redirects
        net.ipv4.conf.all.secure_redirects
        net.ipv4.conf.default.secure_redirects
      ].to_h { |key| [key, current_sysctl(key)] }
    end

    def current_sysctl(key)
      result = run("/usr/bin/sysctl", "-n", key, timeout: 5)
      raise "unable to read sysctl #{key}" unless result.success?

      result.stdout.to_s.strip
    end

    def inspect_file(file)
      absolute = system_path(file.path)
      return file_record(file).merge("state" => "missing") unless File.exist?(absolute) || File.symlink?(absolute)
      return file_record(file).merge("state" => "unsafe_symlink") if File.symlink?(absolute)
      return file_record(file).merge("state" => "not_regular") unless File.file?(absolute)

      stat = File.stat(absolute)
      exact = File.binread(absolute) == file.content && (stat.mode & 0o777) == file.mode
      exact &&= stat.uid.zero? && stat.gid.zero? if live_root?
      file_record(file).merge("state" => exact ? "exact" : "drifted")
    rescue Errno::EACCES
      file_record(file).merge("state" => "permission_denied")
    end

    def inspect_pam
      path = system_path(PAM_PATH)
      return {"path" => PAM_PATH, "state" => "missing"} unless File.exist?(path) || File.symlink?(path)
      return {"path" => PAM_PATH, "state" => "unsafe_symlink"} if File.symlink?(path)
      return {"path" => PAM_PATH, "state" => "not_regular"} unless File.file?(path)

      content = File.binread(path)
      state = if content == PAM_RESTRICTED
                "exact"
              elsif content == PAM_ORIGINAL
                "baseline"
              else
                "drifted"
              end
      {"path" => PAM_PATH, "state" => state, "sha256" => Digest::SHA256.hexdigest(content)}
    rescue Errno::EACCES
      {"path" => PAM_PATH, "state" => "permission_denied"}
    end

    def atomic_install(file)
      atomic_write(file.path, file.mode, file.content)
    end

    def atomic_write(path, mode, content)
      destination = system_path(path)
      directory = File.dirname(destination)
      FileUtils.mkdir_p(directory, mode: 0o755)
      raise "managed directory is unsafe: #{path}" if File.symlink?(directory)

      temporary = File.join(directory, ".#{File.basename(destination)}.soul-#{Process.pid}-#{SecureRandom.hex(6)}")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |handle|
        handle.write(content)
        handle.flush
        handle.fsync
      end
      File.chown(0, 0, temporary) if live_root?
      File.chmod(mode, temporary)
      File.rename(temporary, destination)
      File.open(directory, File::RDONLY) { |handle| handle.fsync }
    ensure
      File.unlink(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def unlink_exact(file)
      path = system_path(file.path)
      File.unlink(path) if inspect_file(file)["state"] == "exact"
    end

    def rollback(installed, pam_changed, prior_sysctls, added_audit)
      Array(installed).reverse_each { |file| unlink_exact(file) }
      atomic_write(PAM_PATH, 0o644, PAM_ORIGINAL) if pam_changed && inspect_pam["state"] == "exact"
      if live_root?
        prior_sysctls.to_h.each { |key, value| run("/usr/bin/sysctl", "-w", "#{key}=#{value}") }
        deactivate_mount_audit!(added_audit)
        generate_audit_rules!
      end
    rescue StandardError
      nil
    end

    def system_path(path)
      candidate = File.expand_path(path.delete_prefix("/"), @system_root)
      prefix = @system_root == "/" ? "/" : "#{@system_root}/"
      raise "managed path escapes system root" unless candidate.start_with?(prefix) && candidate != @system_root

      candidate
    end

    def live_root?
      @system_root == "/" && @euid.zero?
    end

    def run(*argv, timeout: 10)
      @runner.run(argv, timeout_seconds: timeout, max_output_bytes: 64 * 1024)
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def outcome(state, reason, data = {}, mutation = "none")
      {"ok" => true, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation}
    end
  end
end
