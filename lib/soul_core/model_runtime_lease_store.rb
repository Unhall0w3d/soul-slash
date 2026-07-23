# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ModelRuntimeLeaseStore
    DEFAULT_DIRECTORY = File.join("Soul", "runtime", "model_runtime")
    MAX_LEASES = 200
    MAX_LEASE_BYTES = 16 * 1024
    DEFAULT_TTL_SECONDS = 660

    class LockUnavailable < StandardError; end
    class IntegrityError < StandardError; end
    class ResourceBusy < StandardError; end

    def initialize(root: Dir.pwd, directory: DEFAULT_DIRECTORY, clock: -> { Time.now })
      @root = File.expand_path(root)
      @directory = File.expand_path(directory, @root)
      @leases_directory = File.join(@directory, "leases")
      @lock_path = File.join(@directory, "control.lock")
      @clock = clock
    end

    def with_lease(provider_id:, model_id:, request_id:, conversation_id: nil, timeout_seconds:)
      record = acquire(
        provider_id: provider_id,
        model_id: model_id,
        request_id: request_id,
        conversation_id: conversation_id,
        ttl_seconds: [Float(timeout_seconds) + 60, DEFAULT_TTL_SECONDS].max
      )
      yield
    ensure
      release(record && record["lease_id"])
    end

    def acquire(provider_id:, model_id:, request_id:, conversation_id: nil, ttl_seconds: DEFAULT_TTL_SECONDS)
      with_control_lock do
        active_leases_unlocked
        write_record(provider_id: provider_id, model_id: model_id, request_id: request_id, conversation_id: conversation_id, ttl_seconds: ttl_seconds)
      end
    end

    def acquire_exclusive(provider_id:, model_id:, request_id:, resource_group:, conversation_id: nil, ttl_seconds: DEFAULT_TTL_SECONDS)
      group = safe_identifier(resource_group)
      raise IntegrityError, "exclusive resource group is required" if group.empty?

      with_control_lock do
        active = active_leases_unlocked
        conflict = active.find { |lease| lease["resource_group"] == group }
        if conflict
          raise ResourceBusy, "#{group} is occupied by #{conflict.fetch('provider_id')} request #{conflict.fetch('request_id')}"
        end
        write_record(
          provider_id: provider_id, model_id: model_id, request_id: request_id,
          conversation_id: conversation_id, ttl_seconds: ttl_seconds, resource_group: group
        )
      end
    end

    def release(lease_id)
      return unless lease_id.to_s.match?(/\A[0-9a-f]{32}\z/)

      path = lease_path(lease_id)
      stat = File.lstat(path)
      File.unlink(path) if stat.file? && !stat.symlink?
    rescue Errno::ENOENT
      nil
    end

    def active_leases
      with_control_lock { active_leases_unlocked }
    end

    def with_control_lock
      prepare_directories
      File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        raise LockUnavailable, "model runtime control is busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        yield
      ensure
        lock.flock(File::LOCK_UN) rescue nil
      end
    end

    def active_leases_unlocked
      prepare_directories
      entries = Dir.children(@leases_directory).sort
      raise IntegrityError, "model runtime lease limit exceeded" if entries.length > MAX_LEASES

      entries.filter_map do |name|
        raise IntegrityError, "invalid model runtime lease entry" unless name.match?(/\A[0-9a-f]{32}\.json\z/)

        path = File.join(@leases_directory, name)
        stat = File.lstat(path)
        raise IntegrityError, "model runtime lease must be a regular file" unless stat.file? && !stat.symlink?
        raise IntegrityError, "model runtime lease exceeds size limit" if stat.size > MAX_LEASE_BYTES

        record = JSON.parse(File.binread(path, MAX_LEASE_BYTES))
        validate_record!(record, name)
        if stale?(record)
          FileUtils.rm_f(path)
          nil
        else
          record.slice("lease_id", "pid", "provider_id", "model_id", "request_id", "conversation_id", "resource_group", "started_at", "expires_at")
        end
      rescue JSON::ParserError, ArgumentError, Errno::ENOENT => error
        raise IntegrityError, "invalid model runtime lease: #{error.class}"
      end
    end

    private

    def write_record(provider_id:, model_id:, request_id:, conversation_id:, ttl_seconds:, resource_group: nil)
      now = @clock.call
      record = {
        "lease_id" => SecureRandom.hex(16),
        "pid" => Process.pid,
        "process_start" => process_start(Process.pid),
        "provider_id" => safe_identifier(provider_id),
        "model_id" => safe_identifier(model_id),
        "request_id" => safe_identifier(request_id),
        "conversation_id" => safe_identifier(conversation_id),
        "resource_group" => resource_group,
        "started_at" => now.iso8601,
        "expires_at" => (now + Integer(ttl_seconds)).iso8601
      }.compact
      path = lease_path(record.fetch("lease_id"))
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.generate(record) + "\n")
        file.flush
        file.fsync
      end
      record
    end

    def prepare_directories
      FileUtils.mkdir_p(@leases_directory, mode: 0o700)
      File.chmod(0o700, @directory)
      File.chmod(0o700, @leases_directory)
    end

    def validate_record!(record, filename)
      raise IntegrityError, "model runtime lease must be an object" unless record.is_a?(Hash)
      raise IntegrityError, "model runtime lease identity mismatch" unless filename == "#{record['lease_id']}.json"
      raise IntegrityError, "model runtime lease PID is invalid" unless record["pid"].is_a?(Integer) && record["pid"].positive?
      raise IntegrityError, "model runtime lease process identity is missing" if record["process_start"].to_s.empty?
      Time.iso8601(record.fetch("expires_at"))
    end

    def stale?(record)
      return true if Time.iso8601(record.fetch("expires_at")) <= @clock.call

      process_start(record.fetch("pid")) != record.fetch("process_start").to_s
    rescue Errno::ENOENT, Errno::ESRCH, ArgumentError
      true
    end

    def process_start(pid)
      stat = File.read("/proc/#{Integer(pid)}/stat", 4096)
      closing = stat.rindex(")")
      raise Errno::ESRCH unless closing

      fields = stat.byteslice(closing + 2..).to_s.split
      value = fields[19]
      raise Errno::ESRCH if value.to_s.empty?

      value
    end

    def lease_path(lease_id)
      File.join(@leases_directory, "#{lease_id}.json")
    end

    def safe_identifier(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").slice(0, 160)
    end
  end
end
