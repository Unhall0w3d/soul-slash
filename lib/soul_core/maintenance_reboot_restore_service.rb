# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "time"

require_relative "maintenance_desktop_handoff"
require_relative "maintenance_foreground_execution_service"
require_relative "maintenance_reboot_coordinator"
require_relative "maintenance_resume_deployment"

module SoulCore
  class MaintenanceRebootRestoreService
    PLAN_SCHEMA = "soul.maintenance.reboot_restore_plan.v1"
    CONFIRMATION = "OPEN_MAINTENANCE_REBOOT_TERMINAL"
    HANDOFF_START_TTL_SECONDS = 10 * 60
    FIXED_REBOOT_ARGV = ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reboot"].freeze

    def initialize(
      root: Dir.pwd,
      clock: -> { Time.now.utc },
      foreground_service: nil,
      desktop_handoff: nil,
      resume_deployment: nil,
      live_execution_enabled: false,
      boot_id_reader: nil,
      reboot_permission_probe: nil,
      id_generator: -> { SecureRandom.hex(8) }
    )
      @root = File.expand_path(root)
      @clock = clock
      @foreground_service = foreground_service || MaintenanceForegroundExecutionService.new(root: @root, clock: @clock)
      @desktop_handoff = desktop_handoff || MaintenanceDesktopHandoff.new(root: @root, clock: @clock)
      @resume_deployment = resume_deployment || MaintenanceResumeDeployment.new(root: @root)
      @live_execution_enabled = live_execution_enabled == true
      @boot_id_reader = boot_id_reader || -> { File.read("/proc/sys/kernel/random/boot_id", 128).strip }
      @reboot_permission_probe = reboot_permission_probe || method(:reboot_permitted?)
      @id_generator = id_generator
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @transactions_root = File.join(@root, "Soul", "private", "host_maintenance", "transactions")
      @lock_path = File.join(@state_root, "operation.lock")
    end

    def preview(force_database_refresh: false)
      base = @foreground_service.preview(force_database_refresh: force_database_refresh)
      return base unless base["ok"]
      a2 = base.dig("data", "plan")
      resume = @resume_deployment.status.dig("data") || {}
      blockers = Array(a2.dig("preflight", "live_blockers")).dup
      blockers << "reviewed one-shot resume unit is not installed and enabled" unless resume["ready"]
      blockers << "logind does not currently permit reboot" unless @reboot_permission_probe.call
      blockers << "a pending restore journal already exists" if pending_journal?
      source_boot_id = validated_boot_id
      preflight = a2.fetch("preflight").merge("a3_blockers" => blockers)
      basis = {
        "schema_version" => PLAN_SCHEMA,
        "risk_class" => "class_5",
        "owner_uid" => Process.uid,
        "force_database_refresh" => a2.fetch("force_database_refresh"),
        "commands" => a2.fetch("commands"),
        "flatpak_installations" => a2.fetch("flatpak_installations"),
        "restore_registry_digest" => a2.fetch("restore_registry_digest"),
        "window_restore_summary" => a2.fetch("window_restore_summary"),
        "source_boot_id" => source_boot_id,
        "resume_unit" => resume.slice("unit_name", "installed_exact", "enabled", "ready", "persistent_process", "restart_policy", "timer"),
        "one_authentication_required" => true,
        "automatic_reboot" => true,
        "live_execution_enabled" => @live_execution_enabled,
        "a2_plan_digest" => a2.fetch("expected_digest"),
        "a3_blockers" => blockers
      }
      expected_digest = digest(basis)
      plan = basis.merge(
        "preflight" => preflight,
        "plan_id" => "maintenance_a3_#{expected_digest[0, 16]}",
        "created_at" => @clock.call.iso8601,
        "expected_digest" => expected_digest,
        "confirmation" => CONFIRMATION,
        "human_review_required" => true,
        "execution_available" => @live_execution_enabled && blockers.empty?
      )
      outcome("complete", true, "A3 conditional reboot and restore preview ready", {
        "plan" => plan,
        "expected_digest" => expected_digest,
        "confirmation" => CONFIRMATION,
        "read_only" => true
      })
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "A3 preview failed safely: #{safe_error(error)}")
    end

    def execute(force_database_refresh:, expected_digest:, confirmation:)
      return outcome("blocked_for_human_review", false, "live A3 reboot execution is not enabled; complete code review and supervised authorization first") unless @live_execution_enabled
      return outcome("blocked_for_human_review", false, "exact A3 Dashboard confirmation is required") unless confirmation.to_s == CONFIRMATION
      operation_lock = acquire_operation_lock
      return outcome("blocked_for_human_review", false, "another maintenance transaction is active") unless operation_lock

      fresh = preview(force_database_refresh: force_database_refresh)
      return fresh unless fresh["ok"]
      plan = fresh.dig("data", "plan")
      return outcome("blocked_for_human_review", false, "A3 preview changed; review the fresh plan") unless secure_equal?(expected_digest, fresh.dig("data", "expected_digest"))
      blockers = Array(plan.dig("preflight", "a3_blockers"))
      return outcome("blocked_for_human_review", false, "A3 reboot preflight is blocked", {"blockers" => blockers, "plan" => plan}) unless blockers.empty?
      return outcome("blocked_for_human_review", false, "this exact A3 plan is already reserved") if @desktop_handoff.pending_live_digest?(expected_digest)

      transaction = build_transaction(plan)
      handoff = @desktop_handoff.reserve_transaction(transaction)
      outcome("complete", true, "A3 maintenance reboot terminal reserved", {
        "handoff" => handoff,
        "plan" => plan,
        "reboot_requested" => false
      }, "maintenance_reboot_transaction_reserved")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "A3 transaction reservation failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
    end

    def status
      outcome("complete", true, "A3 conditional reboot status loaded", {
        "live_execution_enabled" => @live_execution_enabled,
        "resume_unit" => @resume_deployment.status.dig("data"),
        "pending_restore" => pending_journal?,
        "desktop_handoff" => @desktop_handoff.status
      })
    rescue StandardError => error
      outcome("failed", false, "A3 status failed safely: #{safe_error(error)}")
    end

    private

    def build_transaction(plan)
      id = "maintenance_tx_#{@id_generator.call}"
      raise "transaction ID is invalid" unless id.match?(/\Amaintenance_tx_[a-f0-9]{16}\z/)
      FileUtils.mkdir_p(@transactions_root, mode: 0o700)
      {
        "schema_version" => "soul.maintenance.transaction.v1",
        "transaction_id" => id,
        "mode" => "live_reboot",
        "owner_uid" => Process.uid,
        "created_at" => @clock.call.iso8601,
        "deadline_at" => (@clock.call + HANDOFF_START_TTL_SECONDS).iso8601,
        "plan_digest" => plan.fetch("expected_digest"),
        "commands" => plan.fetch("commands"),
        "sudo_validation_argv" => ["/usr/bin/sudo", "-v"],
        "sudo_refresh_argv" => ["/usr/bin/sudo", "-n", "-v"],
        "sudo_invalidate_argv" => ["/usr/bin/sudo", "-k"],
        "reboot_allowed" => true,
        "reboot_argv" => FIXED_REBOOT_ARGV,
        "source_boot_id" => plan.fetch("source_boot_id"),
        "restore_registry_digest" => plan.fetch("restore_registry_digest"),
        "result_path" => File.join(@transactions_root, "#{id}.result.json")
      }
    end

    def reboot_permitted?
      stdout, _stderr, status = Open3.capture3(
        "/usr/bin/busctl", "--system", "call",
        "org.freedesktop.login1", "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager", "CanReboot"
      )
      status.success? && stdout.to_s.match?(/\As\s+"(?:yes|challenge)"\s*\z/)
    rescue StandardError
      false
    end

    def validated_boot_id
      value = @boot_id_reader.call.to_s.strip
      raise "current boot ID is invalid" unless value.match?(MaintenanceRebootCoordinator::BOOT_ID_PATTERN)
      value
    end

    def pending_journal?
      path = File.join(@root, "Soul", "private", "host_maintenance", "pending_restore.json")
      File.exist?(path) || File.symlink?(path)
    end

    def acquire_operation_lock
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      lock = File.open(@lock_path, File::RDWR | File::CREAT, 0o600)
      return lock if lock.flock(File::LOCK_EX | File::LOCK_NB)
      lock.close
      nil
    rescue Errno::EWOULDBLOCK
      nil
    end

    def release_operation_lock(lock)
      return unless lock
      lock.flock(File::LOCK_UN)
      lock.close
    rescue IOError
      nil
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))

    def secure_equal?(left, right)
      a = left.to_s
      b = right.to_s
      return false unless a.bytesize == 64 && b.bytesize == 64
      result = 0
      a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
      result.zero?
    end

    def safe_error(error) = "#{error.class}: #{error.message}".byteslice(0, 500)

    def outcome(lifecycle, ok, reason, data = {}, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => mutation}
    end
  end
end
