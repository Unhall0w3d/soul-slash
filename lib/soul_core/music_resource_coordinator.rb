# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"

module SoulCore
  class MusicResourceCoordinator
    LEASE_SCHEMA = "soul.music.resource_lease.v1"
    LEASE_ID = /\Amusic_lease_[a-f0-9]{16}\z/
    CANDIDATE_ID = /\Acandidate_[a-f0-9]{16}\z/
    DEFAULT_DIRECTORY = File.join("Soul", "runtime", "music")
    MAX_LEASE_BYTES = 16 * 1024
    LEASE_TTL_SECONDS = 420
    MIN_FREE_MIB = 6_000

    class Busy < StandardError; end
    class IntegrityError < StandardError; end

    def initialize(root: Dir.pwd, directory: DEFAULT_DIRECTORY, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) }, process_start: nil, signaler: ->(signal, target) { Process.kill(signal, target) }, sleeper: ->(seconds) { sleep(seconds) }, model_lease_store: nil)
      @root = File.expand_path(root)
      @directory = File.expand_path(directory, @root)
      @runner = runner
      @clock = clock
      @id_generator = id_generator
      @process_start = process_start || method(:linux_process_start)
      @signaler = signaler
      @sleeper = sleeper
      @model_lease_store = model_lease_store || ModelRuntimeLeaseStore.new(root: @root, clock: @clock)
      @lock_path = File.join(@directory, "control.lock")
      @lease_path = File.join(@directory, "nvidia-music.json")
      raise IntegrityError, "music runtime directory must remain inside repository root" unless within?(@directory, @root)
    end

    def inventory
      hardware = observe_hardware
      lease = with_inspection_lock { active_lease_unlocked }
      {
        "ok" => true,
        "schema_version" => "soul.music.resource_inventory.v1",
        "lifecycle_state" => "complete",
        "reason" => "music resource inventory inspected",
        "lanes" => {
          "amd-conversation" => { "health" => hardware.fetch("amd_health") },
          "nvidia-fallback" => { "service" => "llama-server.service", "state" => hardware.fetch("fallback_state") },
          "nvidia-music" => {
            "gpu_state" => hardware.fetch("nvidia_state"),
            "free_mib" => hardware["nvidia_free_mib"],
            "compute_process_count" => hardware.fetch("nvidia_compute_processes").length,
            "lease" => public_lease(lease)
          },
          "cpu-audio" => { "state" => "available" }
        },
        "can_acquire_nvidia_music" => blockers(hardware, lease).empty?,
        "blockers" => blockers(hardware, lease),
        "automatic_preemption" => false,
        "automatic_retry" => false,
        "mutation" => "none"
      }
    rescue Busy
      outcome("blocked_for_human_review", false, "music resource control is busy")
    rescue IntegrityError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def active_project?(project_id)
      lease = with_inspection_lock { active_lease_unlocked }
      lease && lease["project_id"] == project_id.to_s
    rescue Busy
      true
    end

    def acquire(project_id:, candidate_id:, input_digest:, ttl_seconds: LEASE_TTL_SECONDS)
      raise IntegrityError, "candidate_id is invalid" unless candidate_id.to_s.match?(CANDIDATE_ID)
      raise IntegrityError, "input_digest is invalid" unless input_digest.to_s.match?(/\A[a-f0-9]{64}\z/)
      cross_lease = @model_lease_store.acquire(provider_id: "nvidia-music", model_id: "ace-step-1.5", request_id: candidate_id, conversation_id: project_id, ttl_seconds: ttl_seconds)
      record = with_lock do
        hardware = observe_hardware
        active = active_lease_unlocked(cleanup_stale: true)
        conflicts = blockers(hardware, active)
        raise Busy, conflicts.join("; ") unless conflicts.empty?
        now = @clock.call
        record = {
          "schema_version" => LEASE_SCHEMA,
          "lease_id" => "music_lease_#{@id_generator.call}",
          "lane" => "nvidia-music",
          "project_id" => project_id.to_s,
          "candidate_id" => candidate_id.to_s,
          "input_digest" => input_digest.to_s,
          "model_runtime_lease_id" => cross_lease.fetch("lease_id"),
          "owner_pid" => Process.pid,
          "owner_process_start" => @process_start.call(Process.pid),
          "child_pid" => nil,
          "child_process_start" => nil,
          "process_group_id" => nil,
          "started_at" => now.iso8601,
          "expires_at" => (now + Integer(ttl_seconds)).iso8601
        }
        raise IntegrityError, "generated lease ID is invalid" unless record.fetch("lease_id").match?(LEASE_ID)
        write_lease(record)
        record
      end
      record
    rescue StandardError
      @model_lease_store.release(cross_lease["lease_id"]) if defined?(cross_lease) && cross_lease
      raise
    end

    def attach_child(lease_id:, child_pid:, process_group_id:)
      with_lock do
        record = active_lease_unlocked
        raise IntegrityError, "active music lease does not match" unless record && record["lease_id"] == lease_id
        pid = Integer(child_pid); pgid = Integer(process_group_id)
        raise IntegrityError, "music child identity is invalid" unless pid.positive? && pgid == pid && pid != Process.pid
        record["child_pid"] = pid
        record["child_process_start"] = @process_start.call(pid)
        record["process_group_id"] = pgid
        write_lease(record)
        record
      end
    end

    def release(lease_id)
      cross_lease_id = with_lock do
        record = read_lease
        return false unless record && record["lease_id"] == lease_id
        safe_unlink(@lease_path)
        record["model_runtime_lease_id"]
      end
      @model_lease_store.release(cross_lease_id)
      true
    rescue Busy
      false
    end

    def cancel_preview(candidate_id:)
      record = with_inspection_lock { active_lease_unlocked }
      return outcome("awaiting_input", false, "no active music generation matches candidate_id") unless record && record["candidate_id"] == candidate_id.to_s
      return outcome("blocked_for_human_review", false, "music child process is not yet attached", data: public_lease(record)) unless child_attached?(record)
      scope = cancel_scope(record)
      outcome("blocked_for_human_review", true, "exact cancellation confirmation required", data: public_lease(record).merge(
        "confirmation_phrase" => "CANCEL_MUSIC_GENERATION",
        "expected_digest" => Digest::SHA256.hexdigest(JSON.generate(scope)),
        "preview_scope" => scope
      ))
    rescue Busy
      outcome("blocked_for_human_review", false, "music resource control is busy")
    rescue IntegrityError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def cancel_execute(candidate_id:, confirmation:, expected_digest:)
      return outcome("awaiting_input", false, "confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      record = with_lock { active_lease_unlocked }
      return outcome("awaiting_input", false, "no active music generation matches candidate_id") unless record && record["candidate_id"] == candidate_id.to_s
      return outcome("blocked_for_human_review", false, "music child process is not attached") unless child_attached?(record)
      scope = cancel_scope(record)
      digest = Digest::SHA256.hexdigest(JSON.generate(scope))
      return outcome("blocked_for_human_review", false, "exact cancellation confirmation did not match") unless confirmation == "CANCEL_MUSIC_GENERATION"
      return outcome("blocked_for_human_review", false, "music cancellation state changed; preview again") unless secure_compare(expected_digest, digest)
      return outcome("blocked_for_human_review", false, "music child process identity changed") unless @process_start.call(record.fetch("child_pid")) == record.fetch("child_process_start")

      mark_cancel_requested(record.fetch("lease_id"))
      terminate_group(record.fetch("process_group_id"), record.fetch("child_pid"))
      outcome("canceled", true, "music generation cancellation signal completed", data: public_lease(record), mutation: "music_process_group_canceled")
    rescue Errno::ESRCH
      outcome("canceled", true, "music generation had already exited", data: public_lease(record || {}), mutation: "none")
    rescue Busy
      outcome("blocked_for_human_review", false, "music resource control is busy")
    rescue IntegrityError, KeyError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def cancellation_requested?(lease_id)
      with_lock do
        record = read_lease
        record && record["lease_id"] == lease_id && !record["cancel_requested_at"].to_s.empty?
      end
    rescue Busy, IntegrityError
      false
    end

    private

    def observe_hardware
      fallback = @runner.run("systemctl", "--user", "is-active", "llama-server.service", timeout_seconds: 5, max_output_bytes: 1024)
      fallback_state = fallback.stdout.to_s.strip
      fallback_state = "unknown" unless %w[active inactive failed activating deactivating].include?(fallback_state)
      memory = @runner.run("nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits", timeout_seconds: 5, max_output_bytes: 1024)
      processes = @runner.run("nvidia-smi", "--query-compute-apps=pid,process_name", "--format=csv,noheader", timeout_seconds: 5, max_output_bytes: 8 * 1024)
      nvidia_ready = memory.success? && memory.stdout.to_s.strip.match?(/\A\d+\z/) && processes.success?
      health = @runner.run("curl", "--fail", "--silent", "--show-error", "--max-time", "3", "http://127.0.0.1:8082/health", timeout_seconds: 5, max_output_bytes: 4 * 1024)
      {
        "fallback_state" => fallback_state,
        "nvidia_state" => nvidia_ready ? "available" : "unavailable",
        "nvidia_free_mib" => nvidia_ready ? Integer(memory.stdout.strip) : nil,
        "nvidia_compute_processes" => processes.success? ? processes.stdout.lines.map(&:strip).reject(&:empty?).first(32) : [],
        "amd_health" => health.success? && health.stdout.include?("ok") ? "ok" : "unavailable"
      }
    end

    def blockers(hardware, lease)
      items = []
      items << "NVIDIA fallback service is active" if hardware["fallback_state"] == "active"
      items << "NVIDIA fallback service state is uncertain" unless %w[inactive failed].include?(hardware["fallback_state"])
      items << "AMD conversation health is unavailable" unless hardware["amd_health"] == "ok"
      items << "NVIDIA state is unavailable" unless hardware["nvidia_state"] == "available"
      items << "NVIDIA free memory is below #{MIN_FREE_MIB} MiB" if hardware["nvidia_free_mib"] && hardware["nvidia_free_mib"] < MIN_FREE_MIB
      items << "NVIDIA has active compute processes" unless hardware["nvidia_compute_processes"].empty?
      items << "nvidia-music lease is active" if lease
      items
    end

    def active_lease_unlocked(cleanup_stale: false)
      record = read_lease
      return nil unless record
      if stale?(record)
        return record unless cleanup_stale
        @model_lease_store.release(record["model_runtime_lease_id"])
        safe_unlink(@lease_path)
        nil
      else
        record
      end
    end

    def read_lease
      return nil unless File.exist?(@lease_path) || File.symlink?(@lease_path)
      stat = File.lstat(@lease_path)
      raise IntegrityError, "music lease must be a regular file" unless stat.file? && !stat.symlink?
      raise IntegrityError, "music lease exceeds size limit" if stat.size > MAX_LEASE_BYTES
      record = JSON.parse(File.binread(@lease_path, MAX_LEASE_BYTES))
      validate_lease!(record)
      record
    rescue JSON::ParserError => error
      raise IntegrityError, "invalid music lease: #{error.class}"
    end

    def validate_lease!(record)
      raise IntegrityError, "music lease must be an object" unless record.is_a?(Hash)
      raise IntegrityError, "music lease schema is invalid" unless record["schema_version"] == LEASE_SCHEMA
      raise IntegrityError, "music lease ID is invalid" unless record["lease_id"].to_s.match?(LEASE_ID)
      raise IntegrityError, "music lease lane is invalid" unless record["lane"] == "nvidia-music"
      raise IntegrityError, "music lease candidate is invalid" unless record["candidate_id"].to_s.match?(CANDIDATE_ID)
      raise IntegrityError, "music lease owner is invalid" unless record["owner_pid"].is_a?(Integer) && record["owner_pid"].positive? && !record["owner_process_start"].to_s.empty?
      raise IntegrityError, "music cross-runtime lease is invalid" unless record["model_runtime_lease_id"].to_s.match?(/\A[0-9a-f]{32}\z/)
      Time.iso8601(record.fetch("expires_at"))
      if record["child_pid"]
        raise IntegrityError, "music lease child identity is incomplete" unless child_attached?(record)
      end
    rescue ArgumentError, KeyError
      raise IntegrityError, "music lease timestamps are invalid"
    end

    def stale?(record)
      return true if Time.iso8601(record.fetch("expires_at")) <= @clock.call
      @process_start.call(record.fetch("owner_pid")) != record.fetch("owner_process_start")
    rescue Errno::ENOENT, Errno::ESRCH, ArgumentError
      true
    end

    def write_lease(record)
      prepare_directory
      body = JSON.generate(record) + "\n"
      raise IntegrityError, "music lease exceeds size limit" if body.bytesize > MAX_LEASE_BYTES
      temporary = "#{@lease_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(body); file.flush; file.fsync }
      File.rename(temporary, @lease_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def with_lock
      prepare_directory
      File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        raise Busy, "music resource control is busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      ensure
        lock.flock(File::LOCK_UN) rescue nil
      end
    end

    def with_inspection_lock
      unless File.exist?(@directory) || File.symlink?(@directory)
        return yield
      end
      directory_stat = File.lstat(@directory)
      raise IntegrityError, "music runtime directory must not be a symlink" unless directory_stat.directory? && !directory_stat.symlink?
      unless File.exist?(@lock_path) || File.symlink?(@lock_path)
        raise IntegrityError, "music lease exists without its control lock" if File.exist?(@lease_path) || File.symlink?(@lease_path)
        return yield
      end
      lock_stat = File.lstat(@lock_path)
      raise IntegrityError, "music control lock must be a regular file" unless lock_stat.file? && !lock_stat.symlink?
      File.open(@lock_path, File::RDWR) do |lock|
        raise Busy, "music resource control is busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      ensure
        lock.flock(File::LOCK_UN) rescue nil
      end
    end

    def prepare_directory
      FileUtils.mkdir_p(@directory, mode: 0o700)
      stat = File.lstat(@directory)
      raise IntegrityError, "music runtime directory must not be a symlink" unless stat.directory? && !stat.symlink?
      File.chmod(0o700, @directory)
    end

    def safe_unlink(path)
      stat = File.lstat(path)
      raise IntegrityError, "music lease must be a regular file" unless stat.file? && !stat.symlink?
      File.unlink(path)
    rescue Errno::ENOENT
      nil
    end

    def terminate_group(pgid, child_pid)
      raise IntegrityError, "refusing unsafe music process group" unless pgid.is_a?(Integer) && pgid.positive? && pgid == child_pid
      @signaler.call("TERM", -pgid)
      10.times do
        @sleeper.call(0.1)
        begin
          @process_start.call(child_pid)
        rescue Errno::ENOENT, Errno::ESRCH
          return
        end
      end
      @signaler.call("KILL", -pgid)
    end

    def cancel_scope(record)
      record.slice("lease_id", "lane", "project_id", "candidate_id", "input_digest", "child_pid", "child_process_start", "process_group_id")
    end

    def mark_cancel_requested(lease_id)
      with_lock do
        record = active_lease_unlocked
        raise IntegrityError, "music lease changed during cancellation" unless record && record["lease_id"] == lease_id
        record["cancel_requested_at"] = @clock.call.iso8601
        write_lease(record)
      end
    end

    def child_attached?(record)
      record["child_pid"].is_a?(Integer) && record["child_pid"].positive? && !record["child_process_start"].to_s.empty? && record["process_group_id"] == record["child_pid"]
    end

    def public_lease(record)
      return nil unless record.is_a?(Hash) && record["lease_id"]
      record.slice("lease_id", "lane", "project_id", "candidate_id", "started_at", "expires_at", "child_pid")
    end

    def linux_process_start(pid)
      stat = File.read("/proc/#{Integer(pid)}/stat", 4096)
      closing = stat.rindex(")")
      raise Errno::ESRCH unless closing
      value = stat.byteslice(closing + 2..).to_s.split[19]
      raise Errno::ESRCH if value.to_s.empty?
      value
    end

    def secure_compare(left, right)
      return false unless left.to_s.bytesize == right.to_s.bytesize
      left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def outcome(state, ok, reason, data: {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data || {}, "mutation" => mutation }
    end

    def within?(path, parent)
      expanded = File.expand_path(path); base = File.expand_path(parent)
      expanded == base || expanded.start_with?(base + File::SEPARATOR)
    end
  end
end
