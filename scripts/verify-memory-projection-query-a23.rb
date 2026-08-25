#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require_relative "../lib/soul_core/memory_projection_query_service"
require_relative "../lib/soul_core/memory_projection_transports"

record = {
  "id" => "mem_fixture", "status" => "approved", "layer" => "preference",
  "content" => "The operator prefers bounded local memory retrieval.",
  "source" => {"kind" => "conversation", "reference" => "fixture"},
  "approved_at" => "2026-08-24T00:00:00Z"
}
approved_digest = "a" * 64
payload_digest = "b" * 64
selector = {
  "generation_id" => "generation_#{'b' * 20}", "payload_digest" => payload_digest,
  "source_digests" => {"canonical_state" => "c" * 64, "approved_index" => approved_digest},
  "qdrant_collection" => "soul_memory_vectors_#{'b' * 20}", "falkor_graph" => "SoulMemory_#{'b' * 20}",
  "schema" => "soul.memory_projection_reconciler.a21.v1"
}
content_digest = Digest::SHA256.hexdigest(record.fetch("content").downcase.gsub(/\s+/, " ").strip)

Store = Struct.new(:items) do
  def records(**) = items
end
Selector = Struct.new(:value) do
  def active = value
end
Contract = Struct.new(:receipt) do
  def build = {"lifecycle_state" => "complete", "data" => {"receipt" => receipt}}
end
Embedder = Struct.new(:vector) do
  def embed(_texts) = [vector]
end
Qdrant = Struct.new(:points, :error) do
  def query(**)
    raise error if error
    points
  end
end
Falkor = Struct.new(:edges, :error) do
  def relationships(**)
    raise error if error
    edges
  end
end
Local = Struct.new(:calls) do
  def query(query:, limit:)
    calls << [query, limit]
    {"lifecycle_state" => "complete", "data" => {"query" => query, "results" => [], "retrieval_mode" => "hybrid", "mutation" => "none"}}
  end
end

receipt = {"payload_digest" => payload_digest, "source_digests" => selector.fetch("source_digests")}
point = {
  "id" => "uuid", "score" => 0.84,
  "payload" => {
    "memory_id" => record.fetch("id"), "state" => "approved", "layer" => record.fetch("layer"),
    "source_kind" => record.dig("source", "kind"), "content_digest" => content_digest,
    "canonical_source_digest" => approved_digest, "remote_content" => "must never be trusted"
  }
}
edge = {"source" => "mem_fixture", "target" => "mem_fixture", "relation" => "EXACT_DUPLICATE"}
local = Local.new([])
service = SoulCore::MemoryProjectionQueryService.new(
  memory_store: Store.new([record]), embedding_client: Embedder.new([0.1, 0.2, 0.3]),
  projection_contract: Contract.new(receipt), selector_store: Selector.new(selector),
  qdrant_client: Qdrant.new([point], nil), falkor_client: Falkor.new([edge], nil),
  local_retrieval: local, clock: -> { Time.utc(2026, 8, 24) }
)

errors = []
checks = 0
check = lambda { |label, condition| checks += 1; errors << label unless condition }
result = service.query(query: "bounded memory", limit: 4)
check.call("projection query completes", result["ok"] && result["lifecycle_state"] == "complete")
check.call("remote projection is labeled and generation bound", result.dig("data", "retrieval_mode") == "remote_projection_local_join" && result.dig("data", "projection_generation") == selector.fetch("generation_id"))
check.call("content is joined from canonical memory", result.dig("data", "results", 0, "excerpt") == record.fetch("content") && !JSON.generate(result).include?("must never be trusted"))
check.call("Qdrant score is preserved as untrusted ranking evidence", result.dig("data", "results", 0, "score") == 0.84)
check.call("explicit FalkorDB relationship is exposed", result.dig("data", "relationships") == [edge])
check.call("query cannot mutate memory", result["mutation"] == "none" && result.dig("data", "mutation") == "none")
check.call("local fallback is unused on success", local.calls.empty?)

stale_selector = selector.merge("payload_digest" => "d" * 64)
stale = SoulCore::MemoryProjectionQueryService.new(
  memory_store: Store.new([record]), embedding_client: Embedder.new([0.1]),
  projection_contract: Contract.new(receipt), selector_store: Selector.new(stale_selector),
  qdrant_client: Qdrant.new([point], nil), falkor_client: Falkor.new([], nil), local_retrieval: local
).query(query: "bounded memory", limit: 3)
check.call("stale selector falls back locally", stale.dig("data", "projection_available") == false && stale.dig("data", "projection_reason") == "projection unavailable: RuntimeError")

misbound_selector = selector.merge("qdrant_collection" => "soul_memory_vectors_#{'e' * 20}")
misbound = SoulCore::MemoryProjectionQueryService.new(
  memory_store: Store.new([record]), embedding_client: Embedder.new([0.1]),
  projection_contract: Contract.new(receipt), selector_store: Selector.new(misbound_selector),
  qdrant_client: Qdrant.new([point], nil), falkor_client: Falkor.new([], nil), local_retrieval: local
).query(query: "bounded memory", limit: 3)
check.call("resource names must be bound to the current payload digest", misbound.dig("data", "projection_available") == false)

unknown = Marshal.load(Marshal.dump(point))
unknown["payload"]["memory_id"] = "unknown"
malformed = SoulCore::MemoryProjectionQueryService.new(
  memory_store: Store.new([record]), embedding_client: Embedder.new([0.1]),
  projection_contract: Contract.new(receipt), selector_store: Selector.new(selector),
  qdrant_client: Qdrant.new([unknown], nil), falkor_client: Falkor.new([], nil), local_retrieval: local
).query(query: "bounded memory", limit: 3)
check.call("unknown remote identifier falls back locally", malformed.dig("data", "projection_available") == false)

