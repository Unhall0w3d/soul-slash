# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "bounded_command_runner"
require_relative "maintenance_reboot_coordinator"
require_relative "maintenance_rehearsal_service"

module SoulCore
  class MaintenanceSessionRestorer
    MAX_FILE_BYTES = 512 * 1024
    MAX_RECORDS = 32
    SESSION_WAIT_SECONDS = 90
    WINDOW_WAIT_SECONDS = 20
    MAX_RETRIES = 1
    RECEIPT_SCHEMA = "soul.maintenance.receipt.v1"

    class HyprlandAdapter
      def initialize(
        runner: BoundedCommandRunner.new,
        sleeper: ->(seconds) { sleep(seconds) },
        user_id: Process.uid
      )
        @runner = runner
        @sleeper = sleeper
        @user_id = Integer(user_id)
      end

      def wait_ready(timeout_seconds)
        attempts = [(Integer(timeout_seconds) / 2), 1].max
        attempts.times do
          return true if json("monitors", expected: Array)&.any?
          @sleeper.call(2)
        end
        false
      end

      def windows
        json("clients", expected: Array) || []
      end

      def process_running?(identity)
        execution = @runner.run(
          "/usr/bin/pgrep", "-u", @user_id.to_s, "-x", identity.to_s,
          timeout_seconds: 5, max_output_bytes: 16 * 1024
        )
        execution.success?
      end

      def launch(entry_id, argv, attempt)
        unit = "soul-restore-#{entry_id.gsub(/[^a-zA-Z0-9_.-]/, "-")}-#{attempt}"
        execution = @runner.run(
          "/usr/bin/systemd-run", "--user", "--quiet", "--collect", "--no-block",
          "--unit", unit, "--", *argv,
          timeout_seconds: 10, max_output_bytes: 32 * 1024
        )
        execution.success?
      end

      def wait_for_window(identities, excluded_addresses, timeout_seconds)
        attempts = [(Integer(timeout_seconds) / 2), 1].max
        attempts.times do
          match = windows.find do |window|
            address = window["address"].to_s
            classes = [window["initialClass"], window["class"]].map { |value| value.to_s.downcase }
            !excluded_addresses.include?(address) && (classes & identities).any? && address.match?(/\A0x[a-fA-F0-9]+\z/)
          end
          return match if match
          @sleeper.call(2)
        end
        nil
      end

      def place_window(window, record)
        address = window.fetch("address").to_s
        return false unless address.match?(/\A0x[a-fA-F0-9]+\z/)
        workspace = record.fetch("workspace", {})
        target = workspace["id"].to_i.positive? ? workspace["id"].to_i.to_s : workspace["name"].to_s
        return false if target.empty? || !target.match?(/\A(?:[1-9][0-9]{0,3}|[A-Za-z0-9_.-]{1,64})\z/)

        return false unless dispatch("movetoworkspacesilent", "#{target},address:#{address}")
        return false if record["floating"] == true && window["floating"] != true && !dispatch("togglefloating", "address:#{address}")
        return false if record["pinned"] == true && window["pinned"] != true && !dispatch("pin", "address:#{address}")
        fullscreen = Integer(record.fetch("fullscreen", 0)) rescue 0
        if fullscreen.positive? && window["fullscreen"].to_i.zero?
          return false unless dispatch("focuswindow", "address:#{address}")
          return false unless dispatch("fullscreen", fullscreen.to_s)
        end
        true
      end

      def activate_workspace(workspace)
        target = workspace["id"].to_i.positive? ? workspace["id"].to_i.to_s : workspace["name"].to_s
        return false if target.empty? || !target.match?(/\A(?:[1-9][0-9]{0,3}|[A-Za-z0-9_.-]{1,64})\z/)
        dispatch("workspace", target)
      end

      private

      def json(subject, expected:)
        execution = @runner.run(
          "/usr/bin/hyprctl", "-j", subject,
          timeout_seconds: 5, max_output_bytes: 512 * 1024
        )
        return nil unless execution.success? && !execution.truncated
        value = JSON.parse(execution.stdout)
        value if value.is_a?(expected)
      rescue JSON::ParserError
        nil
      end

      def dispatch(action, *arguments)
        execution = @runner.run(
          "/usr/bin/hyprctl", "dispatch", action, *arguments,
          timeout_seconds: 5, max_output_bytes: 16 * 1024
        )
        execution.success?
      end
    end

    def initialize(
      root: Dir.pwd,
      clock: -> { Time.now.utc },
      adapter: nil,
      rehearsal_service: nil,
      boot_id_reader: nil
    )
      @root = File.expand_path(root)
      @clock = clock
      @adapter = adapter || HyprlandAdapter.new
      @rehearsal_service = rehearsal_service || MaintenanceRehearsalService.new(root: @root, clock: @clock)
      @boot_id_reader = boot_id_reader || -> { File.read(MaintenanceRebootCoordinator::BOOT_ID_PATH, 128).strip }
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @pending_path = File.join(@state_root, "pending_restore.json")
      @journals_root = File.join(@state_root, "journals")
      @receipts_root = File.join(@state_root, "receipts")
    end

    def run
      return outcome("complete", true, "no pending maintenance restoration", {"restored" => 0, "skipped" => 0}) unless File.exist?(@pending_path)

      journal = read_pending
      current_boot = validated_boot_id
      validate_resume!(journal, current_boot)
      journal = update_journal(journal) do |basis|
        basis["current_state"] = "restoring"
        basis["attempt_boot_id"] = current_boot
      end
      unless @adapter.wait_ready(SESSION_WAIT_SECONDS)
        return finalize(journal, "blocked_for_human_review", "Hyprland session did not become ready within 90 seconds", [])
      end

      registry = @rehearsal_service.restore_registry
      raise "restore registry changed after reboot" unless secure_equal?(journal.fetch("restore_registry_digest"), digest(registry))
      attempts = restore_records(journal.fetch("window_snapshot"), registry)
      active_restored = @adapter.activate_workspace(journal.dig("window_snapshot", "active_workspace") || {})
      attempts << {"kind" => "workspace", "status" => active_restored ? "complete" : "failed", "reason" => "restore previously active workspace"}
      failures = attempts.count { |item| item["status"] != "complete" && item["status"] != "skipped" }
      state = failures.zero? ? "complete" : "blocked_for_human_review"
      reason = failures.zero? ? "one-shot maintenance restoration completed" : "#{failures} restoration records require human review"
      finalize(journal, state, reason, attempts)
    rescue StandardError => error
      if defined?(journal) && journal
        finalize(journal, "blocked_for_human_review", error.message, [])
      else
        quarantine_invalid(error.message)
      end
    end

    private

    def restore_records(snapshot, registry)
      windows = Array(snapshot["windows"]).select { |item| item["restore_status"] == "restorable" }
      backgrounds = Array(snapshot["background_applications"]).select { |item| item["restore_status"] == "restorable" }
      raise "restore record count exceeds the A3 bound" if windows.length + backgrounds.length > MAX_RECORDS
      registry_by_id = registry.fetch("entries").to_h { |entry| [entry.fetch("entry_id"), entry] }
      existing = @adapter.windows
      used_addresses = []
      results = []

      windows.each do |record|
        entry = validated_entry(record, registry_by_id)
        identities = entry.fetch("identities")
        existing_match = existing.find do |window|
          address = window["address"].to_s
          classes = [window["initialClass"], window["class"]].map { |value| value.to_s.downcase }
          !used_addresses.include?(address) && (classes & identities).any?
        end
        window = existing_match
        unless window
          excluded = existing.map { |item| item["address"].to_s }
          (MAX_RETRIES + 1).times do |attempt|
            next unless @adapter.launch(entry.fetch("entry_id"), entry.fetch("argv"), attempt)
            window = @adapter.wait_for_window(identities, excluded, WINDOW_WAIT_SECONDS)
            break if window
          end
        end
        if window && @adapter.place_window(window, record)
          used_addresses << window["address"].to_s
          results << {"kind" => "window", "entry_id" => entry.fetch("entry_id"), "status" => "complete"}
        else
          results << {"kind" => "window", "entry_id" => entry.fetch("entry_id"), "status" => "failed", "reason" => "window did not launch or place within the bound"}
        end
      end

      backgrounds.each do |record|
        entry = validated_entry(record, registry_by_id)
        identity = record.fetch("process_identity").to_s
        raise "background process identity changed after review" unless Array(entry["process_identities"]).include?(identity)
        if @adapter.process_running?(identity)
          results << {"kind" => "background", "entry_id" => entry.fetch("entry_id"), "status" => "skipped", "reason" => "already running after login"}
          next
        end
        launched = false
        (MAX_RETRIES + 1).times do |attempt|
          launched = @adapter.launch(entry.fetch("entry_id"), entry.fetch("argv"), attempt)
          break if launched
        end
        results << {"kind" => "background", "entry_id" => entry.fetch("entry_id"), "status" => launched ? "complete" : "failed", "reason" => launched ? "launched because absent" : "launch failed within retry bound"}
      end
      results
    end

    def validated_entry(record, registry)
      entry = registry[record.fetch("restore_entry_id")]
      raise "restore record is no longer allowlisted" unless entry
      raise "restore executable is unavailable" unless entry["executable_available"]
      raise "restore launch vector changed after review" unless record.fetch("launch_argv") == entry.fetch("argv")
      entry
    end

    def validate_resume!(journal, current_boot)
      raise "pending restore journal owner is invalid" unless journal["owner_uid"] == Process.uid
      raise "pending restore journal was not authorized for reboot" unless journal["reboot_requested"] == true
      raise "pending restore journal state is invalid" unless journal["current_state"] == "reboot_requested"
      raise "pending restore journal is stale" unless Time.iso8601(journal.fetch("resume_deadline_at")) > @clock.call
      raise "maintenance reboot did not change the boot ID" if journal["source_boot_id"] == current_boot
      raise "maintenance restoration was already attempted on this boot" if journal["attempt_boot_id"]
    end

    def read_pending
      stat = File.lstat(@pending_path)
      raise "pending restore journal is unsafe" unless stat.file? && !stat.symlink? && (stat.mode & 0o077).zero?
      raise "pending restore journal exceeds size limit" if stat.size > MAX_FILE_BYTES
      journal = JSON.parse(File.binread(@pending_path, MAX_FILE_BYTES))
      raise "pending restore journal schema is invalid" unless journal["schema_version"] == MaintenanceRebootCoordinator::JOURNAL_SCHEMA
      basis = journal.reject { |key, _value| key == "journal_digest" }
      raise "pending restore journal integrity mismatch" unless secure_equal?(journal["journal_digest"], digest(basis))
      journal
    rescue JSON::ParserError
      raise "pending restore journal is invalid JSON"
    end

    def update_journal(journal)
      basis = journal.reject { |key, _value| key == "journal_digest" }
      yield basis
      value = basis.merge("journal_digest" => digest(basis))
      atomic_json(@pending_path, value)
      value
    end

    def finalize(journal, state, reason, attempts)
      terminal = update_journal(journal) do |basis|
        basis["current_state"] = state
        basis["finished_at"] = @clock.call.iso8601
        basis["reason"] = reason.to_s.byteslice(0, 500)
        basis["restore_attempts"] = attempts.first(MAX_RECORDS + 1)
      end
      prepare_directories
      archive = File.join(@journals_root, "#{terminal.fetch('journal_id')}.json")
      File.rename(@pending_path, archive)
      receipt = build_receipt(terminal)
      atomic_json(File.join(@receipts_root, receipt.fetch("receipt_id") + ".json"), receipt)
      prune_receipts
      outcome(state, state == "complete", reason, {
        "receipt" => receipt,
        "restored" => attempts.count { |item| item["status"] == "complete" },
        "skipped" => attempts.count { |item| item["status"] == "skipped" }
      }, mutation: "host_session_restored")
    end

    def quarantine_invalid(reason)
      prepare_directories
      if File.file?(@pending_path) && !File.symlink?(@pending_path)
        destination = File.join(@journals_root, "invalid_restore_#{@clock.call.to_i}.json")
        File.rename(@pending_path, destination)
      end
      outcome("blocked_for_human_review", false, reason.to_s.byteslice(0, 500), {"restored" => 0, "skipped" => 0}, mutation: "maintenance_journal_quarantined")
    rescue StandardError
      outcome("failed", false, "invalid pending restoration could not be quarantined safely", {"restored" => 0, "skipped" => 0})
    end

    def build_receipt(journal)
      attempts = Array(journal["restore_attempts"])
      {
        "schema_version" => RECEIPT_SCHEMA,
        "receipt_id" => "maintenance_receipt_#{journal.fetch('transaction_id').delete_prefix('maintenance_tx_')}",
        "transaction_id" => journal.fetch("transaction_id"),
        "mode" => "live_reboot",
        "plan_digest" => journal.fetch("plan_digest"),
        "started_at" => journal.fetch("created_at"),
        "finished_at" => journal.fetch("finished_at"),
        "lifecycle_state" => journal.fetch("current_state"),
        "terminal_exit_status" => journal.fetch("current_state") == "complete" ? 0 : 1,
        "password_prompts" => 1,
        "commands" => Array(journal["update_commands"]).first(8).map { |item| item.to_h.slice("adapter", "exit_status", "status") },
        "sudo_ticket_invalidated" => true,
        "reboot_requested" => true,
        "restore_summary" => {
          "complete" => attempts.count { |item| item["status"] == "complete" },
          "skipped" => attempts.count { |item| item["status"] == "skipped" },
          "failed" => attempts.count { |item| item["status"] == "failed" }
        },
        "reason" => journal["reason"].to_s.byteslice(0, 500),
        "redacted" => true
      }
    end

    def validated_boot_id
      value = @boot_id_reader.call.to_s.strip
      raise "current boot ID is invalid" unless value.match?(MaintenanceRebootCoordinator::BOOT_ID_PATTERN)
      value
    end

    def prepare_directories
      [@state_root, @journals_root, @receipts_root].each do |path|
        FileUtils.mkdir_p(path, mode: 0o700)
        raise "maintenance state directory is unsafe" if File.symlink?(path)
        File.chmod(0o700, path)
      end
    end

    def atomic_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      raise "maintenance state exceeds size limit" if body.bytesize > MAX_FILE_BYTES
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

    def prune_receipts
      paths = Dir.glob(File.join(@receipts_root, "maintenance_receipt_*.json"))
      paths.sort_by { |path| File.mtime(path) }.reverse.drop(30).each { |path| FileUtils.rm_f(path) }
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

    def outcome(state, ok, reason, data, mutation: "none")
      {"lifecycle_state" => state, "ok" => ok, "reason" => reason, "data" => data, "mutation" => mutation}
    end
  end
end
