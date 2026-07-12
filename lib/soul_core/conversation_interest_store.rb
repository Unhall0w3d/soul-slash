# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ConversationInterestStore
    DEFAULT_PATH = "Soul/identity/interests.jsonl"
    STATUSES = %w[candidate approved inactive retired].freeze
    EVENTS = %w[created approved deactivated reactivated retired].freeze
    MAX_CONTEXT_RECORDS = 3

    attr_reader :path

    def initialize(root: Dir.pwd, path: DEFAULT_PATH, clock: -> { Time.now }, id_generator: -> { SecureRandom.hex(5) })
      @root = File.expand_path(root)
      @path = File.expand_path(path, @root)
      @clock = clock
      @id_generator = id_generator
      FileUtils.mkdir_p(File.dirname(@path))
      FileUtils.touch(@path)
    end

    def propose(topic:, description: nil, source:, confidence: 0.75, chat_id: nil, tags: [])
      normalized_topic = topic.to_s.strip
      raise ArgumentError, "Interest topic must not be empty" if normalized_topic.empty?

      event = {
        "event_id" => event_id,
        "event" => "created",
        "interest_id" => interest_id,
        "occurred_at" => now,
        "status" => "candidate",
        "topic" => normalized_topic,
        "description" => optional_string(description),
        "source" => normalize_source(source),
        "confidence" => normalize_confidence(confidence),
        "chat_id" => optional_string(chat_id),
        "tags" => normalize_tags(tags),
        "approve_automatically" => false
      }.reject { |_key, value| value.nil? }

      append_event(event)
      materialize_event(event)
    end

    def approve(id, note: nil)
      current = fetch!(id)
      raise ArgumentError, "Only candidate interests may be approved" unless current["status"] == "candidate"

      transition("approved", current.fetch("id"), "status" => "approved", "approved_at" => now, "approval_note" => optional_string(note))
      fetch!(id)
    end

    def deactivate(id, reason: nil)
      current = fetch!(id)
      raise ArgumentError, "Only approved interests may be deactivated" unless current["status"] == "approved"

      transition("deactivated", current.fetch("id"), "status" => "inactive", "deactivated_at" => now, "deactivation_reason" => optional_string(reason))
      fetch!(id)
    end

    def reactivate(id, note: nil)
      current = fetch!(id)
      raise ArgumentError, "Only inactive interests may be reactivated" unless current["status"] == "inactive"

      transition("reactivated", current.fetch("id"), "status" => "approved", "reactivated_at" => now, "reactivation_note" => optional_string(note))
      fetch!(id)
    end

    def retire(id, reason: nil)
      current = fetch!(id)
      return current if current["status"] == "retired"

      transition("retired", current.fetch("id"), "status" => "retired", "retired_at" => now, "retirement_reason" => optional_string(reason))
      fetch!(id)
    end

    def find(id)
      materialized.fetch(id.to_s, nil)
    end

    def records(status: nil, include_retired: false)
      selected = materialized.values
      selected = selected.select { |record| record["status"] == normalize_status(status) } if status
      selected = selected.reject { |record| record["status"] == "retired" } unless include_retired
      selected.sort_by { |record| [record["updated_at"].to_s, record["id"].to_s] }.reverse
    end

    def events(id: nil)
      parsed_events.select { |event| id.nil? || event["interest_id"].to_s == id.to_s }
    end

    def context_for(query:, limit: MAX_CONTEXT_RECORDS)
      query_tokens = tokens(query)
      chosen = records(status: "approved").filter_map do |record|
        overlap = (query_tokens & tokens([record["topic"], record["description"], Array(record["tags"]).join(" ")].join(" "))).length
        next unless overlap.positive?

        [(overlap * 10) + record.fetch("confidence", 0.0).to_f, record]
      end.sort_by { |score, record| [-score, record["id"].to_s] }
        .first(normalize_limit(limit)).map(&:last)

      {
        "records" => chosen,
        "record_ids" => chosen.map { |record| record["id"] },
        "count" => chosen.length,
        "rendered" => render_context(chosen),
        "reviewed_only" => true,
        "automatic_inference" => false
      }
    end

    def render_context(records)
      Array(records).map do |record|
        source = record.fetch("source", {})
        source_label = [source["kind"], source["reference"]].compact.reject(&:empty?).join(":")
        source_label = "unspecified" if source_label.empty?
        detail = record["description"].to_s.empty? ? record["topic"] : "#{record['topic']} — #{record['description']}"
        "- [reviewed interest; confidence #{format('%.2f', record['confidence'].to_f)}; source #{source_label}; id #{record['id']}] #{detail}"
      end.join("\n")
    end

    private

    def transition(event, id, fields)
      append_event({ "event_id" => event_id, "event" => event, "interest_id" => id.to_s, "occurred_at" => now }.merge(fields).reject { |_key, value| value.nil? })
    end

    def append_event(event)
      raise ArgumentError, "Unknown interest event" unless EVENTS.include?(event["event"].to_s)

      File.open(@path, "a") do |file|
        file.flock(File::LOCK_EX)
        file.puts(JSON.generate(event))
        file.flush
        file.flock(File::LOCK_UN)
      end
      event
    end

    def parsed_events
      return [] unless File.exist?(@path)

      File.readlines(@path, chomp: true).filter_map do |line|
        next if line.strip.empty?
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def materialized
      parsed_events.each_with_object({}) do |event, records|
        id = event["interest_id"].to_s
        next if id.empty?

        if event["event"] == "created"
          records[id] = materialize_event(event)
        elsif records[id]
          records[id] = records[id].merge(event.reject { |key, _value| %w[event_id event interest_id occurred_at].include?(key) })
          records[id]["updated_at"] = event["occurred_at"]
          records[id]["last_event_id"] = event["event_id"]
        end
      end
    end

    def materialize_event(event)
      {
        "id" => event.fetch("interest_id"),
        "status" => event.fetch("status"),
        "topic" => event.fetch("topic"),
        "description" => event["description"],
        "source" => event.fetch("source"),
        "confidence" => event.fetch("confidence"),
        "chat_id" => event["chat_id"],
        "tags" => Array(event["tags"]),
        "approve_automatically" => false,
        "created_at" => event.fetch("occurred_at"),
        "updated_at" => event.fetch("occurred_at"),
        "last_event_id" => event.fetch("event_id")
      }.reject { |_key, value| value.nil? }
    end

    def fetch!(id)
      find(id) || raise(ArgumentError, "Unknown interest id: #{id}")
    end

    def normalize_status(status)
      value = status.to_s
      raise ArgumentError, "Unknown interest status: #{status}" unless STATUSES.include?(value)
      value
    end

    def normalize_confidence(confidence)
      value = Float(confidence)
      raise ArgumentError unless value.between?(0.0, 1.0)
      value.round(3)
    rescue ArgumentError, TypeError
      raise ArgumentError, "Interest confidence must be between 0.0 and 1.0"
    end

    def normalize_source(source)
      value = source.is_a?(Hash) ? source.transform_keys(&:to_s) : { "kind" => source.to_s }
      value["kind"] = value["kind"].to_s.strip
      raise ArgumentError, "Interest source kind must not be empty" if value["kind"].empty?
      value.reject { |_key, item| item.nil? || item.to_s.empty? }
    end

    def normalize_tags(tags)
      Array(tags).map { |tag| tag.to_s.downcase.strip }.reject(&:empty?).uniq.first(20)
    end

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).uniq
    end

    def normalize_limit(value)
      limit = value.to_i
      limit = MAX_CONTEXT_RECORDS unless limit.positive?
      [limit, MAX_CONTEXT_RECORDS].min
    end

    def optional_string(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def event_id
      "iev_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}"
    end

    def interest_id
      "int_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}"
    end

    def now
      @clock.call.iso8601(6)
    end
  end

  class NullConversationInterestStore
    def context_for(query:, limit: ConversationInterestStore::MAX_CONTEXT_RECORDS)
      _unused = [query, limit]
      { "records" => [], "record_ids" => [], "count" => 0, "rendered" => "", "reviewed_only" => true, "automatic_inference" => false }
    end
  end
end
