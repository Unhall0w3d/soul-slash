# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module SoulCore
  class ConversationCreativeFlowStore
    SCHEMA = "soul.conversation.creative_flow.v1"
    FLOW_ID = /\Acreative_[a-f0-9]{16}\z/
    CHAT_ID = /\Achat_[A-Za-z0-9_.-]+\z/
    MAX_BYTES = 256 * 1024
    TERMINAL_STATES = %w[complete failed canceled].freeze

    def initialize(root: Dir.pwd, clock: -> { Time.now.utc })
      @project_root = File.expand_path(root)
      @root = File.join(@project_root, "Soul", "runtime", "creative_flows")
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

    def read(flow_id:, chat_id:)
      record = read_chat(chat_id)
      return nil unless record && record["flow_id"] == flow_id.to_s

      record
    end

    def write(record)
      value = stringify(record)
      validate!(value)
      value["updated_at"] = @clock.call.iso8601
      path = chat_path(value.fetch("chat_id"))
      temporary = "#{path}.#{Process.pid}.tmp"
      encoded = JSON.pretty_generate(value) + "\n"
      raise ArgumentError, "creative workflow record exceeds size limit" if encoded.bytesize > MAX_BYTES
      File.write(temporary, encoded, mode: "w", perm: 0o600)
      File.rename(temporary, path)
      value
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def cancel(chat_id)
      record = active(chat_id)
      return nil unless record

      write(record.merge("lifecycle_state" => "canceled", "stage" => "canceled", "pending_action" => nil))
    end

    def digest(record)
      Digest::SHA256.hexdigest(JSON.generate(record.reject { |key, _| %w[updated_at pending_action].include?(key) }))
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
      raise ArgumentError, "creative workflow record must be an object" unless record.is_a?(Hash)
      raise ArgumentError, "creative workflow schema is invalid" unless record["schema_version"] == SCHEMA
      raise ArgumentError, "creative workflow ID is invalid" unless record["flow_id"].to_s.match?(FLOW_ID)
      validate_chat!(record["chat_id"])
      raise ArgumentError, "creative workflow kind is invalid" unless %w[music visual combined].include?(record["kind"])
      raise ArgumentError, "creative workflow lifecycle is invalid" unless %w[awaiting_input blocked_for_human_review complete failed canceled].include?(record["lifecycle_state"])
      raise ArgumentError, "creative workflow plan must be an object" unless record["plan"].is_a?(Hash)
      true
    end

    def validate_chat!(chat_id)
      raise ArgumentError, "creative workflow chat ID is invalid" unless chat_id.to_s.match?(CHAT_ID)
    end

    def chat_path(chat_id)
      File.join(@root, "#{chat_id}.json")
    end

    def stringify(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
