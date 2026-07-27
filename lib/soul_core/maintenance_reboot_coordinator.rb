# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "bounded_command_runner"
require_relative "maintenance_rehearsal_service"
require_relative "maintenance_resume_deployment"

module SoulCore
  class MaintenanceRebootCoordinator
    JOURNAL_SCHEMA = "soul.maintenance.restore_journal.v1"
    MAX_FILE_BYTES = 512 * 1024
    RESUME_TTL_SECONDS = 30 * 60
    BOOT_ID_PATH = "/proc/sys/kernel/random/boot_id"
    BOOT_ID_PATTERN = /\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/

    def initialize(
      root: Dir.pwd,
      clock: -> { Time.now.utc },
      runner: BoundedCommandRunner.new,
      rehearsal_service: nil,
      package_lock_probe: -> { File.exist?("/var/lib/pacman/db.lck") },
      active_work_probe: nil,
      resume_unit_probe: nil,
      reboot_permission_probe: nil,
      boot_id_reader: nil
    )
      @root = File.expand_path(root)
      @clock = clock
      @runner = runner
      @rehearsal_service = rehearsal_service || MaintenanceRehearsalService.new(root: @root, clock: @clock, runner: runner)
      @package_lock_probe = package_lock_probe
      @active_work_probe = active_work_probe || method(:default_active_work)
      @resume_unit_probe = resume_unit_probe || -> { MaintenanceResumeDeployment.new(root: @root).status.dig("data", "ready") == true }
      @reboot_permission_probe = reboot_permission_probe || method(:reboot_permitted?)
      @boot_id_reader = boot_id_reader || method(:read_boot_id)
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @pending_path = File.join(@state_root, "pending_restore.json")
    end

    def prepare(transaction)
      validate_transaction!(transaction)
      raise "pacman database lock appeared before reboot" if @package_lock_probe.call
      active = Array(@active_work_probe.call).map(&:to_s).reject(&:empty?).uniq
      raise "active Soul work blocks reboot: #{active.join(', ')}" unless active.empty?
      raise "one-shot maintenance resume unit is unavailable" unless @resume_unit_probe.call
      raise "logind does not currently permit reboot" unless @reboot_permission_probe.call
      raise "a pending maintenance restore journal already exists" if File.exist?(@pending_path) || File.symlink?(@pending_path)

      registry = @rehearsal_service.restore_registry
      registry_digest = digest(registry)
      raise "restore registry changed after review" unless secure_equal?(registry_digest, transaction.fetch("restore_registry_digest"))
      snapshot = @rehearsal_service.capture_window_snapshot
      raise "fresh restore snapshot has no restorable applications" if Integer(snapshot.fetch("restorable_count", 0)).zero?
      raise "fresh restore snapshot exceeds the A3 application bound" if Integer(snapshot.fetch("restorable_count", 0)) > 32

      now = @clock.call
      source_boot_id = @boot_id_reader.call
      raise "boot identity changed after A3 review" unless source_boot_id == transaction.fetch("source_boot_id")
      basis = {
        "schema_version" => JOURNAL_SCHEMA,
        "journal_id" => "restore_#{transaction.fetch('transaction_id').delete_prefix('maintenance_tx_')}",
        "transaction_id" => transaction.fetch("transaction_id"),
        "plan_digest" => transaction.fetch("plan_digest"),
        "owner_uid" => Process.uid,
        "created_at" => now.iso8601,
        "resume_deadline_at" => (now + RESUME_TTL_SECONDS).iso8601,
        "source_boot_id" => source_boot_id,
        "attempt_boot_id" => nil,
        "current_state" => "awaiting_login",
        "restore_registry_digest" => registry_digest,
        "window_snapshot" => snapshot,
        "update_commands" => transaction.fetch("commands").map { |command| {"adapter" => command.fetch("adapter"), "exit_status" => 0, "status" => "complete"} },
        "reboot_requested" => false,
        "restore_attempts" => []
      }
      journal = basis.merge("journal_digest" => digest(basis))
      prepare_directory
      atomic_json(@pending_path, journal)
      journal
    end

    def mark_reboot_requested
      update_pending do |journal|
        journal["current_state"] = "reboot_requested"
        journal["reboot_requested"] = true
      end
    end

    def mark_reboot_failed(reason)
      failed = update_pending do |journal|
        journal["current_state"] = "failed"
        journal["reboot_requested"] = false
        journal["reason"] = reason.to_s.byteslice(0, 500)
        journal["finished_at"] = @clock.call.iso8601
      end
      journals = File.join(@state_root, "journals")
      FileUtils.mkdir_p(journals, mode: 0o700)
      File.rename(@pending_path, File.join(journals, "#{failed.fetch('journal_id')}.json"))
    rescue StandardError
      nil
    end

    private

    def validate_transaction!(transaction)
      raise "A3 transaction mode is invalid" unless transaction["mode"] == "live_reboot"
      raise "A3 transaction reboot authority is invalid" unless transaction["reboot_allowed"] == true
      raise "A3 transaction owner is invalid" unless transaction["owner_uid"] == Process.uid
      raise "A3 transaction restore registry digest is invalid" unless transaction["restore_registry_digest"].to_s.match?(/\A[a-f0-9]{64}\z/)
      raise "A3 transaction source boot ID is invalid" unless transaction["source_boot_id"].to_s.match?(BOOT_ID_PATTERN)
    end

    def reboot_permitted?
      result = @runner.run(
        "/usr/bin/loginctl", "can-reboot",
        timeout_seconds: 5, max_output_bytes: 16 * 1024
      )
      result.success? && result.stdout.to_s.strip == "yes"
    end

    def read_boot_id
      value = File.read(BOOT_ID_PATH, 128).strip
      raise "current boot ID is invalid" unless value.match?(BOOT_ID_PATTERN)
      value
    end

    def default_active_work
      work = []
      Dir.glob(File.join(@root, "Soul", "music", "jobs", "job_*.json")).each do |path|
        next unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 256 * 1024
        status = JSON.parse(File.binread(path, 256 * 1024))["status"]
        work << "music_generation" if %w[accepted running].include?(status)
      rescue JSON::ParserError, Errno::ENOENT
        work << "unreadable_music_job"
      end
      leases = File.join(@root, "Soul", "runtime", "model_runtime", "leases")
      work << "model_runtime_lease" if Dir.exist?(leases) && Dir.children(leases).any? { |name| name.end_with?(".json") }
      backup_lock = File.join(@root, "Soul", "private", "backup", "operation.lock")
      work << "backup_operation" if lock_held?(backup_lock)
      work.uniq
    end

    def lock_held?(path)
      return false unless File.file?(path) && !File.symlink?(path)
      File.open(path, File::RDWR) do |file|
        acquired = file.flock(File::LOCK_EX | File::LOCK_NB)
        file.flock(File::LOCK_UN) if acquired
        !acquired
      end
    rescue StandardError
      true
    end

    def update_pending
      journal = read_pending
      basis = journal.reject { |key, _value| key == "journal_digest" }
      yield basis
      value = basis.merge("journal_digest" => digest(basis))
      atomic_json(@pending_path, value)
      value
    end

    def read_pending
      stat = File.lstat(@pending_path)
      raise "pending restore journal is unsafe" unless stat.file? && !stat.symlink? && (stat.mode & 0o077).zero?
      raise "pending restore journal exceeds size limit" if stat.size > MAX_FILE_BYTES
      journal = JSON.parse(File.binread(@pending_path, MAX_FILE_BYTES))
      raise "pending restore journal schema is invalid" unless journal["schema_version"] == JOURNAL_SCHEMA
      basis = journal.reject { |key, _value| key == "journal_digest" }
      raise "pending restore journal integrity mismatch" unless secure_equal?(journal["journal_digest"], digest(basis))
      journal
    end

    def prepare_directory
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      raise "maintenance state directory is unsafe" if File.symlink?(@state_root)
      File.chmod(0o700, @state_root)
    end

    def atomic_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      raise "restore journal exceeds size limit" if body.bytesize > MAX_FILE_BYTES
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(body)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
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
  end
end
