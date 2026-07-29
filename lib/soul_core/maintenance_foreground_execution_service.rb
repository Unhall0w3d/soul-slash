# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require "timeout"

require_relative "bounded_command_runner"
require_relative "maintenance_desktop_handoff"
require_relative "maintenance_passwordless_authority"
require_relative "maintenance_rehearsal_service"

module SoulCore
  class MaintenanceForegroundExecutionService
    PLAN_SCHEMA = "soul.maintenance.execution_plan.v1"
    TRANSACTION_SCHEMA = "soul.maintenance.transaction.v1"
    RECEIPT_SCHEMA = "soul.maintenance.receipt.v1"
    CONFIRMATION = "OPEN_MAINTENANCE_TERMINAL"
    MAX_RECEIPTS = 30
    MAX_FILE_BYTES = 512 * 1024
    MAX_DURATION_SECONDS = 4 * 60 * 60
    HANDOFF_START_TTL_SECONDS = 10 * 60
    MINIMUM_FREE_KIB = 2 * 1024 * 1024
    FIXED_PATHS = {
      "kitty" => "/usr/bin/kitty",
      "ruby" => "/usr/bin/ruby",
      "sudo" => "/usr/bin/sudo",
      "yay" => "/usr/bin/yay",
      "flatpak" => "/usr/bin/flatpak"
    }.freeze

    class TerminalLauncher
      def initialize(root:, timeout_seconds: MAX_DURATION_SECONDS)
        @root = File.expand_path(root)
        @timeout_seconds = Integer(timeout_seconds)
      end

      def call(transaction_path:, mode:)
        script = File.join(@root, "scripts", "soul-maintenance-transaction")
        argv = [
          FIXED_PATHS.fetch("kitty"),
          "--class", "soul-maintenance",
          "--title", "Soul / Guided Maintenance",
          FIXED_PATHS.fetch("ruby"), script,
          "--root", @root,
          "--transaction", transaction_path,
          "--mode", mode
        ]
        pid = Process.spawn(*argv, pgroup: true)
        status = nil
        Timeout.timeout(@timeout_seconds) { _pid, status = Process.wait2(pid) }
        {"status" => status.success? ? "complete" : "failed", "exit_status" => status.exitstatus, "argv" => argv}
      rescue Timeout::Error
        terminate_group(pid)
        {"status" => "failed", "exit_status" => nil, "reason" => "maintenance terminal exceeded its four-hour bound", "argv" => argv}
      rescue Errno::ENOENT => error
        {"status" => "failed", "exit_status" => nil, "reason" => error.message, "argv" => argv || []}
      end

      private

      def terminate_group(pid)
        return unless pid
        Process.kill("TERM", -pid)
        Timeout.timeout(3) { Process.wait(pid) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue Timeout::Error
        Process.kill("KILL", -pid) rescue nil
        Process.wait(pid) rescue nil
      end
    end

    def initialize(
      root: Dir.pwd,
      clock: -> { Time.now.utc },
      rehearsal_service: nil,
      runner: BoundedCommandRunner.new,
      terminal_launcher: nil,
      active_work_probe: nil,
      package_lock_probe: -> { File.exist?("/var/lib/pacman/db.lck") },
      privilege_transition_probe: nil,
      desktop_handoff: nil,
      live_execution_enabled: false,
      passwordless_authority_enabled: false,
      passwordless_authority: nil,
      id_generator: -> { SecureRandom.hex(8) }
    )
      @root = File.expand_path(root)
      @clock = clock
      @runner = runner
      @rehearsal_service = rehearsal_service || MaintenanceRehearsalService.new(root: @root, clock: @clock, runner: runner)
      @terminal_launcher = terminal_launcher || TerminalLauncher.new(root: @root)
      @active_work_probe = active_work_probe || method(:default_active_work)
      @package_lock_probe = package_lock_probe
      @privilege_transition_probe = privilege_transition_probe || method(:privilege_transition_available?)
      @desktop_handoff = desktop_handoff || MaintenanceDesktopHandoff.new(root: @root, clock: @clock, runner: runner)
      @live_execution_enabled = live_execution_enabled == true
      @passwordless_authority_enabled = passwordless_authority_enabled == true
      @passwordless_authority = passwordless_authority
      @id_generator = id_generator
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @transactions_root = File.join(@state_root, "transactions")
      @receipts_root = File.join(@state_root, "receipts")
      @lock_path = File.join(@state_root, "operation.lock")
    end

    def preview(force_database_refresh: false)
      a1 = @rehearsal_service.preview(force_database_refresh: force_database_refresh)
      return a1 unless a1["ok"]

      base = a1.dig("data", "plan")
      native_evidence = @desktop_handoff.native_evidence
      base["package_evidence"] = native_evidence.fetch("package_evidence") if native_evidence["available"]
      handoff_status = @desktop_handoff.status
      commands = a2_commands(base.fetch("commands"))
      authority = authority_status
      preflight = preflight(base, commands, handoff_status: handoff_status, native_evidence: native_evidence, authority: authority)
      basis = {
        "schema_version" => PLAN_SCHEMA,
        "risk_class" => "class_5",
        "owner_uid" => Process.uid,
        "force_database_refresh" => base.fetch("force_database_refresh"),
        "commands" => commands,
        "package_evidence" => stable_package_evidence(base.fetch("package_evidence")),
        "native_package_evidence" => native_evidence.slice("available", "generated_at", "expires_at", "evidence_digest", "reason"),
        "desktop_handoff" => handoff_status.slice("available", "registered_desktop_id", "problems"),
        "flatpak_installations" => base.fetch("flatpak_installations"),
        "preflight" => preflight,
        "authority" => authority,
        "authority_mode" => authority_mode(authority),
        "one_authentication_required" => authority_mode(authority) == "native_prompt",
        "interactive_terminal_required" => true,
        "automatic_reboot" => false,
        "live_execution_enabled" => @live_execution_enabled
      }
      digest_basis = basis.merge("preflight" => stable_preflight_for_digest(preflight))
      expected_digest = digest(digest_basis)
      plan = basis.merge(
        "plan_id" => "maintenance_a2_#{expected_digest[0, 16]}",
        "created_at" => @clock.call.iso8601,
        "expected_digest" => expected_digest,
        "confirmation" => CONFIRMATION,
        "human_review_required" => true,
        "execution_available" => @live_execution_enabled && preflight.fetch("live_blockers").empty?,
        "rehearsal_available" => preflight.fetch("rehearsal_blockers").empty?
      )
      outcome("complete", true, "A2 foreground transaction preview ready", {
        "plan" => plan,
        "expected_digest" => expected_digest,
        "confirmation" => CONFIRMATION,
        "read_only" => true,
        "restore_evidence" => {
          "restore_registry_digest" => base.fetch("restore_registry_digest"),
          "window_restore_summary" => base.fetch("window_snapshot").slice("restorable_count", "unsupported_count")
        }
      })
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "A2 preview failed safely: #{safe_error(error)}")
    end

    def rehearse(force_database_refresh:, expected_digest:, confirmation:)
      run_transaction(
        mode: "rehearsal",
        force_database_refresh: force_database_refresh,
        expected_digest: expected_digest,
        confirmation: confirmation
      )
    end

    def execute(force_database_refresh:, expected_digest:, confirmation:)
      return outcome("blocked_for_human_review", false, "live A2 execution is not enabled; complete code review and supervised authorization first") unless @live_execution_enabled

      reserve_live_transaction(
        force_database_refresh: force_database_refresh,
        expected_digest: expected_digest,
        confirmation: confirmation
      )
    end

    def reserve_native_evidence
      handoff = @desktop_handoff.status
      return outcome("blocked_for_human_review", false, "maintenance desktop handoff is unavailable", {"handoff" => handoff}) unless handoff["available"]
      reservation = @desktop_handoff.reserve_evidence
      outcome("complete", true, "native package evidence terminal reserved", reservation, "maintenance_evidence_reserved")
    rescue StandardError => error
      outcome("failed", false, "native package evidence reservation failed safely: #{safe_error(error)}")
    end

    def receipts(limit: MAX_RECEIPTS)
      prepare_directories
      count = [[Integer(limit), 1].max, MAX_RECEIPTS].min
      rows = receipt_paths.filter_map { |path| read_json(path, RECEIPT_SCHEMA) }
        .sort_by { |row| row.fetch("finished_at", "") }.reverse.first(count)
      outcome("complete", true, "maintenance receipts loaded", {
        "receipts" => rows,
        "live_execution_enabled" => @live_execution_enabled,
        "desktop_handoff" => @desktop_handoff.status,
        "native_package_evidence" => @desktop_handoff.native_evidence.except("package_evidence")
      })
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "maintenance receipts failed safely: #{safe_error(error)}")
    end

    private

    public

    def passwordless_authority_enabled? = @passwordless_authority_enabled

    def authority_status
      return {"ready" => false, "authority_mode" => "native_prompt", "enabled" => false} unless @passwordless_authority_enabled
      status = passwordless_authority.status
      data = status.fetch("data", {})
      data.merge("enabled" => true)
    rescue StandardError => error
      {"ready" => false, "authority_mode" => "native_prompt", "enabled" => true, "probe_error" => safe_error(error)}
    end

    def materialize_live_commands(commands, transaction_id)
      return commands unless @passwordless_authority_enabled
      commands.map do |command|
        adapter = command.fetch("adapter")
        next command.merge("argv" => [FIXED_PATHS.fetch("flatpak"), "update", "--user", "--noninteractive"]) if adapter == "flatpak.user_update"
        operation = case adapter
        when "arch_and_aur.full_upgrade" then "arch-update"
        when "flatpak.system_update" then "flatpak-system-update"
        else raise "unsupported passwordless maintenance adapter"
        end
        command.merge(
          "argv" => passwordless_authority.command_for(operation, transaction_id),
          "interactive" => false,
          "requires_existing_sudo_ticket" => false
        )
      end
    end

    def privilege_fields(transaction_id, reboot: false)
      if @passwordless_authority_enabled
        fields = {
          "authority_mode" => "root_owned_passwordless",
          "sudo_validation_argv" => [],
          "sudo_refresh_argv" => [],
          "sudo_invalidate_argv" => []
        }
        fields["reboot_argv"] = passwordless_authority.command_for("reboot", transaction_id) if reboot
        fields
      else
        fields = {
          "authority_mode" => "native_prompt",
          "sudo_validation_argv" => [FIXED_PATHS.fetch("sudo"), "-v"],
          "sudo_refresh_argv" => [FIXED_PATHS.fetch("sudo"), "-n", "-v"],
          "sudo_invalidate_argv" => [FIXED_PATHS.fetch("sudo"), "-k"]
        }
        fields["reboot_argv"] = [FIXED_PATHS.fetch("sudo"), "-n", "/usr/bin/systemctl", "reboot"] if reboot
        fields
      end
    end

    private

    def authority_mode(authority = authority_status)
      @passwordless_authority_enabled && authority["ready"] == true ? "root_owned_passwordless" : "native_prompt"
    end

    def passwordless_authority
      @passwordless_authority ||= MaintenancePasswordlessAuthority.new(root: @root)
    end

    def reserve_live_transaction(force_database_refresh:, expected_digest:, confirmation:)
      return outcome("blocked_for_human_review", false, "exact maintenance confirmation is required") unless confirmation.to_s == CONFIRMATION
      operation_lock = acquire_operation_lock
      return outcome("blocked_for_human_review", false, "another maintenance transaction is active") unless operation_lock
      fresh = preview(force_database_refresh: force_database_refresh)
      return fresh unless fresh["ok"]
      plan = fresh.dig("data", "plan")
      return outcome("blocked_for_human_review", false, "maintenance preview changed; review the fresh plan") unless secure_equal?(expected_digest, fresh.dig("data", "expected_digest"))
      blockers = plan.dig("preflight", "live_blockers") || plan.dig("preflight", "blockers")
      return outcome("blocked_for_human_review", false, "maintenance preflight is blocked", {"blockers" => blockers, "plan" => plan}) unless blockers.empty?
      return outcome("blocked_for_human_review", false, "this exact live maintenance plan is already reserved or completed") if used_live_digest?(expected_digest)
      transaction = build_transaction(plan, "live")
      handoff = @desktop_handoff.reserve_transaction(transaction)
      outcome("complete", true, "live maintenance terminal reserved", {
        "handoff" => handoff,
        "plan" => plan,
        "reboot_requested" => false
      }, "maintenance_live_transaction_reserved")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "maintenance transaction reservation failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
    end

    def run_transaction(mode:, force_database_refresh:, expected_digest:, confirmation:)
      raise ArgumentError, "maintenance mode is invalid" unless mode == "rehearsal"
      return outcome("blocked_for_human_review", false, "exact maintenance confirmation is required") unless confirmation.to_s == CONFIRMATION

      operation_lock = acquire_operation_lock
      return outcome("blocked_for_human_review", false, "another maintenance transaction is active") unless operation_lock

      fresh = preview(force_database_refresh: force_database_refresh)
      return fresh unless fresh["ok"]
      plan = fresh.dig("data", "plan")
      return outcome("blocked_for_human_review", false, "maintenance preview changed; review the fresh plan") unless secure_equal?(expected_digest, fresh.dig("data", "expected_digest"))
      blocker_key = mode == "live" ? "live_blockers" : "rehearsal_blockers"
      blockers = plan.dig("preflight", blocker_key) || plan.dig("preflight", "blockers")
      return outcome("blocked_for_human_review", false, "maintenance preflight is blocked", {"blockers" => blockers, "plan" => plan}) unless blockers.empty?
      return outcome("blocked_for_human_review", false, "this exact live maintenance plan already has a receipt") if mode == "live" && used_live_digest?(expected_digest)

      transaction = build_transaction(plan, mode)
      transaction_path = write_transaction(transaction)
      launch = @terminal_launcher.call(transaction_path: transaction_path, mode: mode)
      result = read_result(transaction)
      receipt = build_receipt(transaction, launch, result)
      write_receipt(receipt)
      prune_receipts
      FileUtils.rm_f(transaction_path)
      FileUtils.rm_f(transaction.fetch("result_path"))

      lifecycle = receipt.fetch("lifecycle_state")
      ok = lifecycle == "complete"
      outcome(lifecycle, ok, ok ? "#{mode} transaction completed" : "#{mode} transaction #{lifecycle}", {
        "receipt" => receipt,
        "plan" => plan,
        "reboot_requested" => false
      }, mode == "live" ? "host_packages_updated" : "maintenance_rehearsal_recorded")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("failed", false, "maintenance transaction failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
    end

    def a2_commands(a1_commands)
      a1_commands.map do |command|
        adapter = command.fetch("adapter")
        argv = command.fetch("argv")
        transformed = case adapter
        when "arch_and_aur.full_upgrade"
          raise "unexpected yay path" unless argv.first == FIXED_PATHS.fetch("yay")
          @passwordless_authority_enabled ?
            [MaintenancePasswordlessAuthority::HELPER_PATH, "arch-update", "<transaction_id>"] :
            [argv.first, "--sudoflags=-n", argv.fetch(1)]
        when "flatpak.user_update"
          raise "unexpected user Flatpak command" unless argv == [FIXED_PATHS.fetch("flatpak"), "update", "--user"]
          @passwordless_authority_enabled ? [*argv, "--noninteractive"] : argv
        when "flatpak.system_update"
          expected = [FIXED_PATHS.fetch("sudo"), "-n", FIXED_PATHS.fetch("flatpak"), "update", "--system"]
          raise "unexpected system Flatpak command" unless argv == expected
          @passwordless_authority_enabled ?
            [MaintenancePasswordlessAuthority::HELPER_PATH, "flatpak-system-update", "<transaction_id>"] :
            argv
        else
          raise "unsupported maintenance adapter"
        end
        {
          "adapter" => adapter,
          "argv" => transformed,
          "interactive" => !@passwordless_authority_enabled,
          "requires_existing_sudo_ticket" => !@passwordless_authority_enabled && adapter != "flatpak.user_update",
          "shell" => false
        }
      end
    end

    def preflight(base, commands, handoff_status:, native_evidence:, authority:)
      missing = FIXED_PATHS.filter_map do |name, path|
        name unless File.file?(path) && File.executable?(path)
      end
      script = File.join(@root, "scripts", "soul-maintenance-transaction")
      missing << "transaction_runner" unless File.file?(script)
      package_lock = @package_lock_probe.call == true
      package_processes = active_package_processes
      active_work = Array(@active_work_probe.call).map(&:to_s).uniq.sort.first(32)
      disks = disk_evidence
      common_blockers = []
      common_blockers << "required executables are unavailable: #{missing.join(', ')}" unless missing.empty?
      common_blockers << "pacman database lock is present" if package_lock
      common_blockers << "another package transaction appears active: #{package_processes.join(', ')}" unless package_processes.empty?
      common_blockers << "maintenance must run as the desktop owner, never root" if Process.uid.zero?
      common_blockers << "active Soul work must finish: #{active_work.join(', ')}" unless active_work.empty?
      common_blockers << "maintenance disk-space evidence is unavailable" if disks.empty?
      low = disks.select { |entry| entry.fetch("available_kib", 0) < MINIMUM_FREE_KIB }
      common_blockers << "maintenance free-space threshold is not met: #{low.map { |entry| entry['path'] }.join(', ')}" unless low.empty?
      common_blockers << "package assessment is unavailable" unless base.dig("package_evidence", "status") == "ok"
      common_blockers << "maintenance command count is invalid" unless commands.length.between?(1, 3)
      live_blockers = common_blockers.dup
      live_blockers << native_evidence.fetch("reason", "native package evidence is incomplete") unless native_evidence["available"]
      live_blockers << "package update evidence is incomplete" unless package_evidence_usable?(base.fetch("package_evidence"))
      live_blockers << "reviewed desktop handoff is unavailable" unless handoff_status["available"]
      if @passwordless_authority_enabled && authority["ready"] != true
        live_blockers << "root-owned maintenance authority is not installed exactly"
      end
      {
        "package_lock_present" => package_lock,
        "active_package_processes" => package_processes,
        "active_work" => active_work,
        "disk_free" => disks,
        "required_executables" => FIXED_PATHS.merge("transaction_runner" => script),
        "desktop_handoff_available" => handoff_status["available"],
        "native_package_evidence_available" => native_evidence["available"],
        "rehearsal_blockers" => common_blockers,
        "live_blockers" => live_blockers,
        "blockers" => live_blockers
      }
    end

    def active_package_processes
      result = @runner.run("ps", "-eo", "comm=", timeout_seconds: 5, max_output_bytes: 128 * 1024)
      return ["inventory_unavailable"] unless result.success? && !result.truncated
      names = result.stdout.lines.map { |line| File.basename(line.strip) }.select { |name| %w[pacman yay paru flatpak].include?(name) }
      names.uniq.sort.first(8)
    rescue StandardError
      ["inventory_unavailable"]
    end

    def package_evidence_usable?(evidence)
      pacman = evidence.dig("managers", "pacman", "updates")
      yay = evidence.dig("managers", "yay", "updates")
      return false unless pacman.is_a?(Hash) && yay.is_a?(Hash)
      %w[complete no_updates].include?(pacman["status"]) && %w[complete no_results].include?(yay["status"]) && pacman["truncated"] != true && yay["truncated"] != true
    end

    def privilege_transition_available?
      status = File.read("/proc/self/status", 64 * 1024)
      status.match?(/^NoNewPrivs:\s+0$/)
    rescue StandardError
      false
    end

    def disk_evidence
      %w[/ /home /tmp].filter_map do |path|
        result = @runner.run("df", "-Pk", path, timeout_seconds: 5, max_output_bytes: 16 * 1024)
        next unless result.success? && !result.truncated
        fields = result.stdout.lines.last.to_s.split
        next unless fields.length >= 6
        {"path" => path, "available_kib" => Integer(fields[-3]), "mount" => fields[-1].to_s.byteslice(0, 200)}
      rescue ArgumentError
        nil
      end.uniq { |entry| entry.fetch("mount") }
    end

    def stable_preflight_for_digest(preflight)
      {
        "package_lock_present" => preflight.fetch("package_lock_present"),
        "active_package_processes" => preflight.fetch("active_package_processes"),
        "active_work" => preflight.fetch("active_work"),
        "disk_free" => preflight.fetch("disk_free").map do |entry|
          {
            "path" => entry.fetch("path"),
            "mount" => entry.fetch("mount"),
            "minimum_free_kib" => MINIMUM_FREE_KIB,
            "threshold_met" => entry.fetch("available_kib", 0) >= MINIMUM_FREE_KIB
          }
        end,
        "required_executables" => preflight.fetch("required_executables"),
        "desktop_handoff_available" => preflight.fetch("desktop_handoff_available"),
        "native_package_evidence_available" => preflight.fetch("native_package_evidence_available"),
        "rehearsal_blockers" => preflight.fetch("rehearsal_blockers"),
        "live_blockers" => preflight.fetch("live_blockers")
      }
    end

    def stable_package_evidence(evidence)
      managers = %w[pacman yay flatpak].to_h do |name|
        manager = evidence.dig("managers", name) || {}
        checks = manager.select { |_key, value| value.is_a?(Hash) && value.key?("status") }
          .transform_values { |value| value.slice("status", "count", "items", "truncated") }
        [name, {"detected" => manager["detected"], "path" => manager["path"], "checks" => checks}]
      end
      {"status" => evidence["status"], "managers" => managers, "reboot_recommended" => evidence.dig("reboot", "recommended")}
    end

    def build_transaction(plan, mode)
      prepare_directories
      id = "maintenance_tx_#{@id_generator.call}"
      raise "transaction ID is invalid" unless id.match?(/\Amaintenance_tx_[a-f0-9]{16}\z/)
      privilege = mode == "live" ? privilege_fields(id) : {
        "authority_mode" => "rehearsal",
        "sudo_validation_argv" => [],
        "sudo_refresh_argv" => [],
        "sudo_invalidate_argv" => []
      }
      {
        "schema_version" => TRANSACTION_SCHEMA,
        "transaction_id" => id,
        "mode" => mode,
        "owner_uid" => Process.uid,
        "created_at" => @clock.call.iso8601,
        "deadline_at" => (@clock.call + (mode == "live" ? HANDOFF_START_TTL_SECONDS : MAX_DURATION_SECONDS)).iso8601,
        "plan_digest" => plan.fetch("expected_digest"),
        "force_database_refresh" => plan.fetch("force_database_refresh"),
        "source_boot_id" => File.read("/proc/sys/kernel/random/boot_id", 128).strip,
        "commands" => mode == "live" ? materialize_live_commands(plan.fetch("commands"), id) : rehearsal_commands,
        "reboot_allowed" => false,
        "result_path" => File.join(@transactions_root, "#{id}.result.json")
      }.merge(privilege)
    end

    def rehearsal_commands
      [
        {"adapter" => "fixture.authenticate", "argv" => [], "interactive" => false, "requires_existing_sudo_ticket" => false, "shell" => false},
        {"adapter" => "fixture.arch_aur_update", "argv" => [], "interactive" => false, "requires_existing_sudo_ticket" => false, "shell" => false},
        {"adapter" => "fixture.flatpak_update", "argv" => [], "interactive" => false, "requires_existing_sudo_ticket" => false, "shell" => false},
        {"adapter" => "fixture.verify", "argv" => [], "interactive" => false, "requires_existing_sudo_ticket" => false, "shell" => false}
      ]
    end

    def read_result(transaction)
      result = read_json(transaction.fetch("result_path"), "soul.maintenance.transaction_result.v1")
      raise "maintenance result transaction mismatch" unless result["transaction_id"] == transaction["transaction_id"]
      raise "maintenance result requested an impossible reboot" unless result["reboot_requested"] == false
      prompts = Integer(result.fetch("password_prompts", 0))
      raise "maintenance result password prompt count is invalid" unless prompts.between?(0, 1)
      raise "maintenance result command count is invalid" unless Array(result["commands"]).length <= 8
      result
    rescue Errno::ENOENT
      {
        "schema_version" => "soul.maintenance.transaction_result.v1",
        "transaction_id" => transaction.fetch("transaction_id"),
        "lifecycle_state" => "failed",
        "password_prompts" => 0,
        "commands" => [],
        "sudo_ticket_invalidated" => transaction.fetch("mode") == "rehearsal",
        "reboot_requested" => false,
        "reason" => "maintenance terminal ended without a valid result"
      }
    end

    def build_receipt(transaction, launch, result)
      lifecycle = result.fetch("lifecycle_state", "failed")
      lifecycle = "failed" unless %w[complete failed canceled blocked_for_human_review].include?(lifecycle)
      {
        "schema_version" => RECEIPT_SCHEMA,
        "receipt_id" => "maintenance_receipt_#{transaction.fetch('transaction_id').delete_prefix('maintenance_tx_')}",
        "transaction_id" => transaction.fetch("transaction_id"),
        "mode" => transaction.fetch("mode"),
        "authority_mode" => transaction.fetch("authority_mode", "native_prompt"),
        "plan_digest" => transaction.fetch("plan_digest"),
        "started_at" => transaction.fetch("created_at"),
        "finished_at" => @clock.call.iso8601,
        "lifecycle_state" => lifecycle,
        "terminal_exit_status" => launch["exit_status"],
        "password_prompts" => Integer(result.fetch("password_prompts", 0)),
        "commands" => Array(result["commands"]).first(8).map { |item| item.to_h.slice("adapter", "exit_status", "status") },
        "sudo_ticket_invalidated" => result["sudo_ticket_invalidated"] == true,
        "reboot_requested" => false,
        "reason" => result["reason"].to_s.byteslice(0, 500),
        "redacted" => true
      }
    end

    def prepare_directories
      [@state_root, @transactions_root, @receipts_root].each do |directory|
        FileUtils.mkdir_p(directory, mode: 0o700)
        raise "maintenance state directory is unsafe" if File.symlink?(directory)
        File.chmod(0o700, directory)
      end
    end

    def write_transaction(transaction)
      path = File.join(@transactions_root, "#{transaction.fetch('transaction_id')}.json")
      atomic_json(path, transaction, maximum: MAX_FILE_BYTES)
      path
    end

    def write_receipt(receipt)
      path = File.join(@receipts_root, "#{receipt.fetch('receipt_id')}.json")
      atomic_json(path, receipt, maximum: 64 * 1024)
    end

    def receipt_paths
      Dir.glob(File.join(@receipts_root, "maintenance_receipt_*.json")).first(MAX_RECEIPTS * 2)
    end

    def prune_receipts
      receipt_paths.sort_by { |path| File.mtime(path) }.reverse.drop(MAX_RECEIPTS).each { |path| FileUtils.rm_f(path) }
    end

    def used_live_digest?(expected_digest)
      @desktop_handoff.pending_live_digest?(expected_digest) || receipt_paths.any? do |path|
        receipt = read_json(path, RECEIPT_SCHEMA)
        receipt["mode"] == "live" && receipt["plan_digest"] == expected_digest
      rescue StandardError
        true
      end
    end

    def read_json(path, schema)
      stat = File.lstat(path)
      raise "maintenance state file is unsafe" unless stat.file? && !stat.symlink?
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
