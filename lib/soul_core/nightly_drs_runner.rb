# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

require_relative "backup_administration_service"

module SoulCore
  class NightlyDrsRunner
    CREDENTIAL_NAME = "soul-backup-repository-password"
    OPERATOR_CREDENTIAL_NAME = "operator-backup-repository-password"
    PROFILES = {
      "soul" => {credential_name: CREDENTIAL_NAME, state_directory: "backup"},
      "operator" => {credential_name: OPERATOR_CREDENTIAL_NAME, state_directory: "operator_backup"}
    }.freeze
    MAX_CREDENTIAL_BYTES = BackupAdministrationService::MAX_PASSWORD_BYTES

    def initialize(
      root: Dir.pwd,
      home: Dir.home,
      process_env: ENV,
      clock: -> { Time.now.utc },
      id_generator: -> { SecureRandom.hex(8) },
      backup_service: nil,
      profile_id: "soul"
    )
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @env = process_env.to_h
      @clock = clock
      @id_generator = id_generator
      @profile_id = profile_id.to_s
      profile = PROFILES[@profile_id]
      raise ArgumentError, "DRS profile must be soul or operator" unless profile
      @credential_name = profile.fetch(:credential_name)
      @state_root = File.join(@root, "Soul", "private", profile.fetch(:state_directory))
      @state_path = File.join(@state_root, "nightly-drs-state.json")
      @lock_path = File.join(@state_root, "nightly-drs-run.lock")
      @backup_service = backup_service || BackupAdministrationService.new(
        root: @root, home: @home, process_env: @env, clock: @clock,
        profile_id: @profile_id
      )
      validate_state_root!
    end

    def run(trigger: "systemd_timer", schedule_mode: "installed")
      lock = acquire_lock
      return terminal(false, "blocked_for_human_review", "another nightly DRS runner is active", {}) unless lock

      started_at = @clock.call.utc
      run_id = "drs_run_#{started_at.strftime('%Y%m%dT%H%M%SZ')}_#{@id_generator.call}"
      previous = read_state
      running = {
        "schema_version" => "soul.nightly_drs_state.v1",
        "profile_id" => @profile_id,
        "run_id" => run_id,
        "state" => "running",
        "trigger" => bounded(trigger),
        "schedule_mode" => bounded(schedule_mode),
        "started_at" => started_at.iso8601,
        "completed_at" => nil,
        "last_success_at" => previous["last_success_at"],
        "password_retained" => false,
        "automatic_retry" => false,
        "automatic_retention" => false,
        "remote_deletion" => false
      }
      write_state(running)

      password = read_credential
      preview = @backup_service.drs_preview(password: password)
      result = if preview["ok"]
        @backup_service.drs_execute(
          password: password,
          confirmation: preview.dig("data", "confirmation_phrase"),
          expected_digest: preview.dig("data", "expected_digest")
        )
      else
        preview
      end
      completed_at = @clock.call.utc
      state = result["ok"] ? "complete" : partial?(result) ? "partial" : "failed"
      receipt = result.dig("data", "drs_receipt") || {}
      final = running.merge(
        "state" => state,
        "completed_at" => completed_at.iso8601,
        "last_success_at" => result["ok"] ? completed_at.iso8601 : previous["last_success_at"],
        "reason" => bounded(result["reason"]),
        "mutation" => bounded(result["mutation"]),
        "snapshot_id" => bounded(result.dig("data", "snapshot_id")),
        "drs_receipt_id" => bounded(receipt["receipt_id"]),
        "local_state" => bounded(receipt.dig("local", "state")),
        "replica_state" => bounded(receipt.dig("replica", "state"))
      )
      write_state(final)
      terminal(result["ok"], result["lifecycle_state"], result["reason"], final, result["mutation"])
    rescue StandardError => error
      failed = (defined?(running) && running ? running : {
        "schema_version" => "soul.nightly_drs_state.v1",
        "profile_id" => @profile_id,
        "state" => "failed",
        "started_at" => @clock.call.utc.iso8601,
        "last_success_at" => read_state["last_success_at"]
      }).merge(
        "state" => "failed",
        "completed_at" => @clock.call.utc.iso8601,
        "reason" => "nightly DRS runner failed safely: #{safe_error(error)}",
        "password_retained" => false,
        "automatic_retry" => false,
        "automatic_retention" => false,
        "remote_deletion" => false
      )
      write_state(failed)
      terminal(false, "failed", failed["reason"], failed)
    ensure
      password&.replace("\0" * password.bytesize) if defined?(password) && password.is_a?(String) && !password.frozen?
      release_lock(lock) if defined?(lock)
    end

    private

    def credential_path
      directory = @env.fetch("CREDENTIALS_DIRECTORY", "").to_s
      raise "systemd credential directory is unavailable" if directory.empty?
      expanded = File.expand_path(directory)
      raise "systemd credential directory is invalid" unless File.directory?(expanded) && !File.symlink?(expanded)
      File.join(expanded, @credential_name)
    end

    def read_credential
      path = credential_path
      raise "encrypted backup credential was not delivered" unless File.file?(path) && !File.symlink?(path)
      raise "backup credential exceeds size limit" if File.size(path) > MAX_CREDENTIAL_BYTES
      password = File.binread(path, MAX_CREDENTIAL_BYTES + 1)
      raise "backup credential is empty or invalid" if password.empty? || password.include?("\0")
      password
    end

    def acquire_lock
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      lock = File.open(@lock_path, File::RDWR | File::CREAT, 0o600)
      return lock if lock.flock(File::LOCK_EX | File::LOCK_NB)
      lock.close
      nil
    end

    def release_lock(lock)
      return unless lock
      lock.flock(File::LOCK_UN)
      lock.close
    rescue IOError
      nil
    end

    def read_state
      return {} unless File.file?(@state_path) && !File.symlink?(@state_path) && File.size(@state_path) <= 64 * 1024
      JSON.parse(File.read(@state_path))
    rescue JSON::ParserError, SystemCallError
      {}
    end

    def write_state(value)
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      temporary = "#{@state_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(value) + "\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, @state_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def validate_state_root!
      [File.join(@root, "Soul"), File.join(@root, "Soul", "private"), @state_root].each do |path|
        raise ArgumentError, "nightly DRS state path must not traverse a symlink" if File.symlink?(path)
      end
      return unless File.exist?(@state_root)
      raise ArgumentError, "nightly DRS state root must be owner-only" unless File.directory?(@state_root) && (File.stat(@state_root).mode & 0o077).zero?
    end

    def partial?(result)
      result["mutation"].to_s.include?("replica_incomplete")
    end

    def safe_error(error)
      error.message.to_s.gsub(@root, "[PROJECT_ROOT]").gsub(@home, "~").byteslice(0, 240).to_s
    end

    def bounded(value)
      value.to_s.byteslice(0, 240).to_s
    end

    def terminal(ok, lifecycle, reason, data, mutation = "none")
      {
        "ok" => ok,
        "lifecycle_state" => lifecycle.to_s.empty? ? (ok ? "complete" : "failed") : lifecycle,
        "reason" => bounded(reason),
        "data" => data,
        "mutation" => mutation.to_s.empty? ? "none" : mutation
      }
    end
  end
end
