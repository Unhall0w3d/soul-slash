# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  # Uses disposable remote projections only to rank canonical identifiers and
  # expose explicit relationships. All returned memory content is rejoined from
  # the authoritative local ledger after projection and lifecycle validation.
  class MemoryProjectionQueryService
    SCHEMA = "soul.memory_projection_query.a23.v1"
    MAX_QUERY_CHARACTERS = 200
    MAX_QUERY_INSTRUCTION_CHARACTERS = 500
    MAX_RESULTS = 20
    RELATIONS = %w[SUPERSEDED_BY EXACT_DUPLICATE].freeze

    def initialize(memory_store:, embedding_client:, projection_contract:, selector_store:,
                   qdrant_client:, falkor_client:, local_retrieval:, query_instruction: nil,
                   clock: -> { Time.now.utc })
      @memory_store = memory_store
      @embedding_client = embedding_client
      @projection_contract = projection_contract
      @selector_store = selector_store
      @qdrant_client = qdrant_client
      @falkor_client = falkor_client
      @local_retrieval = local_retrieval
      @query_instruction = query_instruction.to_s.strip
      if @query_instruction.length > MAX_QUERY_INSTRUCTION_CHARACTERS || @query_instruction.match?(/[\r\n]/)
        raise ArgumentError, "query instruction must be one line and at most #{MAX_QUERY_INSTRUCTION_CHARACTERS} characters"
      end
      @clock = clock
    end

    def query(query:, limit: 8)
      text = query.to_s.strip
      return awaiting("memory retrieval query is required") if text.empty?
      return awaiting("memory retrieval query exceeds #{MAX_QUERY_CHARACTERS} characters") if text.length > MAX_QUERY_CHARACTERS
      begin
        wanted = Integer(limit)
      rescue ArgumentError, TypeError
        return awaiting("memory retrieval limit must be 1..#{MAX_RESULTS}")
      end
      return awaiting("memory retrieval limit must be 1..#{MAX_RESULTS}") unless wanted.between?(1, MAX_RESULTS)

      selector = current_selector!
      embedding_input = if @query_instruction.empty?
                          text
                        else
                          "Instruct: #{@query_instruction}\nQuery:#{text}"
                        end
      vectors = @embedding_client.embed([embedding_input])
      vector = Array(vectors).fetch(0)
      points = @qdrant_client.query(name: selector.fetch("qdrant_collection"), vector: vector, limit: wanted)
      records = approved_records
      results = validate_and_join(points, records, selector, wanted)
      relationships = if results.empty?
                        []
                      else
                        @falkor_client.relationships(
                          name: selector.fetch("falkor_graph"),
                          memory_ids: results.map { |result| result.fetch("memory_id") }
                        )
                      end
      validate_relationships!(relationships, records, results.map { |result| result.fetch("memory_id") })
      complete(
        "query" => text,
        "results" => results,
        "count" => results.length,
        "limit" => wanted,
        "abstained" => results.empty?,
        "relationships" => relationships,
        "retrieval_mode" => "remote_projection_local_join",
        "projection_generation" => selector.fetch("generation_id"),
        "projection_available" => true,
        "query_instruction_configured" => !@query_instruction.empty?,
        "authority" => "approved_memory_context",
        "content_source" => "canonical_local_ledger",
        "content_trusted" => false,
        "mutation" => "none",
        "retrieved_at" => @clock.call.utc.iso8601(6)
      )
    rescue StandardError => error
      fallback(query: text, limit: wanted, reason: "projection unavailable: #{error.class}")
    end

    private

    def current_selector!
      selector = @selector_store.active
      raise "active projection selector is unavailable" unless selector.is_a?(Hash)
      built = @projection_contract.build
      raise "current projection contract is unavailable" unless built.is_a?(Hash) && built["lifecycle_state"] == "complete"
      receipt = built.fetch("data").fetch("receipt")
      raise "active projection payload is stale" unless secure_compare(selector.fetch("payload_digest"), receipt.fetch("payload_digest"))
      raise "active projection sources are stale" unless canonical(selector.fetch("source_digests")) == canonical(receipt.fetch("source_digests"))
      suffix = receipt.fetch("payload_digest").to_s[0, 20]
      expected_names = {
        "generation_id" => "generation_#{suffix}",
        "qdrant_collection" => "soul_memory_vectors_#{suffix}",
        "falkor_graph" => "SoulMemory_#{suffix}"
      }
      raise "active projection resources are stale" unless expected_names.all? { |key, value| secure_compare(selector.fetch(key), value) }

      selector
    end

    def approved_records
      records = Array(@memory_store.records(include_deleted: true))
      raise "canonical memory count exceeds bound" if records.length > 10_000

      records.to_h { |record| [record.fetch("id").to_s, record] }
    end

    def validate_and_join(points, records, selector, limit)
      seen = {}
      Array(points).map do |point|
        payload = point.fetch("payload")
        memory_id = payload.fetch("memory_id").to_s
        raise "projection memory identifier is invalid" unless memory_id.match?(/\A[a-zA-Z0-9_-]{1,200}\z/)
        raise "projection query contains duplicate identifiers" if seen[memory_id]
        seen[memory_id] = true
        raise "projection lifecycle state is invalid" unless payload.fetch("state") == "approved"
        raise "projection source digest is stale" unless secure_compare(payload.fetch("canonical_source_digest"), selector.fetch("source_digests").fetch("approved_index"))
        record = records.fetch(memory_id)
        raise "projection references non-approved memory" unless record.fetch("status") == "approved"
        raise "projection content digest mismatched" unless secure_compare(payload.fetch("content_digest"), content_digest(record.fetch("content")))
        raise "projection layer mismatched" unless payload.fetch("layer") == record.fetch("layer")
        source_kind = record.fetch("source", {}).fetch("kind", "unspecified").to_s
        raise "projection source kind mismatched" unless payload.fetch("source_kind") == source_kind
        score = Float(point.fetch("score"))
        raise "projection score is invalid" unless score.finite? && score.between?(-1.0, 1.0)

        {
          "memory_id" => memory_id,
          "layer" => record.fetch("layer"),
          "excerpt" => record.fetch("content").to_s[0, 280],
          "source" => deep_copy(record.fetch("source")),
          "approved_at" => record.fetch("approved_at").to_s,
          "score" => score.round(6),
          "why_recalled" => "qdrant_cosine=#{format('%.3f', score)}; canonical_local_join=verified"
        }
      end.first(limit)
    rescue KeyError, ArgumentError, TypeError
      raise "projection query result is malformed"
    end

    def validate_relationships!(relationships, records, queried_ids)
      raise "projection relationship count exceeds bound" if Array(relationships).length > 40
      scope = queried_ids.to_h { |id| [id.to_s, true] }
      Array(relationships).each do |edge|
        raise "projection relationship is invalid" unless RELATIONS.include?(edge.fetch("relation"))
        source = edge.fetch("source").to_s
        target = edge.fetch("target").to_s
        raise "projection relationship source is unknown" unless records.key?(source)
        raise "projection relationship target is unknown" unless records.key?(target)
        raise "projection relationship is outside query scope" unless scope.key?(source) || scope.key?(target)
      end
    end

    def fallback(query:, limit:, reason:)
      result = @local_retrieval.query(query: query, limit: limit)
      return result unless result.is_a?(Hash) && result["lifecycle_state"] == "complete"

      copied = deep_copy(result)
      copied.fetch("data")["projection_available"] = false
      copied.fetch("data")["projection_reason"] = reason
      copied
    rescue StandardError => error
      failed("memory projection and local fallback failed safely: #{error.class}")
    end

    def content_digest(content)
      Digest::SHA256.hexdigest(content.to_s.downcase.gsub(/\s+/, " ").strip)
    end

    def canonical(value)
      JSON.generate(value.is_a?(Hash) ? value.keys.sort.to_h { |key| [key, value.fetch(key)] } : value)
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && left.bytes.zip(right.bytes).reduce(0) { |sum, pair| sum | (pair[0] ^ pair[1]) }.zero?
    end

    def deep_copy(value) = JSON.parse(JSON.generate(value))
    def complete(data) = {"ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA, "data" => data, "mutation" => "none"}
    def awaiting(message) = {"ok" => false, "lifecycle_state" => "awaiting_input", "schema" => SCHEMA, "message" => message, "mutation" => "none"}
    def failed(message) = {"ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA, "message" => message, "mutation" => "none"}
  end
end
