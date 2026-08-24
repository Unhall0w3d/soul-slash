# frozen_string_literal: true

require "digest"
require "json"
require "time"

module SoulCore
  # Builds disposable, content-free projections from canonical memory and its
  # reviewed embedding index. The returned bundle is private infrastructure
  # input; its receipt is the only safe public representation.
  class MemoryProjectionContract
    SCHEMA = "soul.memory_projection_contract.a18.v1"
    QDRANT_SCHEMA = "soul.memory_qdrant_projection.a18.v1"
    FALKOR_SCHEMA = "soul.memory_falkor_projection.a18.v1"
    MAX_RECORDS = 5_000
    MAX_CONTENT_CHARACTERS = 8_000
    MAX_DIMENSIONS = 1_024
    LAYERS = %w[project preference episodic semantic].freeze
    STATES = %w[candidate approved superseded deleted].freeze

    def initialize(memory_store:, index_service:)
      @memory_store = memory_store
      @index_service = index_service
    end

    def build
      records = canonical_records
      index = valid_index
      approved_source_digest = index.fetch("source_digest").to_s
      expected_approved_digest = digest(records.select { |record| record["status"] == "approved" })
      raise "approved-memory index source digest drifted" unless approved_source_digest == expected_approved_digest
      canonical_state_digest = digest(records)
      qdrant_points = qdrant_points(index, records, approved_source_digest)
      falkor = falkor_projection(records, canonical_state_digest)
      bundle = {
        "schema" => SCHEMA,
        "authority" => "conversation_memory_ledger",
        "rebuildable" => true,
        "source_digests" => {
          "canonical_state" => canonical_state_digest,
          "approved_index" => approved_source_digest
        },
        "qdrant" => {
          "schema" => QDRANT_SCHEMA,
          "dimensions" => Integer(index.fetch("dimensions")),
          "points" => qdrant_points
        },
        "falkor" => falkor
      }
      payload_digest = digest(bundle)
      {
        "lifecycle_state" => "complete",
        "data" => {
          "bundle" => bundle,
          "receipt" => receipt(bundle, payload_digest)
        },
        "mutation" => "none"
      }
    rescue StandardError => error
      {
        "lifecycle_state" => "failed",
        "message" => "memory projection contract failed safely: #{error.class}: #{error.message}",
        "mutation" => "none"
      }
    end

    private

    def canonical_records
      records = Array(@memory_store.records(include_deleted: true))
      raise "canonical record count exceeds #{MAX_RECORDS}" if records.length > MAX_RECORDS

      records.map do |record|
        raise "canonical record must be an object" unless record.is_a?(Hash)
        id = record.fetch("id").to_s
        raise "canonical memory identifier is invalid" unless id.match?(/\A[a-zA-Z0-9_-]{1,200}\z/)
        state = record.fetch("status").to_s
        layer = record.fetch("layer").to_s
        raise "canonical lifecycle state is invalid" unless STATES.include?(state)
        raise "canonical memory layer is invalid" unless LAYERS.include?(layer)
        content = record.fetch("content").to_s
        raise "canonical memory content is invalid" if content.empty? || content.length > MAX_CONTENT_CHARACTERS
        source_kind = record.fetch("source", {}).fetch("kind", "unspecified").to_s
        raise "canonical source kind is invalid" unless source_kind.match?(/\A[a-zA-Z0-9_.-]{1,64}\z/)
        Time.iso8601(record.fetch("created_at").to_s)
        Time.iso8601(record.fetch("updated_at").to_s)
        Time.iso8601(record.fetch("approved_at").to_s) if state == "approved"

        record
      rescue ArgumentError
        raise "canonical memory timestamp is invalid"
      end.sort_by { |record| record.fetch("id").to_s }
    end

    def valid_index
      envelope, reason = @index_service.load_valid_index
      raise "approved-memory index is unavailable: #{reason}" unless envelope.is_a?(Hash)
      dimensions = Integer(envelope.fetch("dimensions"))
      raise "approved-memory index has no embeddings" unless dimensions.between?(1, MAX_DIMENSIONS)
      entries = Array(envelope.fetch("entries"))
      raise "approved-memory index exceeds #{MAX_RECORDS} entries" if entries.length > MAX_RECORDS

      envelope
    end

    def qdrant_points(index, records, source_digest)
      by_id = records.to_h { |record| [record.fetch("id").to_s, record] }
      dimensions = Integer(index.fetch("dimensions"))
      entries = Array(index.fetch("entries"))
      points = entries.map do |entry|
        memory_id = entry.fetch("memory_id").to_s
        record = by_id.fetch(memory_id) { raise "index references unknown canonical memory" }
        raise "vector projection includes non-approved memory" unless record.fetch("status") == "approved"
        vector = Array(entry.fetch("embedding")).map { |value| Float(value) }
        raise "vector projection dimension mismatch" unless vector.length == dimensions
        raise "vector projection contains non-finite values" unless vector.all?(&:finite?)
        indexed_content = entry.fetch("content").to_s
        raise "approved-memory index content drifted" unless indexed_content == record.fetch("content").to_s

        {
          "id" => deterministic_uuid(memory_id),
          "vector" => vector,
          "payload" => metadata(record, source_digest).merge(
            "memory_id" => memory_id,
            "state" => "approved",
            "approved_at" => record.fetch("approved_at").to_s
          )
        }
      end
      approved_ids = records.select { |record| record["status"] == "approved" }.map { |record| record.fetch("id").to_s }.sort
      raise "approved-memory index membership drifted" unless points.map { |point| point.fetch("payload").fetch("memory_id") }.sort == approved_ids

      points.sort_by { |point| point.fetch("payload").fetch("memory_id") }
    end

    def falkor_projection(records, source_digest)
      nodes = records.map do |record|
        {
          "id" => record.fetch("id").to_s,
          "labels" => ["Memory", record.fetch("layer").to_s.capitalize],
          "properties" => metadata(record, source_digest).merge(
            "state" => record.fetch("status").to_s,
            "created_at" => record.fetch("created_at").to_s,
            "updated_at" => record.fetch("updated_at").to_s
          )
        }
      end
      by_id = nodes.to_h { |node| [node.fetch("id"), true] }
      edges = records.filter_map do |record|
        target = record["superseded_by"].to_s
        next if target.empty?
        raise "supersession target is absent" unless by_id[target]

        { "source" => record.fetch("id").to_s, "target" => target, "relation" => "SUPERSEDED_BY" }
      end
      records.group_by { |record| content_digest(record.fetch("content")) }.each_value do |group|
        ids = group.map { |record| record.fetch("id").to_s }.sort
        ids.drop(1).each do |target|
          edges << { "source" => ids.first, "target" => target, "relation" => "EXACT_DUPLICATE" }
        end
      end
      {
        "schema" => FALKOR_SCHEMA,
        "nodes" => nodes,
        "edges" => edges.sort_by { |edge| [edge.fetch("relation"), edge.fetch("source"), edge.fetch("target")] }
      }
    end

    def metadata(record, source_digest)
      {
        "layer" => record.fetch("layer").to_s,
        "source_kind" => record.fetch("source", {}).fetch("kind", "unspecified").to_s,
        "content_digest" => content_digest(record.fetch("content")),
        "canonical_source_digest" => source_digest
      }
    end

    def receipt(bundle, payload_digest)
      {
        "schema" => SCHEMA,
        "authority" => bundle.fetch("authority"),
        "rebuildable" => true,
        "source_digests" => bundle.fetch("source_digests"),
        "payload_digest" => payload_digest,
        "qdrant" => {
          "schema" => QDRANT_SCHEMA,
          "point_count" => bundle.fetch("qdrant").fetch("points").length,
          "dimensions" => bundle.fetch("qdrant").fetch("dimensions")
        },
        "falkor" => {
          "schema" => FALKOR_SCHEMA,
          "node_count" => bundle.fetch("falkor").fetch("nodes").length,
          "edge_count" => bundle.fetch("falkor").fetch("edges").length
        },
        "fallback" => "local_authoritative_retrieval",
        "content_included" => false,
        "mutation" => "none"
      }
    end

    def content_digest(content)
      Digest::SHA256.hexdigest(content.to_s.downcase.gsub(/\s+/, " ").strip)
    end

    def deterministic_uuid(memory_id)
      hex = Digest::SHA256.hexdigest("soul-memory-projection\0#{memory_id}")[0, 32]
      "#{hex[0, 8]}-#{hex[8, 4]}-5#{hex[13, 3]}-a#{hex[17, 3]}-#{hex[20, 12]}"
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end
  end
end
