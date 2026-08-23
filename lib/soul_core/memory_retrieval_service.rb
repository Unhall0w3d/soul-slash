# frozen_string_literal: true

require "json"
require_relative "memory_retrieval_index"

module SoulCore
  # Read-only approved-memory retrieval. A bad derived index never blocks the
  # canonical lexical path and never turns similarity into authority.
  class ApprovedMemoryRetrievalService
    MAX_QUERY_CHARACTERS = 200
    MAX_QUERY_TOKENS = 20
    MAX_RESULTS = 20
    MIN_ADMISSION_SCORE = 0.40
    WEIGHTS = {
      "lexical" => 0.55,
      "semantic" => 0.30,
      "confidence" => 0.10,
      "layer" => 0.05
    }.freeze
    LAYER_WEIGHTS = {
      "preference" => 1.0,
      "project" => 0.75,
      "semantic" => 0.5,
      "episodic" => 0.25
    }.freeze

    def initialize(memory_store:, index_service:, embedding_client: nil, min_admission_score: MIN_ADMISSION_SCORE,
                   clock: -> { Time.now.utc })
      @memory_store = memory_store
      @index_service = index_service
      @embedding_client = embedding_client
      @min_admission_score = Float(min_admission_score)
      raise ArgumentError, "admission threshold must be between 0.0 and 1.0" unless @min_admission_score.between?(0.0, 1.0)
      @clock = clock
    end

    def query(query:, limit: 8)
      text = query.to_s.strip
      return awaiting("memory retrieval query is required") if text.empty?
      return awaiting("memory retrieval query exceeds #{MAX_QUERY_CHARACTERS} characters") if text.length > MAX_QUERY_CHARACTERS

      query_tokens = tokens(text)
      return awaiting("memory retrieval query must contain at least one searchable term") if query_tokens.empty?
      requested_limit = limit.nil? ? 8 : limit.to_i
      wanted = [[requested_limit, 1].max, MAX_RESULTS].min
      envelope, index_reason = @index_service.load_valid_index
      index_available = !envelope.nil?
      semantic_available = index_available && !@embedding_client.nil? && envelope.fetch("dimensions", 0).to_i.positive?
      records = index_available ? envelope.fetch("entries") : lexical_records
      query_vector = semantic_available ? embed_query(text) : nil
      ranked = rank(records, query_tokens, query_vector, wanted)
      selected = ranked.select { |result| result.fetch("score") >= @min_admission_score }.first(wanted)
      abstained = selected.empty?
      complete(
        "query" => text,
        "results" => selected,
        "count" => selected.length,
        "limit" => wanted,
        "abstained" => abstained,
        "retrieval_mode" => if semantic_available
                              "hybrid"
                            elsif index_available
                              "indexed_lexical"
                            else
                              "lexical_fallback"
                            end,
        "index_available" => index_available,
        "index_reason" => index_reason,
        "authority" => "approved_memory_context",
        "content_trusted" => false,
        "mutation" => "none",
        "retrieved_at" => @clock.call.utc.iso8601(6)
      )
    rescue StandardError => error
      # If a local embedding request fails after a valid index was loaded, the
      # lexical result remains usable and is explicitly labeled as fallback.
      begin
        fallback = lexical_query(text, query_tokens, wanted, "embedding unavailable: #{error.class}")
        return fallback if fallback
      rescue StandardError
        nil
      end
      failed("approved-memory retrieval failed safely: #{error.class}: #{error.message}")
    end

    alias search query

    private

    def lexical_query(text, query_tokens, wanted, reason)
      return nil unless text && query_tokens && wanted
      ranked = rank(lexical_records, query_tokens, nil, wanted)
      selected = ranked.select { |result| result.fetch("score") >= @min_admission_score }.first(wanted)
      complete(
        "query" => text,
        "results" => selected,
        "count" => selected.length,
        "limit" => wanted,
        "abstained" => selected.empty?,
        "retrieval_mode" => "lexical_fallback",
        "index_available" => false,
        "index_reason" => reason,
        "authority" => "approved_memory_context",
        "content_trusted" => false,
        "mutation" => "none",
        "retrieved_at" => @clock.call.utc.iso8601(6)
      )
    end

    def lexical_records
      records = Array(@memory_store.records(status: "approved"))
      raise "ledger inspection exceeds #{ApprovedMemoryIndexService::MAX_LEDGER_RECORDS} records" if records.length > ApprovedMemoryIndexService::MAX_LEDGER_RECORDS
      records.select { |record| record["status"] == "approved" }.map do |record|
        {
          "memory_id" => record.fetch("id").to_s,
          "layer" => record.fetch("layer").to_s,
          "content" => record.fetch("content").to_s,
          "source" => deep_copy(record.fetch("source")),
          "confidence" => Float(record.fetch("confidence")),
          "approved_at" => record["approved_at"].to_s,
          "lexical_terms" => tokens([record.fetch("content"), Array(record["tags"]).join(" ")].join(" "))
        }
      end
    end

    def embed_query(text)
      return nil unless @embedding_client

      vectors = @embedding_client.embed([text])
      vector = Array(vectors).fetch(0)
      vector
    end

    def rank(records, query_tokens, query_vector, limit)
      records.filter_map do |record|
        lexical = lexical_component(record.fetch("lexical_terms"), query_tokens)
        semantic = query_vector && record["embedding"] ? semantic_component(query_vector, record.fetch("embedding")) : 0.0
        confidence = [[Float(record.fetch("confidence")), 0.0].max, 1.0].min
        layer = LAYER_WEIGHTS.fetch(record.fetch("layer").to_s, 0.0)
        score = (WEIGHTS["lexical"] * lexical) + (WEIGHTS["semantic"] * semantic) +
          (WEIGHTS["confidence"] * confidence) + (WEIGHTS["layer"] * layer)
        next unless score.positive?

        components = {
          "lexical" => lexical.round(6),
          "semantic" => semantic.round(6),
          "confidence" => confidence.round(6),
          "layer" => layer.round(6),
          "final" => [[score, 0.0].max, 1.0].min.round(6)
        }
        {
          "memory_id" => record.fetch("memory_id"),
          "layer" => record.fetch("layer"),
          "excerpt" => record.fetch("content")[0, 280],
          "source" => deep_copy(record.fetch("source")),
          "approved_at" => record["approved_at"],
          "score" => components.fetch("final"),
          "score_components" => components,
          "why_recalled" => explain(components)
        }
      end.sort_by { |result| [-result.fetch("score"), result.fetch("memory_id")] }.first(limit)
    end

    def lexical_component(record_terms, query_tokens)
      return 0.0 if query_tokens.empty?
      (query_tokens & record_terms).length.to_f / query_tokens.length
    end

    def semantic_component(left, right)
      left = left.map(&:to_f)
      right = right.map(&:to_f)
      return 0.0 unless left.length == right.length
      left_norm = Math.sqrt(left.sum { |value| value * value })
      right_norm = Math.sqrt(right.sum { |value| value * value })
      return 0.0 if left_norm.zero? || right_norm.zero?
      cosine = left.zip(right).sum { |a, b| a * b } / (left_norm * right_norm)
      [[cosine, 0.0].max, 1.0].min
    end

    def explain(components)
      components.select { |name, value| name != "final" && value.to_f.positive? }
        .sort_by { |_name, value| -value.to_f }
        .map { |name, value| "#{name}=#{format('%.3f', value)}" }.join(", ")
    end

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).uniq
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end

    def complete(data)
      { "lifecycle_state" => "complete", "data" => data }
    end

    def awaiting(message)
      { "lifecycle_state" => "awaiting_input", "message" => message, "mutation" => "none" }
    end

    def failed(message)
      { "lifecycle_state" => "failed", "message" => message, "mutation" => "none" }
    end
  end

  MemoryRetrievalService = ApprovedMemoryRetrievalService
  ApprovedMemoryQueryService = ApprovedMemoryRetrievalService
end
