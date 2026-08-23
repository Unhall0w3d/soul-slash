# frozen_string_literal: true

require "tmpdir"
require "time"
require_relative "memory_retrieval_index"
require_relative "memory_retrieval_service"

module SoulCore
  # Deterministic A0 harness. Its vectors are synthetic acceptance fixtures,
  # not a production model recommendation or an approval decision.
  class MemoryRetrievalEvaluationHarness
    class FixtureStore
      def initialize(records)
        @records = records
      end

      def records(status: nil, **_unused)
        status ? @records.select { |record| record["status"] == status } : @records
      end
    end

    class DeterministicEmbeddingClient
      attr_reader :profile, :dimensions

      GROUPS = {
        "vehicle" => 0,
        "spaceship" => 0,
        "ship" => 0,
        "craft" => 0,
        "spacecraft" => 0,
        "planetary" => 1,
        "terrain" => 1,
        "ground" => 1,
        "surface" => 1,
        "compact" => 2,
        "concise" => 2,
        "brief" => 2,
        "short" => 2,
        "archive" => 3,
        "archived" => 3,
        "history" => 3,
        "previous" => 3,
        "privacy" => 4,
        "private" => 4,
        "owner" => 4
      }.freeze

      def initialize
        @dimensions = 5
        @profile = { "name" => "synthetic-a0-v1", "dimensions" => @dimensions }
      end

      def embed(texts)
        Array(texts).map do |text|
          vector = Array.new(@dimensions, 0.0)
          text.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).each do |token|
            index = GROUPS[token]
            vector[index] += 1.0 if index
          end
          vector
        end
      end
    end

    QUERIES = [
      { "id" => "exact", "query" => "rotating frame conversion", "expected" => ["mem_vehicle"] },
      { "id" => "paraphrase", "query" => "spacecraft flight", "expected" => ["mem_vehicle"] },
      { "id" => "renamed", "query" => "planetary ground surface", "expected" => ["mem_terrain"] },
      { "id" => "temporal", "query" => "previous archived history", "expected" => ["mem_archive"] },
      { "id" => "preference", "query" => "concise technical explanations", "expected" => ["mem_preference"] },
      { "id" => "absent", "query" => "quantum gardening recipes", "expected" => [] },
      { "id" => "conflict", "query" => "preferred display theme", "expected" => ["mem_conflict"] },
      { "id" => "distractor", "query" => "quantum gardening", "expected" => [] }
    ].freeze

    def self.synthetic_records
      [
        record("mem_vehicle", "project", "Project Wraith uses rotating frame conversion for vehicle flight.", ["rotation", "frame", "conversion"], 0.95),
        record("mem_terrain", "project", "Project Wraith reanchors craft against planetary terrain and ground surface.", ["terrain", "reanchor"], 0.92),
        record("mem_archive", "episodic", "The previous archived flight history belongs to the earlier project name.", ["history", "archive"], 0.80),
        record("mem_preference", "preference", "The operator prefers concise technical explanations.", ["concise", "preference"], 0.98),
        record("mem_conflict", "preference", "The operator prefers a light display theme.", ["display", "theme", "light"], 0.75),
        record("mem_distractor", "semantic", "Breakfast planning is outside project operations.", ["breakfast"], 0.70),
        record("mem_candidate", "project", "Candidate memory must never be indexed.", [], 0.99, status: "candidate"),
        record("mem_deleted", "semantic", "Deleted private detail must never be indexed.", [], 0.99, status: "deleted")
      ]
    end

    def initialize(clock: -> { Time.now.utc }, embedding_client: nil)
      @clock = clock
      @embedding_client = embedding_client
    end

    def run
      records = self.class.synthetic_records
      client = @embedding_client || DeterministicEmbeddingClient.new
      lexical = MemoryRetrievalLexicalRanker.new
      Dir.mktmpdir("soul-memory-retrieval-a0") do |directory|
        store = FixtureStore.new(records)
        index = ApprovedMemoryIndexService.new(
          memory_store: store,
          index_path: File.join(directory, "approved-memory-index.json"),
          embedding_client: client,
          clock: @clock,
          max_age_seconds: 86_400
        )
        rebuilt = index.rebuild
        raise "synthetic index rebuild failed" unless rebuilt["lifecycle_state"] == "complete"
        hybrid = ApprovedMemoryRetrievalService.new(memory_store: store, index_service: index, embedding_client: client, clock: @clock)
        query_results = QUERIES.map do |fixture|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          lexical_results = lexical.rank(records.select { |record| record["status"] == "approved" }, fixture.fetch("query"), limit: 5)
          hybrid_output = hybrid.query(query: fixture.fetch("query"), limit: 5)
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round(3)
          hybrid_data = hybrid_output.fetch("data")
          expected = fixture.fetch("expected")
          evidence = score_evidence(expected, hybrid_data.fetch("results"))
          lexical_evidence = score_evidence(expected, lexical_results)
          evidence.merge(
            "id" => fixture.fetch("id"),
            "query" => fixture.fetch("query"),
            "expected_memory_ids" => fixture.fetch("expected"),
            "lexical_memory_ids" => lexical_results.map { |result| result.fetch("memory_id") },
            "hybrid_memory_ids" => hybrid_data.fetch("results").map { |result| result.fetch("memory_id") },
            "lexical_recall" => lexical_evidence.fetch("recall"),
            "lexical_precision" => lexical_evidence.fetch("precision"),
            "lexical_reciprocal_rank" => lexical_evidence.fetch("reciprocal_rank"),
            "abstained" => hybrid_data.fetch("abstained"),
            "latency_ms" => elapsed,
            "score_components" => hybrid_data.fetch("results").map { |result| [result.fetch("memory_id"), result.fetch("score_components")] }.to_h
          )
        end
        summarize(query_results).merge(
          "lifecycle_state" => "complete",
          "corpus" => "synthetic-memory-retrieval-a0-v1",
          "embedding_profile" => client.profile,
          "index" => rebuilt.fetch("data"),
          "queries" => query_results,
          "authority" => "evaluation_only",
          "mutation" => "none"
        )
      end
    end

    alias evaluate run

    private

    def score_evidence(expected, results)
      actual = results.map { |result| result.fetch("memory_id") }
      relevant = actual & expected
      reciprocal_rank = expected.empty? ? 0.0 : begin
        position = actual.index { |id| expected.include?(id) }
        position ? (1.0 / (position + 1)) : 0.0
      end
      {
        "recall" => expected.empty? ? 1.0 : (relevant.length.to_f / expected.length).round(6),
        "precision" => actual.empty? ? (expected.empty? ? 1.0 : 0.0) : (relevant.length.to_f / actual.length).round(6),
        "reciprocal_rank" => reciprocal_rank.round(6),
        "abstention_correct" => expected.empty? ? actual.empty? : !actual.empty?
      }
    end

    def summarize(queries)
      non_absent = queries.reject { |query| query.fetch("expected_memory_ids").empty? }
      {
        "query_count" => queries.length,
        "mean_recall" => mean(queries.map { |query| query.fetch("recall") }),
        "mean_precision" => mean(queries.map { |query| query.fetch("precision") }),
        "mean_reciprocal_rank" => mean(non_absent.map { |query| query.fetch("reciprocal_rank") }),
        "lexical_baseline" => {
          "mean_recall" => mean(queries.map { |query| query.fetch("lexical_recall") }),
          "mean_precision" => mean(queries.map { |query| query.fetch("lexical_precision") }),
          "mean_reciprocal_rank" => mean(non_absent.map { |query| query.fetch("lexical_reciprocal_rank") })
        },
        "hybrid_gain" => {
          "recall" => (mean(queries.map { |query| query.fetch("recall") }) - mean(queries.map { |query| query.fetch("lexical_recall") })).round(6),
          "precision" => (mean(queries.map { |query| query.fetch("precision") }) - mean(queries.map { |query| query.fetch("lexical_precision") })).round(6)
        },
        "correct_abstentions" => queries.count { |query| query.fetch("abstention_correct") && query.fetch("expected_memory_ids").empty? },
        "latency_ms" => {
          "max" => queries.map { |query| query.fetch("latency_ms") }.max,
          "mean" => mean(queries.map { |query| query.fetch("latency_ms") })
        }
      }
    end

    def mean(values)
      return 0.0 if values.empty?
      (values.sum.to_f / values.length).round(6)
    end

    def self.record(id, layer, content, tags, confidence, status: "approved")
      {
        "id" => id,
        "status" => status,
        "layer" => layer,
        "content" => content,
        "source" => { "kind" => "synthetic", "reference" => id },
        "confidence" => confidence,
        "approved_at" => "2026-08-23T12:00:00.000000Z",
        "created_at" => "2026-08-23T12:00:00.000000Z",
        "updated_at" => "2026-08-23T12:00:00.000000Z",
        "tags" => tags,
        "metadata" => {}
      }
    end
  end

  class MemoryRetrievalLexicalRanker
    def rank(records, query, limit: 20)
      query_tokens = tokens(query)
      Array(records).filter_map do |record|
        terms = tokens([record.fetch("content"), Array(record["tags"]).join(" ")].join(" "))
        overlap = (query_tokens & terms).length
        next unless overlap.positive?
        {
          "memory_id" => record.fetch("id").to_s,
          "score" => overlap,
          "excerpt" => record.fetch("content")[0, 280]
        }
      end.sort_by { |result| [-result.fetch("score"), result.fetch("memory_id")] }.first(limit.to_i)
    end

    private

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).uniq
    end
  end

  MemoryRetrievalEvaluator = MemoryRetrievalEvaluationHarness
end
