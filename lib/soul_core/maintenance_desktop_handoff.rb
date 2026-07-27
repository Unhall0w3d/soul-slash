# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require "uri"

require_relative "bounded_command_runner"
require_relative "maintenance_transaction_runner"
require_relative "package_manager_assessor"

module SoulCore
  class MaintenanceDesktopHandoff
    RESERVATION_SCHEMA = "soul.maintenance.handoff_reservation.v1"
    EVIDENCE_SCHEMA = "soul.maintenance.native_package_evidence.v1"
    TRANSACTION_SCHEMA = "soul.maintenance.transaction.v1"
    RESULT_SCHEMA = "soul.maintenance.transaction_result.v1"
    RECEIPT_SCHEMA = "soul.maintenance.receipt.v1"
    URI_SCHEME = "soul-maintenance"
    DESKTOP_ID = "soul-maintenance.desktop"
    RESERVATION_TTL_SECONDS = 10 * 60
    EVIDENCE_TTL_SECONDS = 15 * 60
    MAX_FILE_BYTES = 512 * 1024
    MAX_RESERVATIONS = 16
    MAX_RECEIPTS = 30
    XDG_MIME = "/usr/bin/xdg-mime"
    GIO = "/usr/bin/gio"

    attr_reader :desktop_path

    def initialize(
      root: Dir.pwd,
      home: Dir.home,
      clock: -> { Time.now.utc },
      runner: BoundedCommandRunner.new,
      package_assessor: nil,
      transaction_runner_factory: nil,
      id_generator: -> { SecureRandom.hex(8) }
    )
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @clock = clock
      @runner = runner
      @package_assessor = package_assessor || PackageManagerAssessor.new(runner: runner, clock: clock)
      @transaction_runner_factory = transaction_runner_factory || -> { MaintenanceTransactionRunner.new(root: @root, clock: @clock) }
      @id_generator = id_generator
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @reservations_root = File.join(@state_root, "handoff_reservations")
      @transactions_root = File.join(@state_root, "transactions")
      @receipts_root = File.join(@state_root, "receipts")
      @evidence_path = File.join(@state_root, "native_package_evidence.json")
      @lock_path = File.join(@state_root, "operation.lock")
      @desktop_path = File.join(@home, ".local", "share", "applications", DESKTOP_ID)
    end

    def desktop_entry
      executable = File.join(@root, "scripts", "soul-maintenance-uri")
      icon = File.join(@root, "assets", "brand", "soul-account-avatar-150.png")
      [executable, icon].each do |path|
        raise "maintenance desktop handler requires a metacharacter-free project path" unless path.match?(%r{\A/[A-Za-z0-9_./+-]+\z})
      end
      <<~DESKTOP
        [Desktop Entry]
        Type=Application
        Version=1.0
        Name=Soul Guided Maintenance
        Comment=Open one reviewed Soul maintenance transaction
        TryExec=#{executable}
        Exec=#{executable} %u
        Icon=#{icon}
        Terminal=false
        NoDisplay=true
        Categories=Utility;
        MimeType=x-scheme-handler/soul-maintenance;
      DESKTOP
    end

    def status
      problems = []
      executable = File.join(@root, "scripts", "soul-maintenance-uri")
      problems << "maintenance URI handler is missing" unless File.file?(executable) && File.executable?(executable)
      if !File.file?(@desktop_path) || File.symlink?(@desktop_path)
        problems << "maintenance desktop handler is not installed"
      elsif File.size(@desktop_path) > 64 * 1024 || File.binread(@desktop_path, 64 * 1024) != desktop_entry
        problems << "maintenance desktop handler differs from the reviewed entry"
      elsif (File.stat(@desktop_path).mode & 0o777) != 0o644
        problems << "maintenance desktop handler mode is invalid"
      end
      registration = registered_desktop_id
      problems << "maintenance URI scheme is not registered to the reviewed handler" unless registration == DESKTOP_ID
      gio_registration = gio_registered_desktop_id
      problems << "desktop application registry cannot resolve the reviewed handler" unless gio_registration == DESKTOP_ID
      {
        "available" => problems.empty?,
        "desktop_path" => @desktop_path,
        "registered_desktop_id" => registration,
        "gio_registered_desktop_id" => gio_registration,
        "problems" => problems,
        "persistent_process" => false,
        "system_service" => false
      }
    rescue StandardError => error
      {
        "available" => false,
        "desktop_path" => @desktop_path,
        "registered_desktop_id" => nil,
        "gio_registered_desktop_id" => nil,
        "problems" => ["maintenance desktop handler check failed safely: #{safe_error(error)}"],
        "persistent_process" => false,
        "system_service" => false
      }
    end

    def reserve_evidence
      prepare_directories
      prune_expired_reservations
      raise "maintenance reservation limit is reached" if reservation_paths.length >= MAX_RESERVATIONS
      id = "maintenance_evidence_#{@id_generator.call}"
      raise "maintenance evidence reservation ID is invalid" unless id.match?(/\Amaintenance_evidence_[a-f0-9]{16}\z/)
      basis = {
        "schema_version" => RESERVATION_SCHEMA,
        "reservation_id" => id,
        "kind" => "evidence",
        "owner_uid" => Process.uid,
        "created_at" => @clock.call.iso8601,
        "expires_at" => (@clock.call + RESERVATION_TTL_SECONDS).iso8601
      }
      expected_digest = digest(basis)
      reservation = basis.merge("expected_digest" => expected_digest)
      atomic_json(File.join(@reservations_root, "#{id}.json"), reservation, maximum: 64 * 1024)
      {
        "reservation_id" => id,
        "expected_digest" => expected_digest,
        "launch_uri" => launch_uri("evidence", id, expected_digest),
        "expires_at" => reservation.fetch("expires_at")
      }
    end

    def reserve_transaction(transaction)
      prepare_directories
      prune_expired_reservations
      validate_transaction_reservation!(transaction)
      raise "maintenance reservation limit is reached" if reservation_paths.length >= MAX_RESERVATIONS
      id = transaction.fetch("transaction_id")
      digest_value = digest(transaction)
      sealed_transaction = transaction.merge("handoff_digest" => digest_value)
      path = File.join(@transactions_root, "#{id}.reserved.json")
      raise "maintenance transaction is already reserved" if File.exist?(path) || File.exist?(claimed_transaction_path(id))
      atomic_json(path, sealed_transaction, maximum: MAX_FILE_BYTES)
      {
        "transaction_id" => id,
        "expected_digest" => digest_value,
        "launch_uri" => launch_uri("transaction", id, digest_value),
        "deadline_at" => transaction.fetch("deadline_at")
      }
    end

    def native_evidence
      record = read_json(@evidence_path, EVIDENCE_SCHEMA)
      evidence_basis = record.reject { |key, _value| key == "evidence_digest" }
      return {"available" => false, "reason" => "native package evidence integrity mismatch"} unless secure_equal?(record["evidence_digest"], digest(evidence_basis))
      expires_at = Time.iso8601(record.fetch("expires_at"))
      return {"available" => false, "reason" => "native package evidence is stale"} unless expires_at > @clock.call
      return {"available" => false, "reason" => "native package evidence owner is invalid"} unless record["owner_uid"] == Process.uid
      evidence = record.fetch("package_evidence")
      return {"available" => false, "reason" => "native package evidence is incomplete"} unless package_evidence_usable?(evidence)
      {
        "available" => true,
        "generated_at" => record.fetch("generated_at"),
        "expires_at" => record.fetch("expires_at"),
        "evidence_digest" => record.fetch("evidence_digest"),
        "package_evidence" => evidence
      }
    rescue Errno::ENOENT
      {"available" => false, "reason" => "native package evidence has not been collected"}
    rescue StandardError => error
      {"available" => false, "reason" => "native package evidence failed validation: #{safe_error(error)}"}
    end

    def handle_uri(raw_uri)
      kind, id, digest_value = parse_uri(raw_uri)
      lock = acquire_operation_lock
      return result("blocked_for_human_review", false, "another maintenance operation is active") unless lock
      kind == "evidence" ? handle_evidence(id, digest_value) : handle_transaction(id, digest_value)
    rescue ArgumentError => error
      result("blocked_for_human_review", false, error.message)
    rescue StandardError => error
      result("failed", false, "maintenance desktop handoff failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(lock)
    end

    def pending_live_digest?(digest_value)
      Dir.glob(File.join(@transactions_root, "maintenance_tx_*.{reserved,claimed}.json")).any? do |path|
        transaction = read_json(path, TRANSACTION_SCHEMA)
        %w[live live_reboot].include?(transaction["mode"]) && secure_equal?(transaction["plan_digest"], digest_value)
      rescue StandardError
        true
      end
    end

    private

    def handle_evidence(id, digest_value)
      source = File.join(@reservations_root, "#{id}.json")
      claimed = File.join(@reservations_root, "#{id}.claimed.json")
      claim(source, claimed)
      reservation = read_json(claimed, RESERVATION_SCHEMA)
      validate_evidence_reservation!(reservation, id, digest_value)
      evidence = @package_assessor.assess(include_updates: true)
      raise "native package assessment did not complete" unless evidence["status"] == "ok"
      raise "native package assessment is incomplete" unless package_evidence_usable?(evidence)
      generated_at = @clock.call
      record_basis = {
        "schema_version" => EVIDENCE_SCHEMA,
        "owner_uid" => Process.uid,
        "reservation_id" => id,
        "generated_at" => generated_at.iso8601,
        "expires_at" => (generated_at + EVIDENCE_TTL_SECONDS).iso8601,
        "package_evidence" => evidence
      }
      record = record_basis.merge("evidence_digest" => digest(record_basis))
      atomic_json(@evidence_path, record, maximum: MAX_FILE_BYTES)
      FileUtils.rm_f(claimed)
      result("complete", true, "native package evidence collected", {
        "reservation_id" => id,
        "generated_at" => record.fetch("generated_at"),
        "expires_at" => record.fetch("expires_at"),
        "evidence_digest" => record.fetch("evidence_digest")
      }, "maintenance_native_evidence_recorded")
    end

    def handle_transaction(id, digest_value)
      source = File.join(@transactions_root, "#{id}.reserved.json")
      claimed = claimed_transaction_path(id)
      claim(source, claimed)
      transaction = read_json(claimed, TRANSACTION_SCHEMA)
      validate_claimed_transaction!(transaction, id, digest_value)
      result_record = @transaction_runner_factory.call.run(transaction_path: claimed, mode: transaction.fetch("mode"))
      receipt = build_receipt(transaction, result_record)
      write_receipt(receipt)
      FileUtils.rm_f(claimed)
      FileUtils.rm_f(transaction.fetch("result_path"))
      prune_receipts
      lifecycle = receipt.fetch("lifecycle_state")
      accepted = %w[complete awaiting_login].include?(lifecycle)
      mutation = transaction.fetch("mode") == "live_reboot" ? "host_reboot_requested" : "host_packages_updated"
      result(lifecycle, accepted, "live maintenance transaction #{lifecycle}", {"receipt" => receipt}, mutation)
    rescue StandardError => error
      result("failed", false, "live maintenance handoff failed safely: #{safe_error(error)}")
    end

    def parse_uri(raw_uri)
      text = raw_uri.to_s
      raise ArgumentError, "maintenance handoff URI is too long" if text.empty? || text.bytesize > 256
      uri = URI.parse(text)
      raise ArgumentError, "maintenance handoff URI scheme is invalid" unless uri.scheme == URI_SCHEME
      raise ArgumentError, "maintenance handoff URI authority is invalid" unless %w[evidence transaction].include?(uri.host)
      raise ArgumentError, "maintenance handoff URI contains unsupported fields" if uri.userinfo || uri.port || uri.query || uri.fragment
      segments = uri.path.to_s.split("/").reject(&:empty?)
      raise ArgumentError, "maintenance handoff URI path is invalid" unless segments.length == 2
      id, digest_value = segments
      expected_id = uri.host == "evidence" ? /\Amaintenance_evidence_[a-f0-9]{16}\z/ : /\Amaintenance_tx_[a-f0-9]{16}\z/
      raise ArgumentError, "maintenance handoff reservation ID is invalid" unless id.match?(expected_id)
      raise ArgumentError, "maintenance handoff digest is invalid" unless digest_value.match?(/\A[a-f0-9]{64}\z/)
      [uri.host, id, digest_value]
    rescue URI::InvalidURIError
      raise ArgumentError, "maintenance handoff URI is invalid"
    end

    def validate_evidence_reservation!(reservation, id, digest_value)
      raise "maintenance evidence reservation kind is invalid" unless reservation["kind"] == "evidence"
      raise "maintenance evidence reservation owner is invalid" unless reservation["owner_uid"] == Process.uid
      raise "maintenance evidence reservation ID mismatch" unless reservation["reservation_id"] == id
      raise "maintenance evidence reservation digest mismatch" unless secure_equal?(reservation["expected_digest"], digest_value)
      basis = reservation.reject { |key, _value| key == "expected_digest" }
      raise "maintenance evidence reservation integrity mismatch" unless secure_equal?(digest(basis), digest_value)
      raise "maintenance evidence reservation expired" unless Time.iso8601(reservation.fetch("expires_at")) > @clock.call
    end

    def validate_transaction_reservation!(transaction)
      raise "maintenance transaction schema is invalid" unless transaction["schema_version"] == TRANSACTION_SCHEMA
      raise "maintenance transaction mode is invalid" unless %w[live live_reboot].include?(transaction["mode"])
      raise "maintenance transaction owner is invalid" unless transaction["owner_uid"] == Process.uid
      raise "maintenance transaction ID is invalid" unless transaction["transaction_id"].to_s.match?(/\Amaintenance_tx_[a-f0-9]{16}\z/)
      raise "maintenance transaction digest is invalid" unless transaction["plan_digest"].to_s.match?(/\A[a-f0-9]{64}\z/)
      expected_reboot = transaction["mode"] == "live_reboot"
      raise "maintenance transaction reboot authority is invalid" unless transaction["reboot_allowed"] == expected_reboot
      if expected_reboot
        raise "maintenance transaction reboot vector is invalid" unless transaction["reboot_argv"] == ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reboot"]
        raise "maintenance transaction restore registry digest is invalid" unless transaction["restore_registry_digest"].to_s.match?(/\A[a-f0-9]{64}\z/)
      end
      deadline = Time.iso8601(transaction.fetch("deadline_at"))
      raise "maintenance transaction deadline is invalid" unless deadline > @clock.call && deadline <= @clock.call + RESERVATION_TTL_SECONDS
      expected_result = File.join(@transactions_root, "#{transaction.fetch('transaction_id')}.result.json")
      raise "maintenance transaction result path is invalid" unless transaction["result_path"] == expected_result
    end

    def validate_claimed_transaction!(transaction, id, digest_value)
      validate_transaction_reservation!(transaction)
      raise "maintenance transaction ID mismatch" unless transaction["transaction_id"] == id
      raise "maintenance transaction handoff digest is invalid" unless transaction["handoff_digest"].to_s.match?(/\A[a-f0-9]{64}\z/)
      basis = transaction.reject { |key, _value| key == "handoff_digest" }
      raise "maintenance transaction integrity mismatch" unless secure_equal?(digest(basis), digest_value)
      raise "maintenance transaction handoff digest mismatch" unless secure_equal?(transaction["handoff_digest"], digest_value)
    end

    def claim(source, destination)
      raise "maintenance handoff reservation is missing or already claimed" unless File.file?(source) && !File.symlink?(source)
      raise "maintenance handoff claim already exists" if File.exist?(destination) || File.symlink?(destination)
      File.rename(source, destination)
    end

    def build_receipt(transaction, result_record)
      lifecycle = result_record.fetch("lifecycle_state", "failed")
      lifecycle = "failed" unless %w[complete awaiting_login failed canceled blocked_for_human_review].include?(lifecycle)
      {
        "schema_version" => RECEIPT_SCHEMA,
        "receipt_id" => "maintenance_receipt_#{transaction.fetch('transaction_id').delete_prefix('maintenance_tx_')}",
        "transaction_id" => transaction.fetch("transaction_id"),
        "mode" => transaction.fetch("mode"),
        "plan_digest" => transaction.fetch("plan_digest"),
        "started_at" => transaction.fetch("created_at"),
        "finished_at" => @clock.call.iso8601,
        "lifecycle_state" => lifecycle,
        "terminal_exit_status" => %w[complete awaiting_login].include?(lifecycle) ? 0 : 1,
        "password_prompts" => Integer(result_record.fetch("password_prompts", 0)),
        "commands" => Array(result_record["commands"]).first(8).map { |item| item.to_h.slice("adapter", "exit_status", "status") },
        "sudo_ticket_invalidated" => result_record["sudo_ticket_invalidated"] == true,
        "reboot_requested" => result_record["reboot_requested"] == true,
        "reason" => result_record["reason"].to_s.byteslice(0, 500),
        "redacted" => true
      }
    end

    def write_receipt(receipt)
      atomic_json(File.join(@receipts_root, "#{receipt.fetch('receipt_id')}.json"), receipt, maximum: 64 * 1024)
    end

    def prune_receipts
      paths = Dir.glob(File.join(@receipts_root, "maintenance_receipt_*.json")).first(MAX_RECEIPTS * 2)
      paths.sort_by { |path| File.mtime(path) }.reverse.drop(MAX_RECEIPTS).each { |path| FileUtils.rm_f(path) }
    end

    def package_evidence_usable?(evidence)
      pacman = evidence.dig("managers", "pacman", "updates")
      yay = evidence.dig("managers", "yay", "updates")
      return false unless pacman.is_a?(Hash) && yay.is_a?(Hash)
      %w[complete no_updates].include?(pacman["status"]) &&
        %w[complete no_results].include?(yay["status"]) &&
        pacman["truncated"] != true && yay["truncated"] != true
    end

    def registered_desktop_id
      return nil unless File.executable?(XDG_MIME)
      execution = @runner.run(XDG_MIME, "query", "default", "x-scheme-handler/#{URI_SCHEME}", timeout_seconds: 5, max_output_bytes: 16 * 1024)
      return nil unless execution.success? && !execution.truncated
      execution.stdout.to_s.strip.byteslice(0, 200)
    end

    def gio_registered_desktop_id
      return nil unless File.executable?(GIO)
      execution = @runner.run(
        GIO, "mime", "x-scheme-handler/#{URI_SCHEME}",
        timeout_seconds: 5,
        max_output_bytes: 16 * 1024,
        env: {"LC_ALL" => "C"}
      )
      return nil unless execution.success? && !execution.truncated
      line = execution.stdout.to_s.lines.find { |value| value.start_with?("Default application for ") }
      line.to_s.split(": ", 2).last.to_s.strip.byteslice(0, 200)
    end

    def launch_uri(kind, id, digest_value)
      "#{URI_SCHEME}://#{kind}/#{id}/#{digest_value}"
    end

    def claimed_transaction_path(id)
      File.join(@transactions_root, "#{id}.claimed.json")
    end

    def reservation_paths
      (
        Dir.glob(File.join(@reservations_root, "maintenance_evidence_*.json")) +
        Dir.glob(File.join(@transactions_root, "maintenance_tx_*.{reserved,claimed}.json"))
      ).uniq
    end

    def prune_expired_reservations
      reservation_paths.each do |path|
        evidence = File.basename(path).start_with?("maintenance_evidence_")
        record = read_json(path, evidence ? RESERVATION_SCHEMA : TRANSACTION_SCHEMA)
        expiry = evidence ? record.fetch("expires_at") : record.fetch("deadline_at")
        FileUtils.rm_f(path) if Time.iso8601(expiry) <= @clock.call
      rescue StandardError
        next
      end
    end

    def prepare_directories
      [@state_root, @reservations_root, @transactions_root, @receipts_root].each do |directory|
        FileUtils.mkdir_p(directory, mode: 0o700)
        raise "maintenance state directory is unsafe" if File.symlink?(directory)
        File.chmod(0o700, directory)
      end
    end

    def read_json(path, schema)
      stat = File.lstat(path)
      raise "maintenance state file is unsafe" unless stat.file? && !stat.symlink? && (stat.mode & 0o077).zero?
      raise "maintenance state file exceeds size limit" if stat.size > MAX_FILE_BYTES
      data = JSON.parse(File.binread(path, MAX_FILE_BYTES))
      raise "maintenance state schema is invalid" unless data["schema_version"] == schema
      data
    rescue JSON::ParserError
      raise "maintenance state is invalid JSON"
    end

    def atomic_json(path, value, maximum:)
      body = JSON.pretty_generate(value) + "\n"
      raise "maintenance state exceeds size limit" if body.bytesize > maximum
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

    def acquire_operation_lock
      prepare_directories
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

    def secure_equal?(left, right)
      a = left.to_s
      b = right.to_s
      return false unless a.bytesize == 64 && b.bytesize == 64
      result_value = 0
      a.bytes.zip(b.bytes) { |x, y| result_value |= x ^ y }
      result_value.zero?
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))

    def safe_error(error) = "#{error.class}: #{error.message}".byteslice(0, 500)

    def result(lifecycle, ok, reason, data = {}, mutation = "none")
      {"lifecycle_state" => lifecycle, "ok" => ok, "reason" => reason, "data" => data, "mutation" => mutation}
    end
  end
end
