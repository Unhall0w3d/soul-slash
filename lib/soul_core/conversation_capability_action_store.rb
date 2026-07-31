# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module SoulCore
  class ConversationCapabilityActionStore
    SCHEMA = "soul.conversation.capability_action.v1"
    CHAT_ID = /\Achat_[A-Za-z0-9_.-]+\z/
    ACTION_ID = /\Acapability_[a-f0-9]{16}\z/
    MAX_BYTES = 128 * 1024
    TERMINAL_STATES = %w[complete failed canceled].freeze

    def initialize(root: Dir.pwd, clock: -> { Time.now.utc })
      @root = File.join(File.expand_path(root), "Soul", "runtime", "capability_actions")
      @clock = clock
      FileUtils.mkdir_p(@root, mode: 0o700)
      File.chmod(0o700, @root)
    end

    def active(chat_id)
      record = read_chat(chat_id)
      return nil unless record
      return nil if TERMINAL_STATES.include?(record["lifecycle_state"])

      record
    end

    def write(record)
      value = stringify(record)
      validate!(value)
      value["updated_at"] = @clock.call.iso8601
      encoded = JSON.pretty_generate(value) + "\n"
      raise ArgumentError, "capability action exceeds size limit" if encoded.bytesize > MAX_BYTES

      path = chat_path(value.fetch("chat_id"))
      temporary = "#{path}.#{Process.pid}.tmp"
      File.write(temporary, encoded, mode: "w", perm: 0o600)
      File.rename(temporary, path)
      value
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def cancel(chat_id)
      record = active(chat_id)
      return nil unless record

      write(record.merge("lifecycle_state" => "canceled", "stage" => "canceled"))
    end

    private

    def read_chat(chat_id)
      validate_chat!(chat_id)
      path = chat_path(chat_id)
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_BYTES

      record = JSON.parse(File.binread(path, MAX_BYTES))
      validate!(record)
      record
    rescue JSON::ParserError, Errno::ENOENT, ArgumentError
      nil
    end

    def validate!(record)
      raise ArgumentError, "capability action must be an object" unless record.is_a?(Hash)
      raise ArgumentError, "capability action schema is invalid" unless record["schema_version"] == SCHEMA
      raise ArgumentError, "capability action ID is invalid" unless record["action_id"].to_s.match?(ACTION_ID)
      validate_chat!(record["chat_id"])
      raise ArgumentError, "capability ID is invalid" unless record["capability_id"].to_s.match?(/\A[a-z0-9]+(?:[._-][a-z0-9]+)*\z/)
      raise ArgumentError, "capability lifecycle is invalid" unless %w[awaiting_input blocked_for_human_review complete failed canceled].include?(record["lifecycle_state"])
      raise ArgumentError, "capability action stage is invalid" unless record["stage"].to_s.match?(/\A[a-z][a-z0-9_]{0,63}\z/)
      true
    end

    def validate_chat!(chat_id)
      raise ArgumentError, "capability action chat ID is invalid" unless chat_id.to_s.match?(CHAT_ID)
    end

    def chat_path(chat_id)
      File.join(@root, "#{chat_id}.json")
    end

    def stringify(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
