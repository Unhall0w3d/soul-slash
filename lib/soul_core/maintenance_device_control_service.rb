# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "bounded_command_runner"

module SoulCore
  class MaintenanceDeviceControlService
    PLAN_SCHEMA = "soul.maintenance.device_plan.v1"
    RECEIPT_SCHEMA = "soul.maintenance.device_receipt.v1"
    SSH_PATH = "/usr/bin/ssh"
    MAX_RECEIPTS = 30
    MAX_FILE_BYTES = 512 * 1024
    MAINTENANCE_TIMEOUT_SECONDS = 45 * 60
    RECONNECT_ATTEMPTS = 16
    RECONNECT_INTERVAL_SECONDS = 5
    REBOOT_HOLDOFF_SECONDS = 10
    LOCK_SCHEMA = "soul.maintenance.operation_lock.v1"
    LOCK_RECOVERY_GRACE_SECONDS = 30
    MAX_LOCK_BYTES = 4096
    MAX_DIAGNOSTIC_EXCERPT_BYTES = 480
    LIFECYCLE_CONTRACT = "device_scoped_v1"
    CRUCIBLE_HELPER_PATH = "/usr/local/libexec/soul-crucible-maintenance"
    CRUCIBLE_AUTHORITY_VERSION = "soul-crucible-maintenance-d1-v1"
    NIXOS_HELPER_PATH = "/run/current-system/sw/bin/soul-nixos-maintenance"
    NIXOS_AUTHORITY_VERSION = "soul-nixos-maintenance-a1-v1"
    SSH_ALIAS_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}\z/
    FOUNDRY_MAINTENANCE = [
      ["/usr/bin/apt-get", "update"],
      ["/usr/bin/apt-get", "-y", "-o", "Dpkg::Options::=--force-confold", "dist-upgrade"]
    ].freeze
    FOUNDRY_REBOOT_READINESS = [
      {
        "label" => "Proxmox VE management",
        "argv" => ["/usr/bin/pveversion"],
        "stdout_includes" => ["pve-manager/"]
      },
      {
        "label" => "Proxmox VE management services",
        "argv" => ["/usr/bin/systemctl", "is-active", "pveproxy", "pvedaemon", "pvestatd"],
        "stdout_includes" => ["active\nactive\nactive"]
      }
    ].freeze

    TARGETS = {
      "forge" => {
        "label" => "Forge",
        "maintenance_adapter" => "proxmox_apt",
        "ssh_alias" => "proxmox-maintenance",
        "impact" => ["Pi-hole LXC 100 is interrupted while Forge reboots"],
        "maintenance" => [
          ["/usr/bin/apt-get", "update"],
          ["/usr/bin/apt-get", "-y", "-o", "Dpkg::Options::=--force-confold", "dist-upgrade"]
        ],
        "reboot_readiness" => [
          {
            "label" => "Proxmox VE management",
            "argv" => ["/usr/bin/pveversion"],
            "stdout_includes" => ["pve-manager/"]
          },
          {
            "label" => "Pi-hole LXC 100",
            "argv" => ["/usr/sbin/pct", "status", "100"],
            "stdout_includes" => ["status: running"]
          },
          {
            "label" => "Pi-hole dependency services",
            "ssh_alias" => "pihole-maintenance",
            "argv" => ["/usr/bin/systemctl", "is-active", "pihole-FTL", "unbound"],
            "stdout_includes" => ["active\nactive"]
          },
          {
            "label" => "Pi-hole dependency versions",
            "ssh_alias" => "pihole-maintenance",
            "argv" => ["/usr/local/bin/pihole", "-v"],
            "stdout_includes" => ["Core version is", "Web version is", "FTL version is"]
          },
          {
            "label" => "Pi-hole dependency DNS and blocking",
            "ssh_alias" => "pihole-maintenance",
            "argv" => ["/usr/local/bin/pihole", "status"],
            "stdout_includes" => ["FTL is listening", "blocking is enabled"]
          }
        ]
      },
      "pihole" => {
        "label" => "Pi-hole",
        "maintenance_adapter" => "debian_apt_pihole",
        "ssh_alias" => "pihole-maintenance",
        "impact" => [],
        "maintenance" => [
          ["/usr/bin/apt-get", "update"],
          ["/usr/bin/apt-get", "-y", "-o", "Dpkg::Options::=--force-confold", "dist-upgrade"],
          ["/usr/local/bin/pihole", "-up"]
        ],
        "reboot_readiness" => [
          {
            "label" => "Pi-hole services",
            "argv" => ["/usr/bin/systemctl", "is-active", "pihole-FTL", "unbound"],
            "stdout_includes" => ["active\nactive"]
          },
          {
            "label" => "Pi-hole versions",
            "argv" => ["/usr/local/bin/pihole", "-v"],
            "stdout_includes" => ["Core version is", "Web version is", "FTL version is"]
          },
          {
            "label" => "Pi-hole DNS and blocking",
            "argv" => ["/usr/local/bin/pihole", "status"],
            "stdout_includes" => ["FTL is listening", "blocking is enabled"]
          }
        ]
      },
      "crucible" => {
        "label" => "Crucible",
        "maintenance_adapter" => "fedora_dnf5",
        "ssh_alias" => "crucible-maintenance",
        "impact" => ["Crucible backup storage is unavailable while the guest reboots"],
        "maintenance" => [
          ["/usr/bin/sudo", "-n", CRUCIBLE_HELPER_PATH, "dnf5-upgrade"]
        ],
        "reboot" => [
          "/usr/bin/sudo", "-n", CRUCIBLE_HELPER_PATH, "reboot"
        ],
        "reboot_readiness" => [
          {
            "label" => "SSH and QEMU guest agent",
            "argv" => ["/usr/bin/systemctl", "is-active", "sshd", "qemu-guest-agent"],
            "stdout_includes" => ["active\nactive"]
          },
          {
            "label" => "DNF5 package manager",
            "argv" => ["/usr/bin/dnf5", "--version"],
            "stdout_includes" => ["dnf5 version"]
          },
          {
            "label" => "Backup storage mount",
            "argv" => ["/usr/bin/findmnt", "--noheadings", "--output", "TARGET", "/srv/soul-backup"],
            "stdout_includes" => ["/srv/soul-backup"]
          },
          {
            "label" => "Fixed Crucible authority",
            "argv" => ["/usr/bin/sudo", "-n", CRUCIBLE_HELPER_PATH, "self-check"],
            "stdout_includes" => [CRUCIBLE_AUTHORITY_VERSION]
          }
        ]
      },
      "temper" => {
        "label" => "Temper",
        "maintenance_adapter" => "nixos_flake",
        "ssh_alias" => "temper",
        "impact" => [],
        "maintenance" => [
          ["/run/current-system/sw/bin/sudo", "-n", NIXOS_HELPER_PATH, "upgrade"]
        ],
        "reboot" => [
          "/run/current-system/sw/bin/sudo", "-n", NIXOS_HELPER_PATH, "reboot"
        ],
        "boot_identity" => [
          "/run/current-system/sw/bin/cat", "/proc/sys/kernel/random/boot_id"
        ],
        "reboot_readiness" => [
          {
            "label" => "SSH and QEMU guest agent",
            "argv" => ["/run/current-system/sw/bin/systemctl", "is-active", "sshd", "qemu-guest-agent"],
            "stdout_includes" => ["active\nactive"]
          },
          {
            "label" => "Fixed NixOS authority",
            "argv" => ["/run/current-system/sw/bin/sudo", "-n", NIXOS_HELPER_PATH, "self-check"],
            "stdout_includes" => [NIXOS_AUTHORITY_VERSION]
          },
          {
            "label" => "Active and booted NixOS generations",
            "argv" => ["/run/current-system/sw/bin/sudo", "-n", NIXOS_HELPER_PATH, "generation-match"],
            "stdout_includes" => ["matched"]
          }
        ]
      }
    }.freeze

    def initialize(
      root: Dir.pwd,
      fleet_status_service:,
      runner: BoundedCommandRunner.new,
      clock: -> { Time.now.utc },
      sleeper: ->(seconds) { sleep(seconds) },
      live_execution_enabled: false,
      ssh_config: File.expand_path("~/.ssh/config"),
      id_generator: -> { SecureRandom.hex(8) },
      process_alive: nil,
      process_env: ENV
    )
      @root = File.expand_path(root)
      @fleet_status_service = fleet_status_service
      @runner = runner
      @clock = clock
      @sleeper = sleeper
      @live_execution_enabled = live_execution_enabled == true
      @ssh_config = File.expand_path(ssh_config)
      @id_generator = id_generator
      @process_alive = process_alive || method(:process_alive?)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @receipts_root = File.join(@state_root, "device_receipts")
      @lock_path = File.join(@state_root, "operation.lock")
    end

    def preview(device_id:, action:)
      target = target!(device_id)
      action = action!(action)
      commands = action == "maintenance" ? target.fetch("maintenance") : [target.fetch("reboot", ["/usr/bin/systemctl", "reboot"])]
      basis = {
        "schema_version" => PLAN_SCHEMA,
        "device_id" => device_id,
        "device_label" => target_display_label(device_id, target.fetch("label")),
        "address" => target_display_address(device_id),
        "action" => action,
        "maintenance_adapter" => target.fetch("maintenance_adapter"),
        "lifecycle_contract" => LIFECYCLE_CONTRACT,
        "ssh_alias" => target.fetch("ssh_alias"),
        "commands" => commands.map { |argv| {"argv" => argv} },
        "readiness" => action == "reboot" ? target.fetch("reboot_readiness") : [],
        "impact" => action == "reboot" ? target.fetch("impact") : [],
        "automatic_retry" => false,
        "fleet_wide" => false
      }
      if action == "reboot"
        basis["boot_identity"] = {
          "argv" => target.fetch("boot_identity", ["/usr/bin/cat", "/proc/sys/kernel/random/boot_id"])
        }
      end
      expected_digest = digest(basis)
      confirmation = "#{action == "maintenance" ? "MAINTAIN" : "REBOOT"}_#{device_id.upcase}"
      outcome("complete", true, "Device-scoped #{action} preview ready", {
        "plan" => basis.merge(
          "plan_id" => "device_#{action}_#{expected_digest[0, 16]}",
          "created_at" => @clock.call.iso8601,
          "expected_digest" => expected_digest,
          "confirmation" => confirmation,
          "risk_class" => "class_5",
          "live_execution_enabled" => @live_execution_enabled
        ),
        "expected_digest" => expected_digest,
        "confirmation" => confirmation
      })
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "Device preview failed safely: #{safe_error(error)}")
    end

    def execute(device_id:, action:, confirmation:, expected_digest:, progress: nil)
      return outcome("blocked_for_human_review", false, "live device maintenance is not enabled") unless @live_execution_enabled

      fresh = preview(device_id: device_id, action: action)
      return fresh unless fresh["ok"]
      plan = fresh.dig("data", "plan")
      return outcome("blocked_for_human_review", false, "exact device confirmation is required") unless confirmation.to_s == plan.fetch("confirmation")
      return outcome("blocked_for_human_review", false, "device preview changed; review the fresh plan") unless secure_equal?(expected_digest, plan.fetch("expected_digest"))

      lock = acquire_lock
      return outcome("blocked_for_human_review", false, "another maintenance operation is active") unless lock

      progress&.call({"stage" => "authorized", "message" => "#{plan.fetch('device_label')} #{action} authorized; starting the fixed device-scoped transaction."})
      receipt = action == "maintenance" ? maintain(plan, progress) : reboot(plan, progress)
      write_receipt(receipt)
      progress&.call({"stage" => "collecting", "message" => "Refreshing persisted fleet evidence after the terminal device lifecycle."})
      fleet = receipt["lifecycle_state"] == "complete" ? @fleet_status_service.collect : @fleet_status_service.snapshot
      outcome(
        receipt["lifecycle_state"],
        receipt["lifecycle_state"] == "complete",
        receipt["summary"],
        {"receipt" => receipt, "fleet" => fleet["data"]},
        receipt["lifecycle_state"] == "complete" ? "device_scoped" : "none"
      )
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "Device operation failed safely: #{safe_error(error)}")
    ensure
      release_lock(lock)
    end

    def receipts(limit: MAX_RECEIPTS)
      prepare_directories
      count = [[Integer(limit), 1].max, MAX_RECEIPTS].min
      rows = Dir.glob(File.join(@receipts_root, "*.json")).filter_map do |path|
        read_receipt(path)
      end.sort_by { |row| row.fetch("finished_at", "") }.reverse.first(count)
      outcome("complete", true, "Device maintenance receipts loaded", {"receipts" => rows, "live_execution_enabled" => @live_execution_enabled})
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "Device receipts failed safely: #{safe_error(error)}")
    end

    private

    def maintain(plan, progress)
      started = @clock.call
      evidence = []
      plan.fetch("commands").each_with_index do |command, index|
        progress&.call({"stage" => "maintaining", "message" => "Running fixed maintenance step #{index + 1} of #{plan.fetch('commands').length} on #{plan.fetch('device_label')}."})
        result = remote_run(plan.fetch("ssh_alias"), *command.fetch("argv"), timeout: MAINTENANCE_TIMEOUT_SECONDS)
        evidence << command_evidence("maintenance.#{index + 1}", result)
        next if result.status == "ok"

        diagnostic = evidence.last.fetch("diagnostic")
        return receipt(
          plan,
          started,
          "failed",
          "Maintenance stopped at fixed step #{index + 1}: #{diagnostic.fetch('summary')}",
          evidence
        )
      end
      receipt(plan, started, "complete", "#{plan.fetch('device_label')} maintenance completed.", evidence)
    end

    def reboot(plan, progress)
      started = @clock.call
      evidence = []
      boot_identity = plan.fetch("boot_identity").fetch("argv")
      before = remote_run(plan.fetch("ssh_alias"), *boot_identity)
      evidence << command_evidence("reboot.boot_id_before", before)
      return receipt(plan, started, "failed", "Target boot identity could not be collected.", evidence) unless before.status == "ok"

      progress&.call({"stage" => "rebooting", "message" => "Sending the single reviewed reboot request to #{plan.fetch('device_label')}."})
      reboot_result = remote_run(
        plan.fetch("ssh_alias"), *plan.fetch("commands").fetch(0).fetch("argv"),
        timeout: 15,
        accepted_exit_statuses: [0, 255]
      )
      evidence << command_evidence("reboot.request", reboot_result)
      return receipt(plan, started, "failed", "The single reboot request failed.", evidence) unless reboot_result.status == "ok"

      progress&.call({"stage" => "holdoff", "message" => "Reboot requested once; waiting #{REBOOT_HOLDOFF_SECONDS} seconds before reconnect checks."})
      @sleeper.call(REBOOT_HOLDOFF_SECONDS)
      new_boot_seen = false
      RECONNECT_ATTEMPTS.times do |attempt|
        progress&.call({"stage" => "reconnecting", "message" => "Reconnect check #{attempt + 1} of #{RECONNECT_ATTEMPTS} for #{plan.fetch('device_label')}."})
        current = remote_run(plan.fetch("ssh_alias"), *boot_identity, timeout: 7)
        evidence << command_evidence("reboot.reconnect.#{attempt + 1}", current)
        if current.status == "ok" && !output(current).empty? && output(current) != output(before)
          new_boot_seen = true
          ready, readiness_evidence = reboot_ready?(plan, attempt + 1, progress)
          evidence.concat(readiness_evidence)
          if ready
            return receipt(plan, started, "complete", "#{plan.fetch('device_label')} rebooted, returned with a new boot identity, and passed reviewed readiness checks.", evidence)
          end
        end
        @sleeper.call(RECONNECT_INTERVAL_SECONDS) unless attempt == RECONNECT_ATTEMPTS - 1
      end
      summary = if new_boot_seen
                  "#{plan.fetch('device_label')} returned with a new boot identity but did not pass reviewed readiness checks within the bounded window."
                else
                  "#{plan.fetch('device_label')} did not return within the bounded reconnect window."
                end
      receipt(plan, started, "blocked_for_human_review", summary, evidence)
    end

    def reboot_ready?(plan, attempt, progress)
      checks = plan.fetch("readiness")
      progress&.call({
        "stage" => "verifying",
        "message" => "Running #{checks.length} fixed readiness checks for #{plan.fetch('device_label')} after reconnect #{attempt}."
      })
      evidence = checks.each_with_index.map do |check, index|
        result = remote_run(check.fetch("ssh_alias", plan.fetch("ssh_alias")), *check.fetch("argv"), timeout: 10)
        verified = result.status == "ok" && check.fetch("stdout_includes").all? { |needle| output(result).include?(needle) }
        command_evidence("reboot.readiness.#{attempt}.#{index + 1}", result).merge(
          "status" => verified ? "ok" : "not_ready",
          "check" => check.fetch("label")
        )
      end
      [evidence.all? { |entry| entry["status"] == "ok" }, evidence]
    end

    def remote_run(target, *argv, timeout: 20, accepted_exit_statuses: [0])
      result = @runner.run(
        SSH_PATH,
        "-F", @ssh_config,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "ConnectionAttempts=1",
        "-o", "LogLevel=ERROR",
        target,
        *argv,
        timeout_seconds: timeout,
        max_output_bytes: 256 * 1024,
        env: {"LC_ALL" => "C"}
      )
      normalized = result.dup
      normalized.status = "ok" if accepted_exit_statuses.include?(result.exit_status)
      normalized
    end

    def receipt(plan, started, lifecycle, summary, evidence)
      {
        "schema_version" => RECEIPT_SCHEMA,
        "receipt_id" => "device_receipt_#{@id_generator.call}",
        "device_id" => plan.fetch("device_id"),
        "action" => plan.fetch("action"),
        "maintenance_adapter" => plan.fetch("maintenance_adapter"),
        "lifecycle_contract" => plan.fetch("lifecycle_contract"),
        "expected_digest" => plan.fetch("expected_digest"),
        "lifecycle_state" => lifecycle,
        "summary" => summary,
        "started_at" => started.iso8601,
        "finished_at" => @clock.call.iso8601,
        "evidence" => evidence.first(64),
        "reboot_request_count" => plan.fetch("action") == "reboot" ? 1 : 0,
        "automatic_retry" => false
      }
    end

    def command_evidence(adapter, result)
      evidence = {
        "adapter" => adapter,
        "status" => result.status,
        "exit_status" => result.exit_status,
        "truncated" => result.truncated == true
      }
      evidence["diagnostic"] = maintenance_diagnostic(result) unless result.status == "ok"
      evidence
    end

    def maintenance_diagnostic(result)
      source = [result.stderr, result.stdout].map(&:to_s).reject(&:empty?).join("\n")
      code, summary = diagnostic_classification(result, source)
      diagnostic = {"code" => code, "summary" => summary}
      excerpt = sanitize_diagnostic_excerpt(source)
      diagnostic["excerpt"] = excerpt unless excerpt.empty?
      diagnostic
    end

    def diagnostic_classification(result, source)
      return ["command_timeout", "The fixed command exceeded its bounded runtime."] if result.status == "timeout"

      case source
      when /401\s+Unauthorized|enterprise repository.*subscription|requires (?:a )?(?:valid )?subscription|authentication failed/i
        ["repository_authorization", "A configured package repository rejected this device's authorization."]
      when /could not get lock|unable to acquire (?:the )?(?:dpkg|apt|rpm|dnf|package manager).*lock|another app is currently holding the (?:yum|dnf) lock/i
        ["package_manager_lock", "Another package-manager transaction holds the required lock."]
      when /temporary failure resolving|could not resolve|name or service not known|failed to resolve/i
        ["name_resolution", "The device could not resolve a package repository name."]
      when /no space left on device|insufficient disk space|not enough (?:free )?disk space/i
        ["storage_exhausted", "The device does not have enough storage for package maintenance."]
      when /dpkg was interrupted|run ['"]?dpkg --configure -a|rpmdb.*(?:corrupt|damaged)|transaction.*(?:interrupted|incomplete)/i
        ["package_state_interrupted", "The package manager has an interrupted or inconsistent transaction state."]
      when /network is unreachable|connection (?:timed out|refused)|failed to connect|could not connect/i
        ["network_unavailable", "The device could not reach a configured package repository."]
      else
        ["nonzero_exit", "The fixed maintenance command returned a nonzero exit status."]
      end
    end

    def sanitize_diagnostic_excerpt(source)
      value = source.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      value = value.gsub(/\e\[[0-?]*[ -\/]*[@-~]/, "")
      value = value.gsub(%r{([a-z][a-z0-9+.-]*://)[^/\s@]+@}i, '\1[REDACTED]@')
      value = value.gsub(/([?&](?:token|access_?token|api_?key|auth|key|password|secret|signature)=)[^&#\s]+/i, '\1[REDACTED]')
      value = value.gsub(/[[:cntrl:]]+/, " ").gsub(/\s+/, " ").strip
      bounded_utf8(value, MAX_DIAGNOSTIC_EXCERPT_BYTES)
    end

    def bounded_utf8(value, maximum_bytes)
      return value if value.bytesize <= maximum_bytes

      value.byteslice(0, maximum_bytes).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").sub(/\s+\S*\z/, "").rstrip
    end

    def acquire_lock
      prepare_directories
      2.times do |attempt|
        begin
          descriptor = File.open(@lock_path, File::WRONLY | File::CREAT | File::EXCL, 0o600)
          descriptor.write(JSON.generate(lock_payload))
          descriptor.flush
          descriptor.fsync
          return descriptor
        rescue Errno::EEXIST
          return nil unless attempt.zero? && quarantine_stale_lock
        rescue StandardError
          release_lock(descriptor)
          raise
        end
      end
      nil
    end

    def release_lock(descriptor)
      return unless descriptor

      owned = descriptor.stat
      descriptor.close
      current = File.lstat(@lock_path)
      return unless current.file? && !current.symlink?
      return unless current.dev == owned.dev && current.ino == owned.ino

      File.delete(@lock_path)
    rescue Errno::ENOENT
      nil
    rescue SystemCallError
      nil
    ensure
      descriptor.close if descriptor && !descriptor.closed?
    end

    def lock_payload
      {
        "schema_version" => LOCK_SCHEMA,
        "owner_pid" => Process.pid,
        "owner_start_ticks" => process_start_ticks(Process.pid),
        "boot_id" => current_boot_id,
        "started_at" => @clock.call.iso8601,
        "kind" => "device_control"
      }.compact
    end

    def quarantine_stale_lock
      observed = stale_lock_stat
      return false unless observed

      current = File.lstat(@lock_path)
      return false unless current.dev == observed.dev && current.ino == observed.ino

      stamp = @clock.call.utc.strftime("%Y%m%dT%H%M%SZ")
      quarantine = File.join(@state_root, "operation.lock.stale-#{stamp}-#{SecureRandom.hex(4)}")
      File.rename(@lock_path, quarantine)
      File.chmod(0o600, quarantine)
      true
    rescue Errno::ENOENT
      true
    rescue Errno::EEXIST, SystemCallError
      false
    end

    def stale_lock_stat
      stat = File.lstat(@lock_path)
      return nil unless stat.file? && !stat.symlink?

      payload = read_lock_payload
      if valid_lock_payload?(payload)
        return nil if lock_owner_active?(payload)
        return stat
      end

      age = @clock.call.to_f - stat.mtime.to_f
      age >= LOCK_RECOVERY_GRACE_SECONDS ? stat : nil
    rescue Errno::ENOENT
      nil
    end

    def read_lock_payload
      content = File.open(@lock_path, "rb") { |file| file.read(MAX_LOCK_BYTES + 1) }.to_s
      return nil if content.empty? || content.bytesize > MAX_LOCK_BYTES

      JSON.parse(content)
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def valid_lock_payload?(payload)
      payload.is_a?(Hash) && payload["owner_pid"].is_a?(Integer) && payload["owner_pid"].positive?
    end

    def lock_owner_active?(payload)
      pid = payload.fetch("owner_pid")
      return false unless @process_alive.call(pid)

      recorded_boot = payload["boot_id"].to_s
      observed_boot = current_boot_id
      return false if !recorded_boot.empty? && !observed_boot.empty? && !secure_equal?(recorded_boot, observed_boot)

      recorded_start = payload["owner_start_ticks"].to_s
      return true if recorded_start.empty?

      observed_start = process_start_ticks(pid)
      observed_start.empty? || secure_equal?(recorded_start, observed_start)
    rescue StandardError
      false
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def process_start_ticks(pid)
      content = File.read("/proc/#{Integer(pid)}/stat", MAX_LOCK_BYTES)
      suffix = content.split(") ", 2).last.to_s
      suffix.split.fetch(19, "")
    rescue ArgumentError, Errno::ENOENT, IndexError, SystemCallError
      ""
    end

    def current_boot_id
      File.read("/proc/sys/kernel/random/boot_id", 128).strip
    rescue SystemCallError
      ""
    end

    def prepare_directories
      [@state_root, @receipts_root].each do |directory|
        FileUtils.mkdir_p(directory, mode: 0o700)
        raise "maintenance state path is unsafe" if File.symlink?(directory)
        File.chmod(0o700, directory)
      end
    end

    def write_receipt(value)
      prepare_directories
      payload = JSON.pretty_generate(value)
      raise "device receipt exceeds its size bound" if payload.bytesize > MAX_FILE_BYTES

      path = File.join(@receipts_root, "#{value.fetch('finished_at').gsub(/[^0-9]/, '')}-#{value.fetch('receipt_id')}.json")
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
      prune_receipts
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def prune_receipts
      paths = Dir.glob(File.join(@receipts_root, "*.json")).sort.reverse
      paths.drop(MAX_RECEIPTS).each { |path| File.delete(path) if File.file?(path) && !File.symlink?(path) }
    end

    def read_receipt(path)
      return nil if File.symlink?(path) || File.size(path) > MAX_FILE_BYTES
      parsed = JSON.parse(File.binread(path, MAX_FILE_BYTES + 1))
      parsed if parsed["schema_version"] == RECEIPT_SCHEMA
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def target!(device_id)
      return foundry_target! if device_id.to_s == "foundry"

      target = TARGETS.fetch(device_id.to_s) { raise ArgumentError, "device is not available for remote maintenance" }
      return temper_target!(target) if device_id.to_s == "temper"

      target
    end

    def temper_target!(target)
      raise ArgumentError, "Temper control is not enabled" unless truthy?(@process_env["SOUL_FLEET_TEMPER_CONTROL_ENABLED"])

      ssh_alias = @process_env.fetch("SOUL_FLEET_TEMPER_SSH_ALIAS", "temper").to_s.strip
      raise ArgumentError, "Temper SSH alias is invalid" unless ssh_alias.match?(SSH_ALIAS_PATTERN)
      raise ArgumentError, "Temper enrolled control evidence is unavailable; refresh fleet status" unless temper_control_evidence?

      target.merge(
        "label" => target_display_label("temper", target.fetch("label")),
        "ssh_alias" => ssh_alias
      )
    end

    def temper_control_evidence?
      snapshot = @fleet_status_service.snapshot
      return false unless snapshot["ok"] == true && snapshot["lifecycle_state"] == "complete"

      Array(snapshot.dig("data", "devices")).any? do |device|
        device["control"] == "maintenance" &&
          device.dig("facts", "control_target_id") == "temper" &&
          device.dig("facts", "mutation_supported") == true &&
          device.dig("facts", "status_adapter") == "nixos_flake_fixed_maintenance"
      end
    rescue StandardError
      false
    end

    def foundry_target!
      raise ArgumentError, "Foundry control is not enabled" unless truthy?(@process_env["SOUL_FLEET_FOUNDRY_CONTROL_ENABLED"])

      ssh_alias = @process_env.fetch("SOUL_FLEET_FOUNDRY_SSH_ALIAS", "foundry").to_s.strip
      raise ArgumentError, "Foundry SSH alias is invalid" unless ssh_alias.match?(SSH_ALIAS_PATTERN)
      raise ArgumentError, "Foundry enrolled control evidence is unavailable; refresh fleet status" unless foundry_control_evidence?

      {
        "label" => "Foundry",
        "maintenance_adapter" => "proxmox_apt",
        "ssh_alias" => ssh_alias,
        "impact" => ["All Foundry guests are interrupted while Foundry reboots"],
        "maintenance" => FOUNDRY_MAINTENANCE,
        "reboot_readiness" => FOUNDRY_REBOOT_READINESS
      }
    end

    def foundry_control_evidence?
      snapshot = @fleet_status_service.snapshot
      return false unless snapshot["ok"] == true && snapshot["lifecycle_state"] == "complete"

      Array(snapshot.dig("data", "devices")).any? do |device|
        device["control"] == "maintenance" &&
          device.dig("facts", "control_target_id") == "foundry" &&
          device.dig("facts", "mutation_supported") == true &&
          device.dig("facts", "status_adapter") == "proxmox_fixed_maintenance"
      end
    rescue StandardError
      false
    end

    def target_display_address(device_id)
      key, fallback = case device_id.to_s
                      when "forge" then ["SOUL_FLEET_FORGE_ADDRESS", "proxmox-maintenance"]
                      when "pihole" then ["SOUL_FLEET_PIHOLE_ADDRESS", "pihole-maintenance"]
                      when "crucible" then ["SOUL_FLEET_CRUCIBLE_ADDRESS", "crucible-maintenance"]
                      when "foundry" then ["SOUL_FLEET_FOUNDRY_ADDRESS", "foundry"]
                      when "temper" then ["SOUL_FLEET_TEMPER_ADDRESS", "temper"]
                      else raise ArgumentError, "device is not available for remote maintenance"
                      end
      value = @process_env[key].to_s.strip
      value.empty? ? fallback : value.byteslice(0, 255).to_s
    end

    def target_display_label(device_id, fallback)
      key = case device_id.to_s
            when "pihole" then "SOUL_FLEET_PIHOLE_LABEL"
            when "crucible" then "SOUL_FLEET_CRUCIBLE_LABEL"
            when "forge" then nil
            when "foundry" then "SOUL_FLEET_FOUNDRY_LABEL"
            when "temper" then "SOUL_FLEET_TEMPER_LABEL"
            else raise ArgumentError, "device is not available for remote maintenance"
            end
      value = key && @process_env[key].to_s.strip
      value.to_s.empty? ? fallback : value.byteslice(0, 80).to_s
    end

    def action!(action)
      value = action.to_s
      raise ArgumentError, "device action must be maintenance or reboot" unless %w[maintenance reboot].include?(value)
      value
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(deep_sort(value)))
    end

    def deep_sort(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
      when Array then value.map { |item| deep_sort(item) }
      else value
      end
    end

    def secure_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize && !left.empty?
      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def output(result)
      result.stdout.to_s.strip
    end

    def safe_error(error)
      error.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").byteslice(0, 240).to_s
    end

    def outcome(lifecycle, ok, reason, data = {}, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => mutation}
    end
  end
end
