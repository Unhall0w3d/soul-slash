# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "memory_paths"

module SoulCore
  # Owner-private, content-free checkpoint for derived projection repair.
  class MemoryProjectionReconciliationRequestStore
    SCHEMA = "soul.memory_projection_reconciliation_request.a33.v1"
    AUDIT_SCHEMA = "soul.memory_projection_reconciliation_audit.a33.v1"
    MAX_BYTES = 32 * 1024
    MAX_AUDIT_BYTES = 2 * 1024 * 1024
    STATES = %w[pending blocked_for_human_review complete canceled].freeze

    def initialize(root:, path: nil, audit_path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      paths = MemoryPaths.new(root: @root)
      @path = File.expand_path(path || paths.write_path("projection/reconciliation-request.json"), @root)
      @audit_path = File.expand_path(audit_path || paths.write_path("projection/reconciliation-audit.jsonl"), @root)
      @clock = clock
      ensure_safe_paths!
    end

    def current
      ensure_safe_paths!
      return nil unless File.file?(@path)
      raise "projection reconciliation request exceeds byte bound" if File.size(@path) > MAX_BYTES
      validate!(JSON.parse(File.binread(@path)))
    rescue JSON::ParserError
      raise "projection reconciliation request is malformed"
    end

    def pending(source_digest:, canonical_state_digest:, audit_head_sha256:, trigger: nil)
      existing = current
      same = existing && existing["source_digest"] == source_digest && existing["canonical_state_digest"] == canonical_state_digest
      return existing if same && existing["state"] == "pending"
      attempts = same ? Integer(existing["attempts"]) : 0
      write({
        "schema" => SCHEMA,
        "request_id" => "mpr_#{canonical_state_digest[0, 24]}",
        "state" => "pending",
        "source_digest" => digest!(source_digest),
        "canonical_state_digest" => digest!(canonical_state_digest),
        "audit_head_sha256" => digest!(audit_head_sha256),
        "attempts" => attempts,
        "trigger" => bounded_token(trigger || "verified_projection_drift"),
        "updated_at" => @clock.call.utc.iso8601(6),
        "content_included" => false
      })
    end

    def failed(reason)
      request = current or raise "projection reconciliation request is absent"
      attempts = Integer(request.fetch("attempts")) + 1
      state = attempts >= 3 ? "blocked_for_human_review" : "pending"
      write(request.merge("state" => state, "attempts" => attempts,
        "reason" => bounded_reason(reason), "updated_at" => @clock.call.utc.iso8601(6)))
    end

    def complete(generation_id:)
      transition("complete", "generation_id" => bounded_token(generation_id))
    end

    def cancel
      transition("canceled")
    end

    private

    def transition(state, fields = {})
      request = current or raise "projection reconciliation request is absent"
      write(request.merge(fields).merge("state" => state, "reason" => nil,
        "updated_at" => @clock.call.utc.iso8601(6)))
    end

    def write(value)
      ensure_safe_paths!
      validated = validate!(value.compact)
      encoded = JSON.pretty_generate(validated) + "\n"
      raise "projection reconciliation request exceeds byte bound" if encoded.bytesize > MAX_BYTES
      atomic_write(@path, encoded)
      append_audit(validated)
      validated
    end

    def append_audit(value)
      event = {
        "schema" => AUDIT_SCHEMA, "request_id" => value.fetch("request_id"),
        "state" => value.fetch("state"), "source_digest" => value.fetch("source_digest"),
        "canonical_state_digest" => value.fetch("canonical_state_digest"),
        "audit_head_sha256" => value.fetch("audit_head_sha256"),
        "attempts" => value.fetch("attempts"), "generation_id" => value["generation_id"],
        "reason" => value["reason"], "occurred_at" => @clock.call.utc.iso8601(6),
        "content_included" => false
      }.compact
      line = JSON.generate(event) + "\n"
      existing = File.file?(@audit_path) ? File.size(@audit_path) : 0
      raise "projection reconciliation audit exceeds byte bound" if existing + line.bytesize > MAX_AUDIT_BYTES
      FileUtils.mkdir_p(File.dirname(@audit_path), mode: 0o700)
      File.open(@audit_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
        file.write(line)
        file.flush
        file.fsync
      end
      File.chmod(0o600, @audit_path)
    end

    def atomic_write(path, encoded)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(encoded)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def validate!(value)
      raise "projection reconciliation request is invalid" unless value.is_a?(Hash) && value["schema"] == SCHEMA
      raise "projection reconciliation request state is invalid" unless STATES.include?(value["state"])
      digest!(value["source_digest"])
      digest!(value["canonical_state_digest"])
      digest!(value["audit_head_sha256"])
      attempts = Integer(value["attempts"])
      raise "projection reconciliation attempts are invalid" unless attempts.between?(0, 3)
      raise "projection reconciliation request includes content" unless value["content_included"] == false
      value
    rescue ArgumentError, TypeError, KeyError
      raise "projection reconciliation request is invalid"
    end

    def digest!(value)
      text = value.to_s
      raise "projection reconciliation digest is invalid" unless text.match?(/\A[0-9a-f]{64}\z/)
      text
    end

    def bounded_token(value)
      text = value.to_s
      raise "projection reconciliation token is invalid" unless text.match?(/\A[A-Za-z0-9_.:-]{1,160}\z/)
      text
    end

    def bounded_reason(value)
      value.to_s.gsub(@root, "[PROJECT_ROOT]").gsub(%r{/[^ ]+}, "[PATH]")[0, 240]
    end

    def ensure_safe_paths!
      [@path, @audit_path].each do |path|
        prefix = "#{@root}#{File::SEPARATOR}"
        raise "projection reconciliation path escapes project" unless path.start_with?(prefix)
        current = path
        while current.start_with?(prefix)
          raise "projection reconciliation path contains a symlink" if File.symlink?(current)
          current = File.dirname(current)
        end
      end
    end
  end
end
