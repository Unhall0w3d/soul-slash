# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "securerandom"
require "time"

require_relative "backup_administration_service"

module SoulCore
  class NightlyDrsDeployment
    SERVICE = "soul-nightly-drs.service"
    TIMER = "soul-nightly-drs.timer"
    CREDENTIAL_NAME = "soul-backup-repository-password"
    CONFIRM_CREDENTIAL = "ENROLL_SOUL_DRS_CREDENTIAL"
    CONFIRM_TEST = "INSTALL_SOUL_DRS_QUALIFICATION_TIMER"
    CONFIRM_PERMANENT = "ACTIVATE_SOUL_DRS_3AM_TIMER"
    CONFIRM_UNINSTALL = "REMOVE_SOUL_DRS_AUTOMATION"
    CONFIRM_REMOVE_CREDENTIAL = "REMOVE_SOUL_DRS_CREDENTIAL"
    PERMANENT_CALENDAR = "*-*-* 03:00:00"
    OPERATOR_SERVICE = "soul-operator-nightly-drs.service"
    OPERATOR_TIMER = "soul-operator-nightly-drs.timer"
    OPERATOR_CREDENTIAL_NAME = "operator-backup-repository-password"
    OPERATOR_CONFIRM_CREDENTIAL = "ENROLL_OPERATOR_DRS_CREDENTIAL"
    OPERATOR_CONFIRM_TEST = "INSTALL_OPERATOR_DRS_QUALIFICATION_TIMER"
    OPERATOR_CONFIRM_PERMANENT = "ACTIVATE_OPERATOR_DRS_2AM_TIMER"
    OPERATOR_CONFIRM_UNINSTALL = "REMOVE_OPERATOR_DRS_AUTOMATION"
    OPERATOR_CONFIRM_REMOVE_CREDENTIAL = "REMOVE_OPERATOR_DRS_CREDENTIAL"
    OPERATOR_PERMANENT_CALENDAR = "*-*-* 02:00:00"
    PROFILES = {
      "soul" => {
        label: "Soul", service: SERVICE, timer: TIMER,
        credential_name: CREDENTIAL_NAME,
        confirmations: {
          credential: CONFIRM_CREDENTIAL, test: CONFIRM_TEST,
          permanent: CONFIRM_PERMANENT, uninstall: CONFIRM_UNINSTALL,
          remove_credential: CONFIRM_REMOVE_CREDENTIAL
        },
        calendar: PERMANENT_CALENDAR, state_directory: "backup"
      },
      "operator" => {
        label: "Operator", service: OPERATOR_SERVICE, timer: OPERATOR_TIMER,
        credential_name: OPERATOR_CREDENTIAL_NAME,
        confirmations: {
          credential: OPERATOR_CONFIRM_CREDENTIAL, test: OPERATOR_CONFIRM_TEST,
          permanent: OPERATOR_CONFIRM_PERMANENT, uninstall: OPERATOR_CONFIRM_UNINSTALL,
          remove_credential: OPERATOR_CONFIRM_REMOVE_CREDENTIAL
        },
        calendar: OPERATOR_PERMANENT_CALENDAR, state_directory: "operator_backup"
      }
    }.freeze
    MIN_TEST_DELAY = 60
    MAX_TEST_DELAY = 300

    def initialize(
      root: Dir.pwd,
      home: Dir.home,
      process_env: ENV,
      clock: -> { Time.now },
      ruby_path: RbConfig.ruby,
      systemctl_path: "/usr/bin/systemctl",
      systemd_creds_path: "/usr/bin/systemd-creds",
      backup_service: nil,
      runner: nil,
      profile_id: "soul"
    )
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @env = process_env.to_h
      @clock = clock
      @ruby_path = File.expand_path(ruby_path)
      @systemctl_path = File.expand_path(systemctl_path)
      @systemd_creds_path = File.expand_path(systemd_creds_path)
      @runner = runner || method(:capture)
      @profile_id = profile_id.to_s
      profile = PROFILES[@profile_id]
      raise ArgumentError, "DRS profile must be soul or operator" unless profile
      @profile_label = profile.fetch(:label)
      @service_name = profile.fetch(:service)
      @timer_name = profile.fetch(:timer)
      @credential_name = profile.fetch(:credential_name)
      @confirmations = profile.fetch(:confirmations)
      @permanent_calendar = profile.fetch(:calendar)
      @backup_service = backup_service || BackupAdministrationService.new(
        root: @root, home: @home, process_env: @env, clock: @clock,
        profile_id: @profile_id
      )
      @unit_root = File.join(@home, ".config", "systemd", "user")
      @credential_root = File.join(@home, ".config", "credstore.encrypted")
      @credential_path = File.join(@credential_root, "#{@credential_name}.cred")
      state_root = File.join(@root, "Soul", "private", profile.fetch(:state_directory))
      @state_path = File.join(state_root, "nightly-drs-state.json")
      @receipt_root = File.join(state_root, "receipts")
      mount_key = @profile_id == "operator" ? "OPERATOR_BACKUP_MOUNT" : "SOUL_BACKUP_MOUNT"
      @backup_mount = File.expand_path(@env.fetch(mount_key, @env.fetch("SOUL_BACKUP_MOUNT", "/mnt/soul-backup")))
    end

    def credential_plan
      errors = prerequisites(include_credential_tool: true)
      return result(false, "failed", errors.first, {"errors" => errors}) unless errors.empty?

      result(true, "blocked_for_human_review", "Review host-bound encrypted DRS credential enrollment.", {
        "profile_id" => @profile_id,
        "credential_name" => @credential_name,
        "encryption_scope" => "current user and this host installation",
        "plaintext_file_created" => false,
        "confirmation_phrase" => @confirmations.fetch(:credential)
      })
    end

    def enroll_credential(password:, confirmation:)
      planned = credential_plan
      return planned unless planned["ok"]
      return result(false, "awaiting_input", "Exact #{@profile_label} DRS credential enrollment confirmation is required.", planned["data"]) unless confirmation == @confirmations.fetch(:credential)

      secret = validate_password(password)
      validation = validate_repository_access(secret)
      return validation unless validation["ok"]
      ensure_private_directory(@credential_root)
      temporary = "#{@credential_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      command = [
        @systemd_creds_path, "encrypt", "--user", "--with-key=host", "--newline=no",
        "--name=#{@credential_name}", "-", temporary
      ]
      execution = run(command, stdin_data: secret)
      unless execution["success"] && File.file?(temporary) && !File.symlink?(temporary) && File.size(temporary).between?(1, 128 * 1024)
        return result(false, "failed", "Encrypted DRS credential enrollment failed safely.", {
          "credential_name" => @credential_name,
          "stderr" => bounded(execution["stderr"])
        })
      end
      raise IOError, "refusing symlink credential destination" if File.symlink?(@credential_path)
      File.rename(temporary, @credential_path)
      File.chmod(0o600, @credential_path)
      result(true, "complete", "Host-bound encrypted DRS credential enrolled.", {
        "credential_name" => @credential_name,
        "credential_ready" => credential_ready?,
        "plaintext_file_created" => false
      }, "local_encrypted_credential")
    rescue ArgumentError => error
      result(false, "awaiting_input", error.message, {})
    rescue SystemCallError, IOError => error
      result(false, "failed", "Encrypted DRS credential enrollment failed safely: #{error.class}.", {})
    ensure
      secret&.replace("\0" * secret.bytesize) if defined?(secret) && secret.is_a?(String) && !secret.frozen?
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def test_plan(run_at:)
      instant = validate_test_time(run_at)
      plan_for(mode: "qualification", calendar: calendar_for(instant), confirmation: @confirmations.fetch(:test))
    rescue ArgumentError => error
      result(false, "awaiting_input", error.message, {})
    end

    def install_test(run_at:, confirmation:, expected_digest:)
      planned = test_plan(run_at: run_at)
      return planned unless planned["ok"]
      return result(false, "awaiting_input", "Exact #{@profile_label} DRS qualification timer confirmation is required.", planned["data"]) unless confirmation == @confirmations.fetch(:test)
      return result(false, "blocked_for_human_review", "DRS qualification timer preview digest is stale or invalid.", {}) unless secure_equal?(expected_digest, planned.dig("data", "expected_digest"))
      return result(false, "blocked_for_human_review", "Encrypted DRS credential must be enrolled before timer installation.", {}) unless credential_ready?

      install_units(planned.dig("data", "units"))
      result(true, "complete", "One-time DRS qualification timer installed and armed.", status["data"], "local_timer_configuration")
    end

    def permanent_plan
      return result(false, "blocked_for_human_review", "A complete timed DRS qualification is required before permanent activation.", qualification_evidence) unless qualification_verified?
      plan_for(mode: "permanent", calendar: @permanent_calendar, confirmation: @confirmations.fetch(:permanent))
    end

    def install_permanent(confirmation:, expected_digest:)
      planned = permanent_plan
      return planned unless planned["ok"]
      schedule = @permanent_calendar[/\d{2}:\d{2}/]
      return result(false, "awaiting_input", "Exact permanent #{schedule} #{@profile_label} DRS timer confirmation is required.", planned["data"]) unless confirmation == @confirmations.fetch(:permanent)
      return result(false, "blocked_for_human_review", "Permanent DRS timer preview digest is stale or invalid.", {}) unless secure_equal?(expected_digest, planned.dig("data", "expected_digest"))
      return result(false, "blocked_for_human_review", "Timed DRS qualification evidence is no longer valid.", qualification_evidence) unless qualification_verified?

      install_units(planned.dig("data", "units"))
      result(true, "complete", "Nightly #{schedule} #{@profile_label} DRS timer installed and armed.", status["data"], "local_timer_configuration")
    end

    def status
      unit_mode, unit_calendar = installed_mode_and_calendar
      timer = show_unit(@timer_name, "ActiveState,SubState,UnitFileState,NextElapseUSecRealtime,LastTriggerUSec")
      service = show_unit(@service_name, "ActiveState,SubState,Result,ExecMainStatus")
      run_state = read_run_state
      visible_run_state = public_run_state(run_state)
      receipt = qualification_receipt(visible_run_state["drs_receipt_id"])
      visible_run_state["local_state"] = receipt.dig("local", "state").to_s if visible_run_state["local_state"].to_s.empty?
      visible_run_state["replica_state"] = receipt.dig("replica", "state").to_s if visible_run_state["replica_state"].to_s.empty?
      if visible_run_state["state"] == "running" && service["ActiveState"] != "activating"
        visible_run_state["state"] = "interrupted"
        visible_run_state["reason"] = "the prior run did not record a terminal result"
      end
      exact = if unit_mode == "permanent"
        installed_exact?(rendered(mode: "permanent", calendar: @permanent_calendar))
      elsif unit_mode == "qualification" && unit_calendar
        installed_exact?(rendered(mode: "qualification", calendar: unit_calendar))
      else
        false
      end
      armed = credential_ready? && exact && timer["ActiveState"] == "active" && timer["UnitFileState"] == "enabled"
      ready = armed && unit_mode == "permanent"
      result(true, "complete", "Nightly DRS automation status collected.", {
        "profile_id" => @profile_id,
        "profile_label" => @profile_label,
        "credential_ready" => credential_ready?,
        "units_installed_exact" => exact,
        "mode" => unit_mode || "not_installed",
        "calendar" => unit_calendar,
        "timer_active" => timer["ActiveState"] == "active",
        "timer_enabled" => timer["UnitFileState"] == "enabled",
        "armed" => armed,
        "next_run" => normalized_systemd_time(timer["NextElapseUSecRealtime"]),
        "last_trigger" => normalized_systemd_time(timer["LastTriggerUSec"]),
        "service_state" => service["ActiveState"] || "inactive",
        "service_result" => service["Result"] || "unknown",
        "last_run" => visible_run_state,
        "qualification_verified" => qualification_verified?,
        "ready" => ready,
        "automatic_retry" => false,
        "automatic_retention" => false,
        "remote_deletion" => false
      })
    end

    def uninstall(confirmation:)
      return result(false, "awaiting_input", "Exact #{@profile_label} DRS automation removal confirmation is required.", {"confirmation_phrase" => @confirmations.fetch(:uninstall)}) unless confirmation == @confirmations.fetch(:uninstall)
      run([@systemctl_path, "--user", "disable", "--now", @timer_name])
      unit_paths.each_value { |path| FileUtils.rm_f(path) if safe_file?(path) }
      run([@systemctl_path, "--user", "daemon-reload"])
      result(true, "complete", "Nightly DRS service and timer removed; encrypted credential preserved.", {
        "credential_preserved" => credential_ready?
      }, "local_timer_configuration")
    end

    def remove_credential(confirmation:)
      return result(false, "awaiting_input", "Exact #{@profile_label} DRS credential removal confirmation is required.", {"confirmation_phrase" => @confirmations.fetch(:remove_credential)}) unless confirmation == @confirmations.fetch(:remove_credential)
      return result(false, "blocked_for_human_review", "Remove the DRS timer before removing its credential.", status["data"]) if status.dig("data", "timer_active")
      FileUtils.rm_f(@credential_path) if credential_ready?
      result(true, "complete", "Encrypted DRS credential removed.", {"credential_ready" => credential_ready?}, "local_encrypted_credential")
    end

    def rendered(mode:, calendar:)
      mode = mode.to_s
      raise ArgumentError, "DRS schedule mode is invalid" unless %w[qualification permanent].include?(mode)
      calendar = validate_calendar(calendar, mode: mode)
      {
        @service_name => <<~UNIT,
          [Unit]
          Description=#{@profile_label} bounded encrypted DRS backup
          Wants=network-online.target
          After=network-online.target
          ConditionPathIsMountPoint=#{unit_path(@backup_mount)}

          [Service]
          Type=oneshot
          WorkingDirectory=#{unit_path(@root)}
          LoadCredentialEncrypted=#{@credential_name}:#{unit_path(@credential_path)}
          ExecStart=#{unit_quote(@ruby_path)} #{unit_quote(runner_script)} --root #{unit_quote(@root)}#{runner_profile_argument} --trigger systemd_timer --schedule-mode #{mode}
          TimeoutStartSec=4h
          Restart=no
          UMask=0077
          CacheDirectory=#{cache_directory_name}
          CacheDirectoryMode=0700
          Environment=XDG_CACHE_HOME=%C/#{cache_directory_name}
          Nice=10
          IOSchedulingClass=best-effort
          IOSchedulingPriority=6
          NoNewPrivileges=true
          PrivateTmp=true
          ProtectSystem=strict
          ProtectHome=read-only
          ReadWritePaths=#{writable_paths}
          ProtectControlGroups=true
          ProtectKernelModules=true
          ProtectKernelTunables=true
          RestrictSUIDSGID=true
          LockPersonality=true
          RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
        UNIT
        @timer_name => <<~UNIT
          [Unit]
          Description=Schedule #{@profile_label} encrypted DRS backup (#{mode})

          [Timer]
          OnCalendar=#{calendar}
          AccuracySec=1s
          Persistent=true
          Unit=#{@service_name}

          [Install]
          WantedBy=timers.target
        UNIT
      }
    end

    private

    def plan_for(mode:, calendar:, confirmation:)
      errors = prerequisites
      errors << "encrypted DRS credential is not enrolled" unless credential_ready?
      return result(false, "failed", errors.first, {"errors" => errors}) unless errors.empty?
      units = rendered(mode: mode, calendar: calendar)
      scope = {
        "mode" => mode,
        "calendar" => calendar,
        "persistent" => true,
        "service_type" => "oneshot",
        "timeout" => "4h",
        "automatic_retry" => false,
        "automatic_retention" => false,
        "remote_deletion" => false,
        "profile_id" => @profile_id,
        "credential_name" => @credential_name,
        "units" => units
      }
      result(true, "blocked_for_human_review", "Review the exact #{mode} DRS timer.", scope.merge(
        "expected_digest" => digest(scope),
        "confirmation_phrase" => confirmation
      ))
    end

    def install_units(units)
      ensure_private_directory(@unit_root)
      units.each { |name, content| atomic_write(File.join(@unit_root, name), content, 0o600) }
      [
        [@systemctl_path, "--user", "daemon-reload"],
        [@systemctl_path, "--user", "enable", "--now", @timer_name],
        [@systemctl_path, "--user", "restart", @timer_name]
      ].each do |command|
        execution = run(command)
        raise IOError, "systemd user timer installation failed" unless execution["success"]
      end
    end

    def validate_test_time(value)
      instant = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
      delay = instant - @clock.call
      raise ArgumentError, "qualification run must be scheduled 60 to 300 seconds ahead" unless delay.between?(MIN_TEST_DELAY, MAX_TEST_DELAY)
      instant
    rescue ArgumentError
      raise ArgumentError, "qualification run must be a valid ISO-8601 time 60 to 300 seconds ahead"
    end

    def calendar_for(time)
      time.getlocal.strftime("%Y-%m-%d %H:%M:%S")
    end

    def validate_calendar(value, mode:)
      calendar = value.to_s
      return calendar if mode == "permanent" && calendar == @permanent_calendar
      return calendar if mode == "qualification" && calendar.match?(/\A20\d{2}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)
      raise ArgumentError, "DRS timer calendar is invalid"
    end

    def prerequisites(include_credential_tool: false)
      errors = []
      errors << "Ruby executable is unavailable" unless File.file?(@ruby_path) && File.executable?(@ruby_path)
      errors << "systemctl is unavailable" unless File.file?(@systemctl_path) && File.executable?(@systemctl_path)
      errors << "nightly DRS runner is unavailable" unless File.file?(runner_script)
      if include_credential_tool
        errors << "systemd-creds is unavailable" unless File.file?(@systemd_creds_path) && File.executable?(@systemd_creds_path)
      end
      errors
    end

    def validate_repository_access(password)
      inspected = @backup_service.status(password: password)
      data = inspected["data"] || {}
      replica = data["replica"] || {}
      valid = inspected["ok"] &&
        data["snapshot_access"] == "unlocked" &&
        Array(data["snapshots"]).any? &&
        replica["configured"] == true &&
        replica["state"] == "ready" &&
        replica["target_ready"] == true
      return result(true, "complete", "Repository credential verified against local and Crucible repositories.", {
        "local_snapshot_count" => Array(data["snapshots"]).length,
        "replica_snapshot_count" => replica["snapshot_count"],
        "password_retained" => false
      }) if valid

      reason = inspected["reason"].to_s
      reason = replica["reason"].to_s if reason.empty?
      reason = "repository access could not be verified" if reason.empty?
      result(false, "awaiting_input", "DRS credential verification failed safely: #{bounded(reason)}", {
        "password_retained" => false,
        "credential_replaced" => false
      })
    rescue StandardError => error
      result(false, "failed", "DRS credential verification failed safely: #{error.class}.", {
        "password_retained" => false,
        "credential_replaced" => false
      })
    end

    def qualification_verified?
      state = read_run_state
      return false unless state["state"] == "complete" &&
        state["schedule_mode"] == "qualification" &&
        state["drs_receipt_id"].to_s.match?(/\Adrs_[A-Za-z0-9_.-]+\z/) &&
        !state["last_success_at"].to_s.empty?

      receipt = qualification_receipt(state["drs_receipt_id"])
      snapshot_id = state["snapshot_id"].to_s
      receipt["state"] == "complete" &&
        receipt.dig("local", "state") == "complete" &&
        receipt.dig("local", "verification") == "passed" &&
        receipt.dig("local", "snapshot_id") == snapshot_id &&
        receipt.dig("replica", "state") == "complete" &&
        Array(receipt.dig("replica", "destination_snapshot_lineage_ids")).include?(snapshot_id)
    end

    def qualification_receipt(receipt_id)
      path = File.join(@receipt_root, "#{receipt_id}.json")
      return {} unless safe_file?(path) && File.size(path) <= 128 * 1024
      receipt = JSON.parse(File.read(path))
      return {} unless receipt["schema_version"] == "soul.backup_receipt.v1" &&
        receipt["operation"] == "drs" &&
        receipt["receipt_id"] == receipt_id &&
        receipt.fetch("profile_id", "soul") == @profile_id
      receipt
    rescue JSON::ParserError, SystemCallError
      {}
    end

    def qualification_evidence
      {"qualification_verified" => qualification_verified?, "last_run" => public_run_state(read_run_state)}
    end

    def read_run_state
      return {} unless safe_file?(@state_path) && File.size(@state_path) <= 64 * 1024
      JSON.parse(File.read(@state_path))
    rescue JSON::ParserError, SystemCallError
      {}
    end

    def public_run_state(state)
      %w[run_id state trigger schedule_mode started_at completed_at last_success_at reason mutation snapshot_id drs_receipt_id local_state replica_state].to_h do |key|
        [key, state[key]]
      end.compact
    end

    def installed_mode_and_calendar
      service = unit_paths.fetch(@service_name)
      timer = unit_paths.fetch(@timer_name)
      return [nil, nil] unless safe_file?(service) && safe_file?(timer)
      service_body = File.binread(service, 128 * 1024)
      timer_body = File.binread(timer, 128 * 1024)
      mode = service_body[/--schedule-mode (qualification|permanent)/, 1]
      calendar = timer_body[/^OnCalendar=(.+)$/, 1]
      [mode, calendar]
    rescue SystemCallError
      [nil, nil]
    end

    def installed_exact?(units)
      units.all? do |name, content|
        path = unit_paths.fetch(name)
        safe_file?(path) && File.size(path) <= 128 * 1024 && File.binread(path, 128 * 1024) == content
      end
    end

    def credential_ready?
      safe_file?(@credential_path) && File.size(@credential_path).between?(1, 128 * 1024) && (File.stat(@credential_path).mode & 0o077).zero?
    rescue SystemCallError
      false
    end

    def show_unit(unit, properties)
      execution = run([@systemctl_path, "--user", "show", unit, "--property=#{properties}", "--no-pager"])
      return {} unless execution["success"]
      execution["stdout"].to_s.lines.filter_map do |line|
        key, value = line.strip.split("=", 2)
        [key, value] if key && value
      end.to_h
    end

    def normalized_systemd_time(value)
      text = value.to_s.strip
      return nil if text.empty? || text == "n/a"
      text.byteslice(0, 120).to_s
    end

    def runner_script = File.join(@root, "scripts", "soul-nightly-drs-run")
    def runner_profile_argument = @profile_id == "soul" ? "" : " --profile operator"
    def cache_directory_name = @profile_id == "soul" ? "soul-drs" : "soul-operator-drs"
    def writable_paths
      paths = [File.join(@root, "Soul", "private", "backup")]
      paths.unshift(File.dirname(@state_path)) if @profile_id == "operator"
      (paths + [@backup_mount]).map { |path| unit_path(path) }.join(" ")
    end
    def unit_paths
      {
        @service_name => File.join(@unit_root, @service_name),
        @timer_name => File.join(@unit_root, @timer_name)
      }
    end

    def validate_password(value)
      password = value.to_s.dup
      raise ArgumentError, "repository password is required" if password.empty?
      raise ArgumentError, "repository password exceeds size limit" if password.bytesize > 1024 || password.include?("\0")
      password
    end

    def ensure_private_directory(directory)
      raise IOError, "refusing symlink directory" if File.symlink?(directory)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
    end

    def atomic_write(path, content, mode)
      raise IOError, "refusing symlink destination" if File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def capture(argv, stdin_data: nil)
      stdout, stderr, status = Open3.capture3(*argv, stdin_data: stdin_data.to_s)
      {"success" => status.success?, "stdout" => stdout, "stderr" => stderr}
    end

    def run(argv, stdin_data: nil)
      @runner.call(argv, stdin_data: stdin_data)
    rescue ArgumentError
      @runner.call(argv)
    rescue SystemCallError => error
      {"success" => false, "stdout" => "", "stderr" => error.class.to_s}
    end

    def safe_file?(path)
      File.file?(path) && !File.symlink?(path)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(value))
    end

    def secure_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def bounded(value) = value.to_s.byteslice(0, 4096).to_s
    def unit_quote(value) = %Q{"#{value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')}"}

    def unit_path(value)
      value.to_s.bytes.map do |byte|
        character = byte.chr
        character.match?(/[A-Za-z0-9_.\/-]/) ? character : format("\\x%02x", byte)
      end.join
    end

    def result(ok, lifecycle, reason, data, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => ok ? mutation : "none"}
    end
  end
end
