# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ConversationArtifactOperationStore
    DEFAULT_ROOT = "Soul/runtime/artifact_operations"
    TERMINAL_STATES = %w[complete failed canceled blocked_for_human_review].freeze

    def initialize(root:, operation_root: DEFAULT_ROOT, clock: nil)
      @project_root = File.expand_path(root)
      @root = File.expand_path(operation_root, @project_root)
      @clock = clock || -> { Time.now.utc }
    end

    def create(attributes)
      operation_id = "artop_#{timestamp.delete('^0-9')}_#{SecureRandom.hex(4)}"
      record = stringify_keys(attributes).merge(
        "operation_id" => operation_id,
        "lifecycle_state" => "preview_ready",
        "created_at" => timestamp,
        "updated_at" => timestamp
      )
      write(record)
      record
    end

    def find(operation_id)
      path = operation_path(operation_id)
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def transition(operation_id, lifecycle_state:, attributes: {})
      record = find(operation_id)
      raise ArgumentError, "Unknown artifact operation: #{operation_id}" unless record

      state = lifecycle_state.to_s
      allowed = %w[preview_ready awaiting_input executing complete failed canceled blocked_for_human_review]
      raise ArgumentError, "Unsupported artifact operation lifecycle: #{state}" unless allowed.include?(state)

      record.merge!(stringify_keys(attributes))
      record["lifecycle_state"] = state
      record["updated_at"] = timestamp
      record.delete("content") if TERMINAL_STATES.include?(state)
      write(record)
      record
    end

    def with_exclusive_lock(operation_id)
      raise ArgumentError, "Unknown artifact operation: #{operation_id}" unless find(operation_id)

      FileUtils.mkdir_p(@root)
      File.open(lock_path(operation_id), File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      ensure
        file.flock(File::LOCK_UN)
      end
    end

    private

    def write(record)
      FileUtils.mkdir_p(@root)
      path = operation_path(record.fetch("operation_id"))
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.flock(File::LOCK_EX)
        file.write(JSON.pretty_generate(record) + "\n")
        file.flush
        file.fsync
      ensure
        file.flock(File::LOCK_UN)
      end
      File.chmod(0o600, path)
    end

    def operation_path(operation_id)
      safe = operation_id.to_s
      raise ArgumentError, "Invalid artifact operation ID" unless safe.match?(/\Aartop_[a-zA-Z0-9_]+\z/)

      File.join(@root, "#{safe}.json")
    end

    def lock_path(operation_id)
      "#{operation_path(operation_id)}.lock"
    end

    def timestamp
      @clock.call.utc.iso8601(6)
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
    end
  end
end
