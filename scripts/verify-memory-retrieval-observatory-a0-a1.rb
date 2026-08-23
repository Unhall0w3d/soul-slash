#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/memory_retrieval_evaluator"
require_relative "../lib/soul_core/memory_retrieval_index"
require_relative "../lib/soul_core/memory_retrieval_service"

include SoulCore

errors = []
check = lambda do |name, condition|
  errors << name unless condition
end

harness = MemoryRetrievalEvaluationHarness.new
evaluation = harness.run
check.call("A0 harness completes", evaluation["lifecycle_state"] == "complete")
check.call("A0 corpus demonstrates semantic recall gain", evaluation.dig("hybrid_gain", "recall").to_f.positive?)
check.call("A0 hybrid precision does not regress", evaluation.dig("hybrid_gain", "precision").to_f >= 0.0)
check.call("A0 reports per-query evidence", evaluation.fetch("queries").all? { |query| query.key?("score_components") && query.key?("latency_ms") })

class FailingEmbeddingClient
  attr_reader :profile, :dimensions

  def initialize
    @dimensions = 5
    @profile = { "name" => "synthetic-a0-v1", "dimensions" => @dimensions }
  end

  def embed(_texts)
    raise "synthetic transient failure"
  end
end

Dir.mktmpdir("soul-memory-retrieval-verifier") do |directory|
  records = MemoryRetrievalEvaluationHarness.synthetic_records
  store = MemoryRetrievalEvaluationHarness::FixtureStore.new(records)
  client = MemoryRetrievalEvaluationHarness::DeterministicEmbeddingClient.new
  index_path = File.join(directory, "approved-memory-index.json")
  index = ApprovedMemoryIndexService.new(memory_store: store, index_path: index_path, embedding_client: client)
  rebuilt = index.rebuild
  check.call("approved-only index rebuild completes", rebuilt["lifecycle_state"] == "complete" && rebuilt.dig("data", "entry_count") == 6)
  envelope = JSON.parse(File.read(index_path))
  check.call("candidate and deleted records are absent", envelope["entries"].none? { |entry| %w[mem_candidate mem_deleted].include?(entry["memory_id"]) })
  check.call("index exposes source and payload digests", envelope["source_digest"].to_s.length == 64 && envelope["payload_digest"].to_s.length == 64)

  retrieval = ApprovedMemoryRetrievalService.new(memory_store: store, index_service: index, embedding_client: client)
  hybrid = retrieval.query(query: "spacecraft flight", limit: 5)
  check.call("hybrid result exposes bounded explainable components", hybrid.dig("data", "results", 0, "score_components").values.all? { |value| value.to_f.between?(0.0, 1.0) })
  check.call("hybrid result names approved source memory", hybrid.dig("data", "results", 0, "memory_id") == "mem_vehicle")

  File.write(index_path, "not json")
  fallback = retrieval.query(query: "rotating frame conversion", limit: 5)
  check.call("malformed index falls back to lexical retrieval", fallback.dig("data", "retrieval_mode") == "lexical_fallback" && fallback.dig("data", "results", 0, "memory_id") == "mem_vehicle")

  index.rebuild
  stale_clock = -> { Time.utc(2026, 8, 25) }
  stale_index = ApprovedMemoryIndexService.new(memory_store: store, index_path: index_path, embedding_client: client, clock: stale_clock, max_age_seconds: 1)
  stale_retrieval = ApprovedMemoryRetrievalService.new(memory_store: store, index_service: stale_index, embedding_client: client, clock: stale_clock)
  stale = stale_retrieval.query(query: "rotating frame conversion", limit: 5)
  check.call("stale index falls back to lexical retrieval", stale.dig("data", "retrieval_mode") == "lexical_fallback")

  index.rebuild
  prior_bytes = File.binread(index_path)
  failed_index = ApprovedMemoryIndexService.new(memory_store: store, index_path: index_path, embedding_client: FailingEmbeddingClient.new)
  failed = failed_index.rebuild
  check.call("failed rebuild does not replace prior valid index", failed["lifecycle_state"] == "failed" && File.binread(index_path) == prior_bytes)

  tampered = JSON.parse(prior_bytes)
  tampered["dimensions"] = 4
  File.write(index_path, JSON.generate(tampered))
  dimension_fallback = retrieval.query(query: "rotating frame conversion", limit: 5)
  check.call("dimension mismatch fails closed", dimension_fallback.dig("data", "retrieval_mode") == "lexical_fallback")

  if Gem.win_platform? == false
    File.delete(index_path)
    File.symlink("/dev/null", index_path)
    check.call("symlinked index fails closed", index.availability["available"] == false)
  end
end

unless Gem.win_platform?
  Dir.mktmpdir("soul-memory-retrieval-symlink-parent") do |directory|
    private_root = File.join(directory, "private")
    outside = File.join(directory, "outside")
    FileUtils.mkdir_p([private_root, outside])
    File.symlink(outside, File.join(private_root, "derived"))
    records = MemoryRetrievalEvaluationHarness.synthetic_records
    store = MemoryRetrievalEvaluationHarness::FixtureStore.new(records)
    begin
      ApprovedMemoryIndexService.new(
        memory_store: store,
        index_path: File.join(private_root, "derived", "index.json"),
        allowed_root: private_root
      )
      errors << "symlinked index parent was accepted"
    rescue StandardError
      # expected
    end
  end
end

begin
  LocalLoopbackEmbeddingClient.new(endpoint: "http://192.0.2.10:8080/embed", profile: { "name" => "x", "dimensions" => 2 })
  errors << "remote embedding endpoint was accepted"
rescue ArgumentError
  # expected
end

ollama_client = LocalLoopbackEmbeddingClient.new(
  endpoint: "http://127.0.0.1:11434/api/embed",
  profile: { "name" => "fixture-embedding", "dimensions" => 2 }
)
ollama_payload = ollama_client.send(:request_payload, ["bounded input"])
check.call("default local embedding payload matches Ollama embed API", ollama_payload == { "model" => "fixture-embedding", "input" => ["bounded input"], "truncate" => false })

if errors.empty?
  puts "Memory retrieval Observatory A0-A1 deterministic verification passed."
else
  warn "Memory retrieval Observatory A0-A1 verification failed: #{errors.join(', ')}"
  exit 1
end
