# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "conversation_artifact_contract"

module SoulCore
  class ConversationArtifactStore
    DEFAULT_RELATIVE_PATH = "Soul/artifacts/conversation_artifacts.jsonl"
    MAX_CONTEXT_RECORDS = 5
    EVENT_TYPES = %w[registered attached detached archived].freeze

    attr_reader :root, :path

    def initialize(root:, path: nil, clock: nil)
      @root = File.expand_path(root)
      @path = File.expand_path(path || File.join(@root, DEFAULT_RELATIVE_PATH))
      @clock = clock || -> { Time.now.utc }
    end

    def register(path:, title: nil, kind: nil, privacy: "project", source: {}, chat_id: nil)
      file = ConversationArtifactContract.resolve_project_file(root: root, path: path)
      artifact_id = artifact_id_for
      now = timestamp
      source_data = source.is_a?(Hash) ? source : {}
      normalized_source = ConversationArtifactContract.normalize_source(
        source_data.merge("reference" => file.fetch("relative_path"), "chat_id" => chat_id)
      )

      payload = {
        "artifact_id" => artifact_id,
        "title" => normalized_title(title, file.fetch("relative_path")),
        "kind" => ConversationArtifactContract.normalize_kind(kind, path: file.fetch("relative_path")),
        "privacy" => ConversationArtifactContract.normalize_privacy(privacy),
        "lifecycle" => "active",
        "relative_path" => file.fetch("relative_path"),
        "media_type" => file.fetch("media_type"),
        "size_bytes" => file.fetch("size_bytes"),
        "sha256" => file.fetch("sha256"),
        "source" => normalized_source,
        "attached_chat_ids" => compact_chat_ids(chat_id),
        "created_at" => now,
        "updated_at" => now,
        "content_read" => false,
        "file_mutated" => false
      }

      append_event("registered", artifact_id, payload)
      find(artifact_id)
    end

    def attach(artifact_id, chat_id:)
      record = fetch_active!(artifact_id)
      normalized_chat = require_chat_id(chat_id)
      return record if Array(record["attached_chat_ids"]).include?(normalized_chat)

      append_event("attached", record.fetch("artifact_id"), { "chat_id" => normalized_chat })
      find(record.fetch("artifact_id"))
    end

    def detach(artifact_id, chat_id:)
      record = fetch_record!(artifact_id)
      normalized_chat = require_chat_id(chat_id)
      return record unless Array(record["attached_chat_ids"]).include?(normalized_chat)

      append_event("detached", record.fetch("artifact_id"), { "chat_id" => normalized_chat })
      find(record.fetch("artifact_id"))
    end

    def archive(artifact_id)
      record = fetch_record!(artifact_id)
      return record if record["lifecycle"] == "archived"

      append_event("archived", record.fetch("artifact_id"), {})
      find(record.fetch("artifact_id"))
    end

    def find(artifact_id)
      records.fetch(artifact_id.to_s, nil)
    end

    def list(lifecycle: nil)
      values = records.values
      values = values.select { |record| record["lifecycle"] == lifecycle.to_s } if lifecycle
      values.sort_by { |record| [record["updated_at"].to_s, record["artifact_id"].to_s] }.reverse
    end

    def attached_to_chat(chat_id, limit: MAX_CONTEXT_RECORDS)
      normalized_chat = require_chat_id(chat_id)
      list(lifecycle: "active").select do |record|
        Array(record["attached_chat_ids"]).include?(normalized_chat)
      end.first(normalize_limit(limit))
    end

    def context_for(chat_id:, limit: MAX_CONTEXT_RECORDS, provider_privacy_class: nil)
      selected = attached_to_chat(chat_id, limit: limit)
      blocked = []
      unless provider_privacy_class.to_s.empty?
        selected, blocked = selected.partition do |record|
          ConversationArtifactContract.provider_allowed?(record.fetch("privacy", "project"), provider_privacy_class)
        end
      end
      {
        "records" => selected,
        "artifact_ids" => selected.map { |record| record.fetch("artifact_id") },
        "privacy_blocked_artifact_ids" => blocked.map { |record| record.fetch("artifact_id") },
        "count" => selected.length,
        "metadata_only" => true,
        "content_read" => false,
        "rendered" => render_context(selected)
      }
    end

    def events
      return [] unless File.file?(path)

      File.readlines(path, chomp: true).filter_map do |line|
        next if line.strip.empty?

        event = JSON.parse(line)
        validate_event!(event)
        event
      end
    end

    def records
      events.each_with_object({}) do |event, state|
        artifact_id = event.fetch("artifact_id")
        case event.fetch("event_type")
        when "registered"
          state[artifact_id] = deep_copy(event.fetch("payload"))
        when "attached"
          record = state.fetch(artifact_id) { raise "Attachment references unknown artifact #{artifact_id}" }
          chat_id = event.dig("payload", "chat_id").to_s
          record["attached_chat_ids"] = (Array(record["attached_chat_ids"]) + [chat_id]).reject(&:empty?).uniq
          record["updated_at"] = event.fetch("created_at")
        when "detached"
          record = state.fetch(artifact_id) { raise "Detachment references unknown artifact #{artifact_id}" }
          chat_id = event.dig("payload", "chat_id").to_s
          record["attached_chat_ids"] = Array(record["attached_chat_ids"]).reject { |item| item == chat_id }
          record["updated_at"] = event.fetch("created_at")
        when "archived"
          record = state.fetch(artifact_id) { raise "Archive references unknown artifact #{artifact_id}" }
          record["lifecycle"] = "archived"
          record["attached_chat_ids"] = []
          record["updated_at"] = event.fetch("created_at")
        end
      end
    end

    private

    def append_event(event_type, artifact_id, payload)
      raise ArgumentError, "Unsupported artifact event: #{event_type}" unless EVENT_TYPES.include?(event_type)

      event = {
        "event_id" => "artev_#{timestamp.delete('^0-9')}_#{SecureRandom.hex(4)}",
        "event_type" => event_type,
        "artifact_id" => artifact_id,
        "payload" => payload,
        "created_at" => timestamp
      }

      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        file.write(JSON.generate(event) + "\n")
        file.flush
        file.fsync
      ensure
        file.flock(File::LOCK_UN)
      end
      File.chmod(0o600, path)
      event
    end

    def validate_event!(event)
      raise "Artifact event must be an object" unless event.is_a?(Hash)
      raise "Artifact event type is invalid" unless EVENT_TYPES.include?(event["event_type"])
      raise "Artifact event ID is missing" if event["event_id"].to_s.empty?
      raise "Artifact ID is missing" if event["artifact_id"].to_s.empty?
      raise "Artifact event payload is missing" unless event["payload"].is_a?(Hash)
      raise "Artifact event timestamp is missing" if event["created_at"].to_s.empty?
    end

    def fetch_record!(artifact_id)
      find(artifact_id) || raise(ArgumentError, "Unknown artifact ID: #{artifact_id}")
    end

    def fetch_active!(artifact_id)
      record = fetch_record!(artifact_id)
      raise ArgumentError, "Artifact is archived: #{artifact_id}" unless record["lifecycle"] == "active"

      record
    end

    def require_chat_id(chat_id)
      value = chat_id.to_s.strip
      raise ArgumentError, "A chat ID is required for artifact attachment" if value.empty?

      value
    end

    def compact_chat_ids(chat_id)
      value = chat_id.to_s.strip
      value.empty? ? [] : [value]
    end

    def normalized_title(title, relative_path)
      value = title.to_s.strip
      value = File.basename(relative_path) if value.empty?
      value[0, 160]
    end

    def render_context(records)
      records.map do |record|
        [
          "- #{record['artifact_id']}: #{record['title']}",
          "kind=#{record['kind']}",
          "path=#{record['relative_path']}",
          "privacy=#{record['privacy']}",
          "sha256=#{record['sha256']}"
        ].join("; ")
      end.join("\n")
    end

    def artifact_id_for
      "art_#{timestamp.delete('^0-9')}_#{SecureRandom.hex(4)}"
    end

    def timestamp
      @clock.call.utc.iso8601(6)
    end

    def normalize_limit(value)
      number = value.to_i
      number = MAX_CONTEXT_RECORDS unless number.positive?
      [number, MAX_CONTEXT_RECORDS].min
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end

  class NullConversationArtifactStore
    def context_for(chat_id:, limit: ConversationArtifactStore::MAX_CONTEXT_RECORDS, provider_privacy_class: nil)
      _unused = [chat_id, limit, provider_privacy_class]
      {
        "records" => [],
        "artifact_ids" => [],
        "privacy_blocked_artifact_ids" => [],
        "count" => 0,
        "metadata_only" => true,
        "content_read" => false,
        "rendered" => ""
      }
    end
  end
end
