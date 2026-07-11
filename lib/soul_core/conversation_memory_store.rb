# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ConversationMemoryStore
    DEFAULT_PATH = "Soul/memory/conversation_memory.jsonl"
    LAYERS = %w[project preference episodic semantic].freeze
    STATUSES = %w[candidate approved superseded deleted].freeze
    EVENTS = %w[created approved superseded deleted].freeze

    attr_reader :path

    def initialize(
      root: Dir.pwd,
      path: DEFAULT_PATH,
      clock: -> { Time.now },
      id_generator: -> { SecureRandom.hex(5) }
    )
      @root = File.expand_path(root)
      @path = File.expand_path(path, @root)
      @clock = clock
      @id_generator = id_generator
      FileUtils.mkdir_p(File.dirname(@path))
      FileUtils.touch(@path)
    end

    def propose(layer:, content:, source:, confidence:, chat_id: nil, tags: [], metadata: {})
      normalized_layer = normalize_layer(layer)
      normalized_content = content.to_s.strip
      raise ArgumentError, "Memory content must not be empty" if normalized_content.empty?

      event = {
        "event_id" => event_id,
        "event" => "created",
        "memory_id" => memory_id,
        "occurred_at" => now,
        "status" => "candidate",
        "layer" => normalized_layer,
        "content" => normalized_content,
        "source" => normalize_source(source),
        "confidence" => normalize_confidence(confidence),
        "chat_id" => optional_string(chat_id),
        "tags" => normalize_tags(tags),
        "metadata" => normalize_metadata(metadata),
        "promote_automatically" => false
      }

      append_event(event)
      materialize_event(event)
    end

    def approve(memory_id, note: nil)
      current = fetch!(memory_id)
      raise ArgumentError, "Only candidate memory may be approved" unless current["status"] == "candidate"

      append_transition(
        event: "approved",
        memory_id: current.fetch("id"),
        fields: {
          "status" => "approved",
          "approved_at" => now,
          "approval_note" => optional_string(note)
        }
      )
      fetch!(memory_id)
    end

    def supersede(memory_id, by:, reason: nil)
      current = fetch!(memory_id)
      replacement = fetch!(by)
      raise ArgumentError, "Deleted memory cannot supersede another record" if replacement["status"] == "deleted"
      raise ArgumentError, "A memory record cannot supersede itself" if current["id"] == replacement["id"]

      append_transition(
        event: "superseded",
        memory_id: current.fetch("id"),
        fields: {
          "status" => "superseded",
          "superseded_at" => now,
          "superseded_by" => replacement.fetch("id"),
          "supersession_reason" => optional_string(reason)
        }
      )
      fetch!(memory_id)
    end

    def delete(memory_id, reason: nil)
      current = fetch!(memory_id)
      return current if current["status"] == "deleted"

      append_transition(
        event: "deleted",
        memory_id: current.fetch("id"),
        fields: {
          "status" => "deleted",
          "deleted_at" => now,
          "deletion_reason" => optional_string(reason)
        }
      )
      fetch!(memory_id)
    end

    def find(memory_id)
      materialized.fetch(memory_id.to_s, nil)
    end

    def records(layer: nil, status: nil, include_deleted: false)
      selected = materialized.values
      selected = selected.select { |record| record["layer"] == normalize_layer(layer) } if layer
      selected = selected.select { |record| record["status"] == normalize_status(status) } if status
      selected = selected.reject { |record| record["status"] == "deleted" } unless include_deleted
      selected.sort_by { |record| [record["updated_at"].to_s, record["id"].to_s] }.reverse
    end

    def events(memory_id: nil)
      parsed_events.select do |event|
        memory_id.nil? || event["memory_id"].to_s == memory_id.to_s
      end
    end

    def context_for(query:, chat_id: nil, limit: 8)
      query_tokens = tokens(query)
      selected = records(status: "approved").filter_map do |record|
        score = relevance_score(record, query_tokens, chat_id)
        next unless score.positive?

        [score, record]
      end
      selected.sort_by! { |score, record| [-score, record["id"].to_s] }
      chosen = selected.first(normalize_limit(limit)).map(&:last)

      {
        "records" => chosen,
        "record_ids" => chosen.map { |record| record["id"] },
        "layers" => chosen.map { |record| record["layer"] }.uniq,
        "count" => chosen.length,
        "rendered" => render_context(chosen)
      }
    end

    def render_context(memory_records)
      Array(memory_records).map do |record|
        source = record.fetch("source", {})
        source_label = [source["kind"], source["reference"]].compact.reject(&:empty?).join(":")
        source_label = "unspecified" if source_label.empty?
        confidence = format("%.2f", record.fetch("confidence", 0.0).to_f)
        "- [#{record['layer']}; confidence #{confidence}; source #{source_label}; id #{record['id']}] #{record['content']}"
      end.join("\n")
    end

    private

    def append_transition(event:, memory_id:, fields:)
      append_event(
        {
          "event_id" => event_id,
          "event" => event,
          "memory_id" => memory_id.to_s,
          "occurred_at" => now
        }.merge(fields).reject { |_key, value| value.nil? }
      )
    end

    def append_event(event)
      raise ArgumentError, "Unknown memory event" unless EVENTS.include?(event["event"].to_s)

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
        id = event["memory_id"].to_s
        next if id.empty?

        if event["event"] == "created"
          records[id] = materialize_event(event)
        elsif records[id]
          records[id] = records[id].merge(transition_fields(event))
          records[id]["updated_at"] = event["occurred_at"]
          records[id]["last_event_id"] = event["event_id"]
        end
      end
    end

    def materialize_event(event)
      {
        "id" => event.fetch("memory_id"),
        "status" => event.fetch("status"),
        "layer" => event.fetch("layer"),
        "content" => event.fetch("content"),
        "source" => event.fetch("source"),
        "confidence" => event.fetch("confidence"),
        "chat_id" => event["chat_id"],
        "tags" => Array(event["tags"]),
        "metadata" => event.fetch("metadata", {}),
        "promote_automatically" => false,
        "created_at" => event.fetch("occurred_at"),
        "updated_at" => event.fetch("occurred_at"),
        "last_event_id" => event.fetch("event_id")
      }.reject { |_key, value| value.nil? }
    end

    def transition_fields(event)
      event.reject do |key, _value|
        %w[event_id event memory_id occurred_at].include?(key)
      end
    end

    def fetch!(memory_id)
      record = find(memory_id)
      raise ArgumentError, "Unknown memory id: #{memory_id}" unless record

      record
    end

    def normalize_layer(layer)
      value = layer.to_s
      raise ArgumentError, "Unknown memory layer: #{layer}" unless LAYERS.include?(value)

      value
    end

    def normalize_status(status)
      value = status.to_s
      raise ArgumentError, "Unknown memory status: #{status}" unless STATUSES.include?(value)

      value
    end

    def normalize_confidence(confidence)
      value = Float(confidence)
      raise ArgumentError, "Memory confidence must be between 0.0 and 1.0" unless value.between?(0.0, 1.0)

      value.round(3)
    rescue ArgumentError, TypeError
      raise ArgumentError, "Memory confidence must be between 0.0 and 1.0"
    end

    def normalize_source(source)
      value = case source
              when Hash
                source.transform_keys(&:to_s)
              else
                { "kind" => source.to_s }
              end
      value["kind"] = value["kind"].to_s.strip
      raise ArgumentError, "Memory source kind must not be empty" if value["kind"].empty?

      value.reject { |_key, item| item.nil? || item.to_s.empty? }
    end

    def normalize_tags(tags)
      Array(tags).map { |tag| tag.to_s.downcase.strip }.reject(&:empty?).uniq.first(20)
    end

    def normalize_metadata(metadata)
      value = metadata.is_a?(Hash) ? metadata.transform_keys(&:to_s) : {}
      JSON.parse(JSON.generate(value))
    rescue JSON::GeneratorError
      raise ArgumentError, "Memory metadata must be JSON-compatible"
    end

    def relevance_score(record, query_tokens, chat_id)
      content_tokens = tokens([record["content"], Array(record["tags"]).join(" ")].join(" "))
      overlap = (query_tokens & content_tokens).length
      always_include = record.fetch("metadata", {})["always_include"] == true
      same_chat = !chat_id.to_s.empty? && record["chat_id"].to_s == chat_id.to_s
      return 0 unless overlap.positive? || always_include || same_chat

      layer_weight = {
        "preference" => 4,
        "project" => 3,
        "semantic" => 2,
        "episodic" => 1
      }.fetch(record["layer"], 0)

      (overlap * 10) + layer_weight + (same_chat ? 5 : 0) +
        (always_include ? 3 : 0) + record.fetch("confidence", 0.0).to_f
    end

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).uniq
    end

    def normalize_limit(value)
      limit = value.to_i
      limit = 8 unless limit.positive?
      [limit, 20].min
    end

    def optional_string(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def event_id
      "mev_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}"
    end

    def memory_id
      "mem_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}"
    end

    def now
      @clock.call.iso8601(6)
    end
  end

  class NullConversationMemoryStore
    def context_for(query:, chat_id: nil, limit: 8)
      _unused = [query, chat_id, limit]
      {
        "records" => [],
        "record_ids" => [],
        "layers" => [],
        "count" => 0,
        "rendered" => ""
      }
    end
  end
end
