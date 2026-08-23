# frozen_string_literal: true

require "digest"
require_relative "conversation_memory_store"
require_relative "memory_retrieval_index"
require_relative "memory_retrieval_service"

module SoulCore
  # Read-only projection over the canonical append-only memory ledger and its
  # disposable retrieval index. It deliberately exposes no mutation methods.
  class MemoryObservatoryService
    MAX_RECORDS = 10_000
    MAX_EVENTS = 100
    MAX_RELATIONSHIPS = 100
    MAX_VISUALIZATION_NODES = 240
    MAX_VISUALIZATION_EDGES = 400
    REVIEW_GUIDANCE = [
      "Show pending memory proposals",
      "Show approved memory",
      "Approve memory <memory_id>",
      "Supersede memory <memory_id> with <replacement_id>",
      "Forget memory <memory_id>"
    ].freeze

    def initialize(memory_store:, index_service:, retrieval_service:)
      @memory_store = memory_store
      @index_service = index_service
      @retrieval_service = retrieval_service
    end

    def summary
      records = bounded_records
      events = bounded_events
      duplicates = duplicate_projection(records)
      supersessions = supersession_projection(records)
      complete(
        "counts" => {
          "states" => counts(records, "status"),
          "layers" => counts(records.reject { |record| record["status"] == "deleted" }, "layer"),
          "sources" => source_counts(records.reject { |record| record["status"] == "deleted" })
        },
        "index" => @index_service.availability,
        "lifecycle_events" => lifecycle_projection(events),
        "duplicates" => duplicates,
        "supersessions" => supersessions,
        "visualization" => visualization_projection(records, duplicates, supersessions),
        "review_guidance" => REVIEW_GUIDANCE,
        "authority" => "conversation_memory_ledger",
        "content_trusted" => false,
        "mutation" => "none"
      )
    rescue StandardError => error
      failed("memory observatory summary failed safely: #{error.class}: #{error.message}")
    end

    def query(query:, limit: 8)
      @retrieval_service.query(query: query, limit: limit)
    end

    private

    def bounded_records
      records = Array(@memory_store.records(include_deleted: true))
      raise "ledger inspection exceeds #{MAX_RECORDS} records" if records.length > MAX_RECORDS

      records
    end

    def bounded_events
      events = Array(@memory_store.events)
      raise "ledger inspection exceeds #{MAX_RECORDS} events" if events.length > MAX_RECORDS

      events.last(MAX_EVENTS).reverse
    end

    def counts(records, field)
      records.each_with_object(Hash.new(0)) do |record, result|
        value = record[field].to_s
        result[value.empty? ? "unspecified" : value] += 1
      end.sort.to_h
    end

    def source_counts(records)
      records.each_with_object(Hash.new(0)) do |record, result|
        kind = record.fetch("source", {})["kind"].to_s
        result[kind.empty? ? "unspecified" : kind] += 1
      end.sort.to_h
    end

    def lifecycle_projection(events)
      events.map do |event|
        {
          "event" => event["event"].to_s,
          "memory_id" => event["memory_id"].to_s,
          "state" => event["status"].to_s,
          "at" => event["occurred_at"].to_s,
          "reason" => event["supersession_reason"] || event["deletion_reason"] || event["approval_note"]
        }.compact
      end
    end

    def duplicate_projection(records)
      approved = records.select { |record| record["status"] == "approved" }
      groups = approved.group_by { |record| normalized_content(record["content"]) }
      groups.filter_map do |content, duplicates|
        next unless duplicates.length > 1

        {
          "memory_ids" => duplicates.map { |record| record["id"].to_s }.sort,
          "content_digest" => Digest::SHA256.hexdigest(content),
          "summary" => "#{duplicates.length} approved records have identical normalized content"
        }
      end.first(MAX_RELATIONSHIPS)
    end

    def supersession_projection(records)
      records.filter_map do |record|
        replacement = record["superseded_by"].to_s
        next if replacement.empty?

        {
          "superseded_id" => record["id"].to_s,
          "replacement_id" => replacement,
          "at" => record["superseded_at"].to_s,
          "reason" => record["supersession_reason"]
        }.compact
      end.first(MAX_RELATIONSHIPS)
    end

    def visualization_projection(records, duplicates, supersessions)
      selected = records.last(MAX_VISUALIZATION_NODES)
      selected_ids = selected.map { |record| record["id"].to_s }.to_h { |id| [id, true] }
      nodes = selected.map do |record|
        {
          "id" => record["id"].to_s,
          "state" => record["status"].to_s,
          "layer" => record["layer"].to_s,
          "source_kind" => record.fetch("source", {})["kind"].to_s,
          "created_at" => record["created_at"].to_s
        }
      end
      edges = supersessions.filter_map do |record|
        source = record["superseded_id"].to_s
        target = record["replacement_id"].to_s
        next unless selected_ids[source] && selected_ids[target]

        { "source" => source, "target" => target, "relation" => "supersession" }
      end
      duplicates.each do |record|
        ids = Array(record["memory_ids"]).select { |id| selected_ids[id.to_s] }.map(&:to_s)
        ids.drop(1).each do |target|
          break if edges.length >= MAX_VISUALIZATION_EDGES

          edges << { "source" => ids.first, "target" => target, "relation" => "exact_duplicate" }
        end
      end
      {
        "nodes" => nodes,
        "edges" => edges.first(MAX_VISUALIZATION_EDGES),
        "node_count" => nodes.length,
        "edge_count" => [edges.length, MAX_VISUALIZATION_EDGES].min,
        "truncated" => records.length > MAX_VISUALIZATION_NODES,
        "content_included" => false
      }
    end

    def normalized_content(value)
      value.to_s.downcase.gsub(/\s+/, " ").strip
    end

    def complete(data)
      { "lifecycle_state" => "complete", "data" => data }
    end

    def failed(message)
      { "lifecycle_state" => "failed", "message" => message, "mutation" => "none" }
    end
  end
end
