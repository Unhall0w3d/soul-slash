# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class MemoryFusionRetrievalService
    SCHEMA = "soul.memory_fusion_query.a27.v1"
    PROFILE = "projection_gate_local_order_a29"
    MAX_RESULTS = 20

    def initialize(local_retrieval:, projection_retrieval:, policy_store:, clock: -> { Time.now.utc })
      @local = local_retrieval
      @projection = projection_retrieval
      @policy = policy_store
      @clock = clock
    end

    def query(query:, limit: 8)
      wanted = Integer(limit)
      return @local.query(query: query, limit: limit) unless wanted.between?(1, MAX_RESULTS)
      local = @local.query(query: query, limit: MAX_RESULTS)
      policy = @policy.active
      return local unless policy["profile"] == PROFILE
      local_data = validated_local(local)
      return local unless local_data["retrieval_mode"] == "hybrid"
      projection = @projection.query(query: query, limit: MAX_RESULTS)
      projection_data = validated_projection(projection)
      threshold = policy.fetch("projection_threshold")
      admitted = projection_data.fetch("results").select { |result| Float(result.fetch("score")) >= threshold }
      local_results = local_data.fetch("results")
      local_rank = local_results.each_with_index.to_h { |result, index| [result.fetch("memory_id").to_s, index] }
      local_by_id = local_results.to_h { |result| [result.fetch("memory_id").to_s, result] }
      ordered = admitted.each_with_index.sort_by do |(result, projection_rank)|
        [local_rank.fetch(result.fetch("memory_id").to_s, MAX_RESULTS + projection_rank), projection_rank]
      end.map.with_index do |(projected, _projection_rank), fusion_rank|
        id = projected.fetch("memory_id").to_s
        base = deep_copy(local_by_id.fetch(id, projected))
        base.merge(
          "fusion_rank" => fusion_rank + 1,
          "projection_score" => Float(projected.fetch("score")).round(6),
          "why_recalled" => "projection>=#{format('%.2f', threshold)}; local_order=#{local_rank[id] ? local_rank[id] + 1 : 'unavailable'}; canonical_local_join=verified"
        )
      end.first(wanted)
      complete(
        "query" => query.to_s.strip,
        "results" => ordered,
        "count" => ordered.length,
        "limit" => wanted,
        "abstained" => ordered.empty?,
        "retrieval_mode" => "projection_gate_local_order",
        "ranking_profile" => PROFILE,
        "projection_threshold" => threshold,
        "projection_generation" => projection_data.fetch("projection_generation"),
        "projection_available" => true,
        "index_available" => local_data["index_available"] == true,
        "authority" => "approved_memory_context",
        "content_source" => "canonical_local_ledger",
        "content_trusted" => false,
        "mutation" => "none",
        "retrieved_at" => @clock.call.utc.iso8601(6)
      )
    rescue StandardError
      local || @local.query(query: query, limit: limit)
    end

    alias search query

    private

    def validated_local(envelope)
      raise "local retrieval is invalid" unless envelope.is_a?(Hash) && envelope["lifecycle_state"] == "complete"
      data = envelope.fetch("data")
      raise "local retrieval authority is invalid" unless data["authority"] == "approved_memory_context" && data["mutation"] == "none"
      validate_results(data.fetch("results"))
      data
    end

    def validated_projection(envelope)
      raise "projection retrieval is invalid" unless envelope.is_a?(Hash) && envelope["lifecycle_state"] == "complete" && envelope["schema"] == "soul.memory_projection_query.a23.v1" && envelope["mutation"] == "none"
      data = envelope.fetch("data")
      valid = data["projection_available"] == true && data["retrieval_mode"] == "remote_projection_local_join" &&
        data["authority"] == "approved_memory_context" && data["content_source"] == "canonical_local_ledger" &&
        data["mutation"] == "none" && data["projection_generation"].to_s.match?(/\Ageneration_[0-9a-f]{20}\z/)
      raise "projection retrieval fell back" unless valid
      validate_results(data.fetch("results"))
      data
    end

    def validate_results(results)
      raise "retrieval results are invalid" unless results.is_a?(Array) && results.length <= MAX_RESULTS
      ids = results.map do |result|
        id = result.fetch("memory_id").to_s
        score = Float(result.fetch("score"))
        raise "retrieval result is invalid" unless id.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}\z/) && score.finite? && score.between?(-1.0, 1.0)
        id
      end
      raise "retrieval result identifiers repeat" unless ids.uniq.length == ids.length
    end

    def deep_copy(value) = JSON.parse(JSON.generate(value))
    def complete(data) = {"lifecycle_state" => "complete", "schema" => SCHEMA, "data" => data, "mutation" => "none"}
  end
end
