# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "json"
require "open3"
require "securerandom"

module SoulCore
  class MaintenancePasswordlessAuthority
    CONFIRM_INSTALL = "INSTALL_SOUL_MAINTENANCE_AUTHORITY"
    CONFIRM_REMOVE = "REMOVE_SOUL_MAINTENANCE_AUTHORITY"
    HELPER_PATH = "/usr/local/libexec/soul-maintenance-authority"
    SUDOERS_PATH = "/etc/sudoers.d/90-soul-maintenance-authority"
    HELPER_VERSION = "soul-maintenance-authority-a4-v3"
    TRANSACTION_PATTERN = "maintenance_tx_[a-f0-9]{16}"
    SUPPORTED_YAY_VERSION = "13.0.1"
    FIXED_PATHS = {
      "sudo" => "/usr/bin/sudo",
      "ruby" => "/usr/bin/ruby",
      "yay" => "/usr/bin/yay",
      "pacman" => "/usr/bin/pacman",
      "flatpak" => "/usr/bin/flatpak",
      "systemctl" => "/usr/bin/systemctl",
      "makepkg" => "/usr/bin/makepkg",
      "git" => "/usr/bin/git",
      "gpg" => "/usr/bin/gpg",
      "false" => "/usr/bin/false",
      "visudo" => "/usr/bin/visudo",
      "install" => "/usr/bin/install",
      "mv" => "/usr/bin/mv",
      "rm" => "/usr/bin/rm"
    }.freeze

    attr_reader :root, :owner_uid, :owner_gid, :owner_name, :hostname, :home

    def initialize(
      root: Dir.pwd,
      owner_uid: Process.uid,
      owner_name: nil,
      hostname: nil,
      home: nil,
      command_runner: nil
    )
      @root = File.expand_path(root)
      @owner_uid = Integer(owner_uid)
      passwd = Etc.getpwuid(@owner_uid)
      @owner_gid = Integer(passwd.gid)
      @owner_name = (owner_name || passwd.name).to_s
      @home = File.expand_path(home || passwd.dir)
      @hostname = (hostname || File.read("/proc/sys/kernel/hostname", 256).strip).to_s
      @command_runner = command_runner || method(:capture)
      validate_identity!
    end

    def plan
      problems = required_path_problems
      problems << "yay #{SUPPORTED_YAY_VERSION} is required" unless yay_version == SUPPORTED_YAY_VERSION
      helper = helper_content
      helper_digest = Digest::SHA256.hexdigest(helper)
      sudoers = sudoers_content(helper_digest)
      basis = {
        "operation" => "maintenance_passwordless_authority_install",
        "version" => HELPER_VERSION,
        "owner_uid" => @owner_uid,
        "owner_gid" => @owner_gid,
        "owner_name" => @owner_name,
        "hostname" => @hostname,
        "project_root" => @root,
        "helper_path" => HELPER_PATH,
        "helper_mode" => "0755",
        "helper_sha256" => helper_digest,
        "sudoers_path" => SUDOERS_PATH,
        "sudoers_mode" => "0440",
        "sudoers_sha256" => Digest::SHA256.hexdigest(sudoers),
        "allowed_operations" => %w[self-check arch-update flatpak-system-update reboot],
        "yay_version" => yay_version,
        "password_storage" => false,
        "arbitrary_command_forwarding" => false,
        "persistent_process" => false
      }
      digest = Digest::SHA256.hexdigest(JSON.generate(basis))
      outcome(
        problems.empty? ? "blocked_for_human_review" : "failed",
        problems.empty?,
        problems.empty? ? "Review the exact root-owned maintenance authority before installation." : problems.first,
        basis.merge(
          "expected_digest" => digest,
          "confirmation_phrase" => CONFIRM_INSTALL,
          "helper_content" => helper,
          "sudoers_content" => sudoers,
          "problems" => problems
        )
      )
    end

    def status
      planned = plan
      return planned unless planned["ok"]
      expected = planned.fetch("data")
      helper_exact = regular_file_exact?(HELPER_PATH, expected.fetch("helper_sha256"), 0o755)
      probe = run(FIXED_PATHS.fetch("sudo"), "-n", HELPER_PATH, "self-check")
      parsed = JSON.parse(probe.fetch("stdout")) if probe["success"]
      native_verified = helper_exact && parsed.is_a?(Hash) &&
        parsed["version"] == HELPER_VERSION &&
        parsed["helper_sha256"] == expected.fetch("helper_sha256") &&
        parsed["owner_uid"] == @owner_uid &&
        parsed["hostname"] == @hostname
      confined = helper_exact && !probe["success"] &&
        probe.fetch("stderr", "").include?("no new privileges")
      ready = native_verified || confined
      outcome("complete", true, "Maintenance passwordless authority status collected.", {
        "ready" => ready,
        "helper_installed_exact" => helper_exact,
        "sudoers_authorization_exact" => native_verified,
        "authorization_verification" => native_verified ? "native_self_check" : (confined ? "deferred_to_native_handoff" : "unavailable"),
        "helper_path" => HELPER_PATH,
        "sudoers_path" => SUDOERS_PATH,
        "helper_sha256" => expected.fetch("helper_sha256"),
        "authority_mode" => ready ? "root_owned_passwordless" : "native_prompt",
        "probe_error" => native_verified ? "" : bounded(probe.fetch("stderr"))
      })
    rescue JSON::ParserError
      outcome("complete", true, "Maintenance passwordless authority status collected.", {
        "ready" => false,
        "helper_installed_exact" => false,
        "sudoers_authorization_exact" => false,
        "authority_mode" => "native_prompt",
        "probe_error" => "authority self-check returned invalid data"
      })
    end

    def install(expected_digest:, confirmation:)
      planned = plan
      return planned unless planned["ok"]
      data = planned.fetch("data")
      return outcome("blocked_for_human_review", false, "Review the current authority plan digest before installation.", data) unless secure_equal?(expected_digest, data.fetch("expected_digest"))
      return outcome("awaiting_input", false, "Exact authority installation confirmation is required.", data) unless confirmation == CONFIRM_INSTALL

      helper_temp = write_private_temp("helper", data.fetch("helper_content"), 0o700)
      sudoers_temp = write_private_temp("sudoers", data.fetch("sudoers_content"), 0o600)
      staged_sudoers = "#{SUDOERS_PATH}.new"
      commands = [
        [FIXED_PATHS.fetch("sudo"), "-v"],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("install"), "-d", "-o", "root", "-g", "root", "-m", "0755", File.dirname(HELPER_PATH)],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("install"), "-o", "root", "-g", "root", "-m", "0755", helper_temp, HELPER_PATH],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("install"), "-o", "root", "-g", "root", "-m", "0440", sudoers_temp, staged_sudoers],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("visudo"), "-cf", staged_sudoers],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("mv"), "-f", staged_sudoers, SUDOERS_PATH],
        [FIXED_PATHS.fetch("sudo"), "-k"]
      ]
      commands.each do |argv|
        result = @command_runner.call(argv)
        raise "authority installation command failed: #{File.basename(argv[1] || argv[0])}: #{bounded(result['stderr'])}" unless result["success"]
      end
      verified = status
      raise "installed authority did not pass exact self-check" unless verified.dig("data", "ready")
      outcome("complete", true, "Root-owned maintenance authority installed exactly.", verified.fetch("data"), "privileged_policy_installed")
    ensure
      FileUtils.rm_f(helper_temp) if defined?(helper_temp) && helper_temp
      FileUtils.rm_f(sudoers_temp) if defined?(sudoers_temp) && sudoers_temp
    end

    def uninstall(confirmation:)
      return outcome("awaiting_input", false, "Exact authority removal confirmation is required.", {"confirmation_phrase" => CONFIRM_REMOVE}) unless confirmation == CONFIRM_REMOVE
      commands = [
        [FIXED_PATHS.fetch("sudo"), "-v"],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("rm"), "-f", SUDOERS_PATH],
        [FIXED_PATHS.fetch("sudo"), FIXED_PATHS.fetch("rm"), "-f", HELPER_PATH],
        [FIXED_PATHS.fetch("sudo"), "-k"]
      ]
      commands.each do |argv|
        result = @command_runner.call(argv)
        raise "authority removal failed: #{bounded(result['stderr'])}" unless result["success"]
      end
      outcome("complete", true, "Root-owned maintenance authority removed.", {"ready" => false}, "privileged_policy_removed")
    end

    def command_for(operation, transaction_id)
      raise ArgumentError, "maintenance transaction ID is invalid" unless transaction_id.to_s.match?(/\A#{TRANSACTION_PATTERN}\z/)
      token = operation.to_s
      raise ArgumentError, "maintenance authority operation is invalid" unless %w[arch-update flatpak-system-update reboot].include?(token)
      [FIXED_PATHS.fetch("sudo"), "-n", HELPER_PATH, token, transaction_id]
    end

    def helper_content
      template = File.binread(File.join(@root, "scripts", "soul-maintenance-authority-root"))
      replacements = {
        "@@VERSION@@" => HELPER_VERSION,
        "@@PROJECT_ROOT@@" => @root,
        "@@OWNER_UID@@" => @owner_uid.to_s,
        "@@OWNER_GID@@" => @owner_gid.to_s,
        "@@OWNER_NAME@@" => @owner_name,
        "@@OWNER_HOME@@" => @home,
        "@@HOSTNAME@@" => @hostname,
        "@@YAY_VERSION@@" => SUPPORTED_YAY_VERSION
      }
      replacements.each { |token, value| template = template.gsub(token, ruby_literal(value)) }
      raise "authority helper template has unresolved tokens" if template.include?("@@")
      template
    end

    def sudoers_content(helper_digest = Digest::SHA256.hexdigest(helper_content))
      commands = [
        "#{HELPER_PATH} self-check",
        "#{HELPER_PATH} arch-update maintenance_tx_*",
        "#{HELPER_PATH} pacman-bridge maintenance_tx_* *",
        "#{HELPER_PATH} flatpak-system-update maintenance_tx_*",
        "#{HELPER_PATH} reboot maintenance_tx_*"
      ]
      entries = commands.map { |command| "sha256:#{helper_digest} #{command}" }.join(", \\\n    ")
      <<~SUDOERS
        # Soul/ A4 fixed-operation maintenance authority. Generated; do not edit.
        Defaults!#{HELPER_PATH} env_reset, secure_path=/usr/local/sbin:/usr/local/bin:/usr/bin
        #{@owner_name} #{@hostname} = (root) NOPASSWD: #{entries}
      SUDOERS
    end

    private

    def validate_identity!
      raise ArgumentError, "maintenance owner name is invalid" unless @owner_name.match?(/\A[a-z_][a-z0-9_-]*\z/i)
      raise ArgumentError, "maintenance hostname is invalid" unless @hostname.match?(/\A[a-z0-9][a-z0-9._-]*\z/i)
      stat = File.lstat(@root)
      raise ArgumentError, "maintenance project root is unsafe" unless
        @root.start_with?("/") && @root != "/" && !@root.include?("\n") &&
        stat.directory? && !stat.symlink? && stat.uid == @owner_uid
    rescue SystemCallError
      raise ArgumentError, "maintenance project root is unsafe"
    end

    def required_path_problems
      FIXED_PATHS.filter_map do |name, path|
        "#{name} is unavailable at #{path}" unless File.file?(path) && File.executable?(path)
      end + [
        ("authority helper template is unavailable" unless File.file?(File.join(@root, "scripts", "soul-maintenance-authority-root")))
      ].compact
    end

    def yay_version
      result = run(FIXED_PATHS.fetch("yay"), "--version")
      result["success"] ? result["stdout"].to_s[/yay v?([0-9]+\.[0-9]+\.[0-9]+)/, 1].to_s : ""
    end

    def regular_file_exact?(path, expected_digest, expected_mode)
      stat = File.lstat(path)
      stat.file? && !stat.symlink? && (stat.mode & 0o777) == expected_mode &&
        Digest::SHA256.file(path).hexdigest == expected_digest
    rescue SystemCallError
      false
    end

    def write_private_temp(label, content, mode)
      path = File.join("/tmp", "soul-maintenance-authority-#{label}-#{Process.pid}-#{SecureRandom.hex(6)}")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      path
    end

    def capture(argv)
      stdout, stderr, status = Open3.capture3(*argv)
      {"success" => status.success?, "stdout" => stdout, "stderr" => stderr}
    rescue SystemCallError => error
      {"success" => false, "stdout" => "", "stderr" => error.class.to_s}
    end

    def run(*argv) = @command_runner.call(argv)
    def ruby_literal(value) = value.to_s.dump
    def bounded(value) = value.to_s.byteslice(0, 500).to_s

    def secure_equal?(left, right)
      a = left.to_s
      b = right.to_s
      return false unless a.bytesize == 64 && b.bytesize == 64
      result = 0
      a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
      result.zero?
    end

    def outcome(lifecycle, ok, reason, data = {}, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => ok ? mutation : "none"}
    end
  end
end
