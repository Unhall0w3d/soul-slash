# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "memory_paths"

module SoulCore
  class MemoryCoreAwareWorker
    SCHEMA = "soul.memory_core_aware_worker.a17.v1"
    ELIGIBLE_CORES = %w[daily amd-free dev].freeze
    SKIPPED_CORES = %w[free music].freeze
    MAX_STATUS_BYTES = 16 * 1024

    def initialize(root:, lifecycle_service:, core_status:, status_path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @lifecycle = lifecycle_service
      @core_status = core_status
      @status_path = File.expand_path(status_path || MemoryPaths.new(root: @root).write_path("memory_lifecycle_worker_status.json"), @root)
      @clock = clock
      ensure_safe_path!
    end

    def run
      core = read_core
      return record(complete("skipped_core", core, "none")) if SKIPPED_CORES.include?(core)
      return record(failed("active Core is unavailable or unsupported", core)) unless ELIGIBLE_CORES.include?(core)

      work = @lifecycle.work_status
      return record(failed(work["reason"], core)) unless work["ok"]
      return record(complete("no_work", core, "none", work)) unless work["work_available"]

      request = "a17-cycle-#{work.fetch('work_digest')[0, 32]}"
      cycle = @lifecycle.run(request_id: request)
      return record(failed(cycle["reason"], core, "request_id" => request)) unless cycle["ok"]

      record(complete("cycle_complete", core, "audited_ordinary_memory", {
        "request_id" => request, "cycle_id" => cycle["cycle_id"],
        "cycle_sha256" => cycle["cycle_sha256"], "mode" => cycle["mode"],
        "decision_counts" => cycle["decision_counts"],
        "rollback_references" => cycle["rollback_references"],
        "idempotent" => cycle["idempotent"],
        "projection_reconciliation_required" => cycle["projection_reconciliation_required"]
      }.compact))
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT, IOError => error
      record(failed(error.message, nil))
    end

    def status
      ensure_safe_path!
      return complete("never_run", nil, "none") unless File.file?(@status_path)
      raise ArgumentError, "memory worker status must not be a symlink" if File.symlink?(@status_path)
      raise ArgumentError, "memory worker status exceeds size limit" if File.size(@status_path) > MAX_STATUS_BYTES
      value = JSON.parse(File.binread(@status_path))
      raise ArgumentError, "memory worker status is invalid" unless valid_status?(value)
      value
    rescue JSON::ParserError, ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failed(error.message, nil)
    end

    private

    def read_core
      envelope = @core_status.call
      raise ArgumentError, envelope["reason"].to_s.empty? ? "Core status is unavailable" : envelope["reason"] unless envelope.is_a?(Hash) && envelope["ok"]
      envelope.dig("data", "active_core_id").to_s
    end

    def complete(outcome, core, mutation, details = nil)
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "completed_at" => @clock.call.iso8601(6), "outcome" => outcome,
        "active_core_id" => core, "mutation" => mutation,
        "details" => content_free(details), "content_included" => false }.compact
    end

    def failed(reason, core, details = nil)
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "completed_at" => @clock.call.iso8601(6), "outcome" => "failed",
        "active_core_id" => core, "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 400],
        "details" => content_free(details), "mutation" => "none", "content_included" => false }.compact
    end

    def record(value)
      ensure_safe_path!
      encoded = JSON.pretty_generate(value) + "\n"
      raise ArgumentError, "memory worker status exceeds size limit" if encoded.bytesize > MAX_STATUS_BYTES
      FileUtils.mkdir_p(File.dirname(@status_path), mode: 0o700)
      temporary = "#{@status_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(encoded)
        file.flush
        file.fsync
      end
      File.rename(temporary, @status_path)
      File.chmod(0o600, @status_path)
      value
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def valid_status?(value)
      value.is_a?(Hash) && value["schema"] == SCHEMA &&
        %w[complete failed].include?(value["lifecycle_state"]) &&
        value["content_included"] == false && value["completed_at"].is_a?(String)
    end

    def content_free(value)
      return nil if value.nil?
      copy = JSON.parse(JSON.generate(value))
      redact(copy)
    end

    def redact(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), output|
          next if %w[text content excerpt query messages candidate structured].include?(key.to_s)
          output[key] = redact(child)
        end
      when Array then value.map { |child| redact(child) }
      else value
      end
    end

    def ensure_safe_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory worker status path escapes project" unless @status_path.start_with?(prefix)
      current = @status_path
      while current.start_with?(prefix)
        raise ArgumentError, "memory worker status path component must not be a symlink" if File.symlink?(current)
        current = File.dirname(current)
      end
    end
  end
end
