# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "thread"
require "time"
require "timeout"

require_relative "maintenance_reboot_coordinator"

module SoulCore
  class MaintenanceTransactionRunner
    TRANSACTION_SCHEMA = "soul.maintenance.transaction.v1"
    RESULT_SCHEMA = "soul.maintenance.transaction_result.v1"
    MAX_FILE_BYTES = 512 * 1024
    MAX_DURATION_SECONDS = 4 * 60 * 60
    REFRESH_INTERVAL_SECONDS = 60
    TERMINAL_STATES = %w[complete failed canceled blocked_for_human_review].freeze

    def initialize(
      root: Dir.pwd,
      clock: -> { Time.now.utc },
      command_executor: nil,
      reboot_coordinator: nil,
      sleeper: ->(seconds) { sleep(seconds) },
      output: $stdout
    )
      @root = File.expand_path(root)
      @clock = clock
      @command_executor = command_executor || method(:spawn_interactive)
      @reboot_coordinator = reboot_coordinator || MaintenanceRebootCoordinator.new(root: @root, clock: @clock)
      @sleeper = sleeper
      @output = output
      @canceled = false
      @active_pid = nil
      @keeper_stop = false
      @keeper_failed = false
      @keeper_thread = nil
      @previous_handlers = {}
    end

    def run(transaction_path:, mode:)
      transaction = read_transaction(transaction_path)
      validate_mode!(transaction, mode)
      install_signal_handlers
      print_header(transaction)
      result = mode == "rehearsal" ? run_rehearsal(transaction) : run_live(transaction)
      stop_keeper
      result["sudo_ticket_invalidated"] = invalidate_ticket(transaction)
      write_result(transaction.fetch("result_path"), result)
      result
    rescue Interrupt
      result = failure_result(transaction, "canceled", "maintenance transaction canceled")
      result["sudo_ticket_invalidated"] = invalidate_ticket(transaction) if result
      write_result(transaction.fetch("result_path"), result) if transaction
      result
    rescue StandardError => error
      result = failure_result(transaction, "failed", "#{error.class}: #{error.message}")
      result["sudo_ticket_invalidated"] = invalidate_ticket(transaction) if result
      write_result(transaction.fetch("result_path"), result) if transaction
      result
    ensure
      stop_keeper
      invalidate_ticket(transaction) if transaction && result && result["sudo_ticket_invalidated"] != true
      restore_signal_handlers
    end

    private

    def run_rehearsal(transaction)
      records = []
      transaction.fetch("commands").each do |command|
        raise "rehearsal transaction contains a host command" unless command.fetch("argv").empty?
        raise Interrupt if @canceled
        adapter = command.fetch("adapter")
        @output.puts("[rehearsal] #{adapter}")
        records << {"adapter" => adapter, "exit_status" => 0, "status" => "simulated"}
      end
      result_for(transaction, "complete", records, password_prompts: 0, ticket_invalidated: true)
    end

    def run_live(transaction)
      deadline = Time.iso8601(transaction.fetch("deadline_at"))
      raise "maintenance transaction deadline is invalid" if deadline <= @clock.call || deadline > @clock.call + MAX_DURATION_SECONDS + 60
      validate_live_vectors!(transaction)

      return run_passwordless(transaction, deadline) if transaction.fetch("authority_mode", "native_prompt") == "root_owned_passwordless"

      @output.puts("Administrator authentication is required once.")
      auth = execute(transaction.fetch("sudo_validation_argv"), deadline: deadline)
      return result_for(transaction, @canceled ? "canceled" : "failed", [{"adapter" => "sudo.validate", "exit_status" => auth, "status" => status_for(auth)}], password_prompts: 1, reason: "administrator authentication did not complete") unless auth.zero?

      records = [{"adapter" => "sudo.validate", "exit_status" => 0, "status" => "complete"}]
      start_keeper(transaction.fetch("sudo_refresh_argv"), deadline)
      transaction.fetch("commands").each do |command|
        raise Interrupt if @canceled
        raise "sudo ticket refresh failed" if @keeper_failed
        @output.puts("\n[#{command.fetch('adapter')}] #{display_command(command.fetch('argv'))}")
        status = execute(command.fetch("argv"), deadline: deadline)
        records << {"adapter" => command.fetch("adapter"), "exit_status" => status, "status" => status_for(status)}
        return result_for(transaction, @canceled ? "canceled" : "failed", records, password_prompts: 1, reason: "maintenance command did not complete") unless status.zero?
        raise "sudo ticket refresh failed" if @keeper_failed
      end

      stop_keeper
      return run_reboot(transaction, records, deadline) if transaction.fetch("mode") == "live_reboot"

      result_for(transaction, "complete", records, password_prompts: 1)
    end

    def run_passwordless(transaction, deadline)
      @output.puts("Root-owned fixed-operation authority verified. No password or routine package input is required.")
      records = []
      transaction.fetch("commands").each do |command|
        raise Interrupt if @canceled
        @output.puts("\n[#{command.fetch('adapter')}] #{display_command(command.fetch('argv'))}")
        status = execute(command.fetch("argv"), deadline: deadline)
        records << {"adapter" => command.fetch("adapter"), "exit_status" => status, "status" => status_for(status)}
        return result_for(transaction, @canceled ? "canceled" : "failed", records, password_prompts: 0, ticket_invalidated: true, reason: "maintenance command did not complete") unless status.zero?
      end
      return run_reboot(transaction, records, deadline) if transaction.fetch("mode") == "live_reboot"
      result_for(transaction, "complete", records, password_prompts: 0, ticket_invalidated: true)
    end

    def run_reboot(transaction, records, deadline)
      @output.puts("\n[A3] Revalidating reboot and one-shot restoration postconditions.")
      @reboot_coordinator.prepare(transaction)
      @reboot_coordinator.mark_reboot_requested
      @output.puts("[A3] Durable restore journal written. Requesting one reboot.")
      status = execute(transaction.fetch("reboot_argv"), deadline: deadline)
      records << {"adapter" => "system.reboot", "exit_status" => status, "status" => status_for(status)}
      unless status.zero?
        @reboot_coordinator.mark_reboot_failed("reviewed reboot command did not complete")
        return result_for(transaction, "failed", records, password_prompts: password_prompts_for(transaction), ticket_invalidated: passwordless?(transaction), reason: "reviewed reboot command did not complete")
      end
      result_for(transaction, "awaiting_login", records, password_prompts: password_prompts_for(transaction), ticket_invalidated: passwordless?(transaction), reboot_requested: true)
    rescue StandardError => error
      @reboot_coordinator.mark_reboot_failed(error.message)
      result_for(transaction, "blocked_for_human_review", records, password_prompts: password_prompts_for(transaction), ticket_invalidated: passwordless?(transaction), reason: error.message)
    end

    def execute(argv, deadline:)
      remaining = deadline - @clock.call
      raise "maintenance transaction exceeded its four-hour bound" unless remaining.positive?
      Integer(@command_executor.call(argv, remaining, method(:register_active_pid)))
    ensure
      @active_pid = nil
    end

    def spawn_interactive(argv, timeout_seconds, pid_callback)
      # The child must remain in the visible terminal's foreground process
      # group. Moving sudo/yay into a new background group prevents them from
      # safely controlling TTY echo and reading interactive input.
      pid = Process.spawn(*argv, in: $stdin, out: $stdout, err: $stderr)
      pid_callback.call(pid)
      status = nil
      Timeout.timeout(timeout_seconds) { _pid, status = Process.wait2(pid) }
      status.exitstatus || 1
    rescue Timeout::Error
      terminate_process(pid)
      124
    rescue Errno::ENOENT
      127
    end

    def register_active_pid(pid)
      @active_pid = Integer(pid)
    end

    def start_keeper(argv, deadline)
      @keeper_stop = false
      @keeper_failed = false
      @keeper_thread = Thread.new do
        loop do
          @sleeper.call(REFRESH_INTERVAL_SECONDS)
          break if @keeper_stop || @clock.call >= deadline
          status = @command_executor.call(argv, [deadline - @clock.call, 30].min, ->(_pid) {})
          unless Integer(status).zero?
            @keeper_failed = true
            terminate_process(@active_pid)
            break
          end
        end
      rescue StandardError
        @keeper_failed = true
        terminate_process(@active_pid)
      end
      @keeper_thread.report_on_exception = false
    end

    def stop_keeper
      return unless @keeper_thread
      @keeper_stop = true
      @keeper_thread.kill if @keeper_thread.alive?
      @keeper_thread.join(2)
      @keeper_thread = nil
    end

    def invalidate_ticket(transaction)
      return true unless transaction && %w[live live_reboot].include?(transaction["mode"])
      return true if passwordless?(transaction)
      argv = transaction.fetch("sudo_invalidate_argv", [])
      return false if argv.empty?
      Integer(@command_executor.call(argv, 30, ->(_pid) {})).zero?
    rescue StandardError
      false
    end

    def validate_live_vectors!(transaction)
      authority_mode = transaction.fetch("authority_mode", "native_prompt")
      raise "maintenance authority mode is invalid" unless %w[native_prompt root_owned_passwordless].include?(authority_mode)
      if transaction.fetch("mode") == "live"
        raise "reboot authority is prohibited in A2" unless transaction["reboot_allowed"] == false
        raise "A2 contains a reboot vector" if transaction.key?("reboot_argv")
      else
        raise "reboot authority is required only for A3" unless transaction["mode"] == "live_reboot" && transaction["reboot_allowed"] == true
        expected_reboot = if authority_mode == "root_owned_passwordless"
          ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "reboot", transaction.fetch("transaction_id")]
        else
          ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reboot"]
        end
        raise "A3 reboot vector is invalid" unless transaction["reboot_argv"] == expected_reboot
      end
      expected_privilege = authority_mode == "root_owned_passwordless" ? [[], [], []] : [
        ["/usr/bin/sudo", "-v"],
        ["/usr/bin/sudo", "-n", "-v"],
        ["/usr/bin/sudo", "-k"]
      ]
      actual_privilege = [
        transaction["sudo_validation_argv"],
        transaction["sudo_refresh_argv"],
        transaction["sudo_invalidate_argv"]
      ]
      raise "sudo lifecycle vectors are invalid" unless actual_privilege == expected_privilege
      commands = transaction.fetch("commands")
      raise "maintenance command count is invalid" unless commands.is_a?(Array) && commands.length.between?(1, 3)
      commands.each do |command|
        argv = command.fetch("argv")
        allowed = case command.fetch("adapter")
        when "arch_and_aur.full_upgrade"
          if authority_mode == "root_owned_passwordless"
            argv == ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "arch-update", transaction.fetch("transaction_id")]
          else
            [
              ["/usr/bin/yay", "--sudoflags=-n", "-Syu"],
              ["/usr/bin/yay", "--sudoflags=-n", "-Syyu"]
            ].include?(argv)
          end
        when "flatpak.user_update"
          expected = ["/usr/bin/flatpak", "update", "--user"]
          expected << "--noninteractive" if authority_mode == "root_owned_passwordless"
          argv == expected
        when "flatpak.system_update"
          expected = if authority_mode == "root_owned_passwordless"
            ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "flatpak-system-update", transaction.fetch("transaction_id")]
          else
            ["/usr/bin/sudo", "-n", "/usr/bin/flatpak", "update", "--system"]
          end
          argv == expected
        else
          false
        end
        raise "maintenance command vector is not allowlisted" unless allowed
        raise "maintenance command shell boundary is invalid" unless command["shell"] == false
      end
    end

    def read_transaction(path)
      expanded = File.expand_path(path)
      boundary = File.join(@root, "Soul", "private", "host_maintenance", "transactions")
      raise "transaction path is outside private maintenance state" unless expanded.start_with?("#{boundary}/")
      stat = File.lstat(expanded)
      raise "transaction request is unsafe" unless stat.file? && !stat.symlink? && stat.size <= MAX_FILE_BYTES
      transaction = JSON.parse(File.binread(expanded, MAX_FILE_BYTES))
      raise "transaction schema is invalid" unless transaction["schema_version"] == TRANSACTION_SCHEMA
      raise "transaction owner is invalid" unless transaction["owner_uid"] == Process.uid
      raise "transaction ID is invalid" unless transaction["transaction_id"].to_s.match?(/\Amaintenance_tx_[a-f0-9]{16}\z/)
      expected_result = File.join(boundary, "#{transaction.fetch('transaction_id')}.result.json")
      raise "transaction result path is invalid" unless transaction["result_path"] == expected_result
      transaction
    rescue JSON::ParserError
      raise "transaction request is invalid JSON"
    end

    def validate_mode!(transaction, requested)
      raise "transaction mode mismatch" unless transaction.fetch("mode") == requested
      raise "transaction mode is invalid" unless %w[rehearsal live live_reboot].include?(requested)
    end

    def print_header(transaction)
      @output.puts("Soul / Guided Maintenance")
      @output.puts("Transaction: #{transaction.fetch('transaction_id')}")
      @output.puts("Mode: #{transaction.fetch('mode')}")
      @output.puts(transaction.fetch("mode") == "live_reboot" ? "A3 may request one reboot only after every reviewed postcondition passes." : "A2 never requests a reboot.")
      @output.flush
    end

    def result_for(transaction, state, commands, password_prompts:, ticket_invalidated: false, reboot_requested: false, reason: "")
      {
        "schema_version" => RESULT_SCHEMA,
        "transaction_id" => transaction.fetch("transaction_id"),
        "lifecycle_state" => state,
        "password_prompts" => password_prompts,
        "commands" => commands,
        "sudo_ticket_invalidated" => ticket_invalidated || transaction.fetch("mode") == "rehearsal",
        "reboot_requested" => reboot_requested == true,
        "reason" => reason
      }
    end

    def failure_result(transaction, state, reason)
      return nil unless transaction
      result_for(transaction, state, [], password_prompts: 0, reason: reason.to_s.byteslice(0, 500))
    end

    def status_for(code) = code.zero? ? "complete" : "failed"
    def passwordless?(transaction) = transaction.fetch("authority_mode", "native_prompt") == "root_owned_passwordless"
    def password_prompts_for(transaction) = passwordless?(transaction) ? 0 : 1

    def display_command(argv)
      argv.map { |value| value.match?(/\A[A-Za-z0-9_.,:\/=+-]+\z/) ? value : "[argument]" }.join(" ")
    end

    def install_signal_handlers
      %w[INT TERM].each do |signal|
        @previous_handlers[signal] = Signal.trap(signal) do
          @canceled = true
          terminate_process(@active_pid)
          raise Interrupt
        end
      end
    end

    def restore_signal_handlers
      @previous_handlers.each { |signal, handler| Signal.trap(signal, handler) }
      @previous_handlers.clear
    rescue ArgumentError
      nil
    end

    def terminate_process(pid)
      return unless pid
      Process.kill("TERM", pid)
      @sleeper.call(1)
      Process.kill("KILL", pid) rescue nil
    rescue Errno::ESRCH
      nil
    end

    def write_result(path, result)
      return unless result
      body = JSON.pretty_generate(result) + "\n"
      raise "maintenance result exceeds size limit" if body.bytesize > MAX_FILE_BYTES
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
  end
end