unavailable = SoulCore::MemoryProjectionQueryService.new(
  memory_store: Store.new([record]), embedding_client: Embedder.new([0.1]),
  projection_contract: Contract.new(receipt), selector_store: Selector.new(selector),
  qdrant_client: Qdrant.new([], RuntimeError.new("fixture unavailable")), falkor_client: Falkor.new([], nil), local_retrieval: local
).query(query: "bounded memory", limit: 3)
check.call("remote failure preserves local retrieval", unavailable["lifecycle_state"] == "complete" && unavailable.dig("data", "projection_available") == false)
check.call("fallback reason exposes only exception class", !JSON.generate(unavailable).include?("fixture unavailable"))

other_record = record.merge("id" => "mem_other", "content" => "Unrelated approved memory")
unrelated_edge = {"source" => "mem_other", "target" => "mem_other", "relation" => "EXACT_DUPLICATE"}
unrelated = SoulCore::MemoryProjectionQueryService.new(
  memory_store: Store.new([record, other_record]), embedding_client: Embedder.new([0.1]),
  projection_contract: Contract.new(receipt), selector_store: Selector.new(selector),
  qdrant_client: Qdrant.new([point], nil), falkor_client: Falkor.new([unrelated_edge], nil), local_retrieval: local
).query(query: "bounded memory", limit: 3)
check.call("relationships outside the queried result set fall back", unrelated.dig("data", "projection_available") == false)

empty = service.query(query: " ")
long = service.query(query: "x" * 201)
check.call("empty and oversized queries await input", [empty, long].all? { |value| value["lifecycle_state"] == "awaiting_input" })
invalid_limits = ["not-a-number", 0, 21].map { |value| service.query(query: "bounded memory", limit: value) }
check.call("invalid limits await input without invoking fallback", invalid_limits.all? { |value| value["lifecycle_state"] == "awaiting_input" })

source = File.binread(File.expand_path("../lib/soul_core/memory_projection_query_service.rb", __dir__))
check.call("service has no persistence or background execution", !source.match?(/File\.(?:write|open|rename|delete)|Thread\.new|systemd|setInterval|retry/))
check.call("service performs no remote writes", !source.match?(/\.prepare\(|\.delete\(|\.activate\(/))

Response = SoulCore::BoundedJsonTlsTransport::Response
transport_calls = []
transport = Object.new
transport.define_singleton_method(:request) do |method, path, body: nil|
  transport_calls << [method, path, body]
  Response.new(code: 200, body: JSON.generate("result" => {"points" => [point]}))
end
remote_points = SoulCore::QdrantProjectionClient.new(transport: transport).query(
  name: selector.fetch("qdrant_collection"), vector: [0.1, 0.2, 0.3], limit: 4
)
check.call("Qdrant query is bounded and payload-only", remote_points == [point] && transport_calls == [[
  "POST", "/collections/#{selector.fetch('qdrant_collection')}/points/query",
  {"query" => [0.1, 0.2, 0.3], "limit" => 4, "with_payload" => true, "with_vector" => false}
]])

malformed_qdrant_transport = Object.new
malformed_qdrant_transport.define_singleton_method(:request) do |*_args, **_kwargs|
  Response.new(code: 200, body: JSON.generate("result" => {}))
end
begin
  SoulCore::QdrantProjectionClient.new(transport: malformed_qdrant_transport).query(
    name: selector.fetch("qdrant_collection"), vector: [0.1], limit: 1
  )
  malformed_qdrant_rejected = false
rescue RuntimeError
  malformed_qdrant_rejected = true
end
check.call("Qdrant missing points field is rejected", malformed_qdrant_rejected)

relationship_client = Object.new
relationship_client.define_singleton_method(:call) do |*parts|
  query = parts.fetch(2)
  raise "unexpected mutating query" unless parts.first == "GRAPH.RO_QUERY" && query.include?("WHERE a.id IN")
  [[], [[[2, "mem_fixture"], [2, "mem_fixture"], [2, "EXACT_DUPLICATE"]]], []]
end
remote_edges = SoulCore::FalkorProjectionClient.new(command_client: relationship_client).relationships(
  name: selector.fetch("falkor_graph"), memory_ids: ["mem_fixture"]
)
check.call("FalkorDB relationship lookup is explicit and read-only", remote_edges == [edge])

malformed_relationship_client = Object.new
malformed_relationship_client.define_singleton_method(:call) { |*| [[], nil, []] }
begin
  SoulCore::FalkorProjectionClient.new(command_client: malformed_relationship_client).relationships(
    name: selector.fetch("falkor_graph"), memory_ids: ["mem_fixture"]
  )
  malformed_falkor_rejected = false
rescue RuntimeError
  malformed_falkor_rejected = true
end
check.call("FalkorDB missing row block is rejected", malformed_falkor_rejected)

load File.expand_path("soul-memory-projection-query", __dir__)
check.call(
  "CLI leaves local retrieval available when embedding config is absent",
  SoulMemoryProjectionQueryCLI.optional_embedding_client({}).nil?
)
missing_clients = SoulMemoryProjectionQueryCLI.projection_clients(
  {"SOUL_MEMORY_PROJECTION_PRIVATE_CONFIG" => "/nonexistent/projection.json"},
  "/tmp"
)
check.call(
  "CLI represents unavailable private projection config without aborting construction",
  missing_clients.all? { |client| client.is_a?(SoulMemoryProjectionQueryCLI::UnavailableProjectionDependency) }
)

abort "Memory projection query A23 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection query A23 verification passed (#{checks} checks)."
