# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"

require_relative "bounded_command_runner"

module SoulCore
  class CrucibleMaintenanceAuthority
    VERSION = "soul-crucible-maintenance-d1-v1"
    CONFIRM_INSTALL = "INSTALL_CRUCIBLE_MAINTENANCE_AUTHORITY"
    SSH_ALIAS = "crucible-maintenance"
    REMOTE_USER = "souladmin"
    REMOTE_HOSTNAME = "crucible"
    HELPER_PATH = "/usr/local/libexec/soul-crucible-maintenance"
    SUDOERS_PATH = "/etc/sudoers.d/90-soul-crucible-maintenance"
    CLOUD_INIT_SUDOERS_PATH = "/etc/sudoers.d/90-cloud-init-users"
    SSH_PATH = "/usr/bin/ssh"
    SCP_PATH = "/usr/bin/scp"

    def initialize(
      root: Dir.pwd,
      runner: BoundedCommandRunner.new,
      ssh_config: File.expand_path("~/.ssh/config"),
      id_generator: -> { SecureRandom.hex(8) }
    )
      @root = File.expand_path(root)
      @runner = runner
      @ssh_config = File.expand_path(ssh_config)
      @id_generator = id_generator
    end

    def plan
      helper = helper_content
      helper_digest = Digest::SHA256.hexdigest(helper)
      sudoers = sudoers_content(helper_digest)
      problems = required_path_problems
      basis = {
        "operation" => "crucible_maintenance_authority_install",
        "version" => VERSION,
        "ssh_alias" => SSH_ALIAS,
        "remote_user" => REMOTE_USER,
        "remote_hostname" => REMOTE_HOSTNAME,
        "helper_path" => HELPER_PATH,
        "helper_mode" => "0755",
        "helper_sha256" => helper_digest,
        "sudoers_path" => SUDOERS_PATH,
        "sudoers_mode" => "0440",
        "sudoers_sha256" => Digest::SHA256.hexdigest(sudoers),
        "removed_broad_rule" => CLOUD_INIT_SUDOERS_PATH,
        "allowed_operations" => %w[self-check dnf5-upgrade reboot],
        "password_storage" => false,
        "arbitrary_command_forwarding" => false,
        "persistent_process" => false
      }
      digest = Digest::SHA256.hexdigest(JSON.generate(basis))
      outcome(
        problems.empty? ? "blocked_for_human_review" : "failed",
        problems.empty?,
        problems.empty? ? "Review the exact Crucible authority before installation." : problems.first,
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
      probe = ssh("/usr/bin/sudo", "-n", HELPER_PATH, "self-check", timeout: 10)
      parsed = JSON.parse(probe.stdout) if probe.status == "ok"
      broad = ssh("/usr/bin/sudo", "-n", "/usr/bin/test", "-e", CLOUD_INIT_SUDOERS_PATH, timeout: 10)
      ready = parsed.is_a?(Hash) &&
        parsed["version"] == VERSION &&
        parsed["arbitrary_command_forwarding"] == false &&
        broad.status != "ok"
      outcome("complete", true, "Crucible maintenance authority status collected.", {
        "ready" => ready,
        "authority_mode" => ready ? "root_owned_fixed_operations" : "unavailable",
        "version" => parsed.is_a?(Hash) ? parsed["version"].to_s : "",
        "broad_cloud_init_authority_present" => broad.status == "ok",
        "helper_sha256" => expected.fetch("helper_sha256")
      })
    rescue JSON::ParserError
      outcome("complete", true, "Crucible maintenance authority status collected.", {
        "ready" => false,
        "authority_mode" => "unavailable",
        "broad_cloud_init_authority_present" => true
      })
    end

    def install(expected_digest:, confirmation:)
      planned = plan
      return planned unless planned["ok"]
      data = planned.fetch("data")
      return outcome("blocked_for_human_review", false, "Review the current authority plan digest before installation.", data) unless secure_equal?(expected_digest, data.fetch("expected_digest"))
      return outcome("awaiting_input", false, "Exact Crucible authority confirmation is required.", data) unless confirmation == CONFIRM_INSTALL

      token = @id_generator.call.to_s
      raise "authority staging token is invalid" unless token.match?(/\A[a-f0-9]{16}\z/)
      local_helper = write_temp("helper", data.fetch("helper_content"), 0o700)
      local_sudoers = write_temp("sudoers", data.fetch("sudoers_content"), 0o600)
      remote_helper = "/tmp/soul-crucible-helper-#{token}"
      remote_sudoers = "/tmp/soul-crucible-sudoers-#{token}"
      staged_sudoers = "#{SUDOERS_PATH}.new"

      upload(local_helper, remote_helper)
      upload(local_sudoers, remote_sudoers)
      [
        ["/usr/bin/sudo", "-n", "/usr/bin/install", "-d", "-o", "root", "-g", "root", "-m", "0755", File.dirname(HELPER_PATH)],
        ["/usr/bin/sudo", "-n", "/usr/bin/install", "-o", "root", "-g", "root", "-m", "0755", remote_helper, HELPER_PATH],
        ["/usr/bin/sudo", "-n", "/usr/bin/install", "-o", "root", "-g", "root", "-m", "0440", remote_sudoers, staged_sudoers],
        ["/usr/bin/sudo", "-n", "/usr/sbin/visudo", "-cf", staged_sudoers],
        ["/usr/bin/sudo", "-n", "/usr/bin/mv", "-f", staged_sudoers, SUDOERS_PATH],
        ["/usr/bin/sudo", "-n", HELPER_PATH, "self-check"],
        ["/usr/bin/sudo", "-n", "/usr/bin/rm", "-f", CLOUD_INIT_SUDOERS_PATH]
      ].each do |argv|
        result = ssh(*argv, timeout: 20)
        raise "Crucible authority install failed at #{File.basename(argv[2] || argv[0])}" unless result.status == "ok"
      end
      cleanup = ssh("/usr/bin/rm", "-f", remote_helper, remote_sudoers, timeout: 10)
      raise "Crucible authority staging cleanup failed" unless cleanup.status == "ok"
      verified = status
      raise "Crucible authority did not pass exact post-install verification" unless verified.dig("data", "ready")

      outcome("complete", true, "Crucible root-owned maintenance authority installed exactly.", verified.fetch("data"), "privileged_policy_installed")
    ensure
      FileUtils.rm_f(local_helper) if defined?(local_helper) && local_helper
      FileUtils.rm_f(local_sudoers) if defined?(local_sudoers) && local_sudoers
    end

    def helper_content
      File.binread(File.join(@root, "scripts", "soul-crucible-maintenance-root"))
    end

    def sudoers_content(helper_digest = Digest::SHA256.hexdigest(helper_content))
      commands = %w[self-check dnf5-upgrade reboot].map do |operation|
        "sha256:#{helper_digest} #{HELPER_PATH} #{operation}"
      end.join(", \\\n    ")
      <<~SUDOERS
        # Soul/ Crucible D1 fixed-operation maintenance authority. Generated; do not edit.
        Defaults!#{HELPER_PATH} env_reset, secure_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
        #{REMOTE_USER} #{REMOTE_HOSTNAME} = (root) NOPASSWD: #{commands}
      SUDOERS
    end

    private

    def required_path_problems
      {
        "ssh" => SSH_PATH,
        "scp" => SCP_PATH,
        "SSH config" => @ssh_config,
        "helper template" => File.join(@root, "scripts", "soul-crucible-maintenance-root")
      }.filter_map { |label, path| "#{label} is unavailable" unless File.file?(path) && File.readable?(path) }
    end

    def ssh(*remote, timeout:)
      @runner.run(
        SSH_PATH, "-F", @ssh_config,
        "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
        "-o", "ConnectionAttempts=1", "-o", "LogLevel=ERROR",
        SSH_ALIAS, *remote,
        timeout_seconds: timeout, max_output_bytes: 64 * 1024,
        env: {"LC_ALL" => "C"}
      )
    end

    def upload(local, remote)
      result = @runner.run(
        SCP_PATH, "-F", @ssh_config,
        "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
        "-o", "ConnectionAttempts=1", "-o", "LogLevel=ERROR",
        local, "#{SSH_ALIAS}:#{remote}",
        timeout_seconds: 20, max_output_bytes: 64 * 1024,
        env: {"LC_ALL" => "C"}
      )
      raise "Crucible authority upload failed" unless result.status == "ok"
    end

    def write_temp(label, content, mode)
      path = File.join("/tmp", "soul-crucible-authority-#{label}-#{Process.pid}-#{SecureRandom.hex(6)}")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      path
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
