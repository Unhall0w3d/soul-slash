#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/memory_projection_contract"

errors = []
checks = 0
check = lambda do |name, condition|
  checks += 1
  errors << name unless condition
end

RecordStore = Struct.new(:items) do
  def records(include_deleted: false)
    include_deleted ? items : items.reject { |item| item["status"] == "deleted" }
  end
end

IndexService = Struct.new(:envelope, :reason) do
  def load_valid_index
    [envelope, reason || "index is valid and fresh"]
  end
end

records = [
  {
    "id" => "mem_alpha", "status" => "approved", "layer" => "semantic",
    "content" => "The operator prefers bounded evidence.", "source" => { "kind" => "chat" },
    "confidence" => 0.98, "created_at" => "2026-08-24T12:00:00Z",
    "updated_at" => "2026-08-24T12:01:00Z", "approved_at" => "2026-08-24T12:01:00Z"
  },
  {
    "id" => "mem_beta", "status" => "superseded", "layer" => "preference",
    "content" => "Use bounded evidence.", "source" => { "kind" => "import" },
    "confidence" => 0.8, "created_at" => "2026-08-23T12:00:00Z",
    "updated_at" => "2026-08-24T12:01:00Z", "superseded_by" => "mem_alpha"
  },
  {
    "id" => "mem_deleted", "status" => "deleted", "layer" => "episodic",
    "content" => "Temporary detail.", "source" => { "kind" => "chat" },
    "confidence" => 0.6, "created_at" => "2026-08-22T12:00:00Z",
    "updated_at" => "2026-08-24T12:01:00Z"
  },
  {
    "id" => "mem_duplicate", "status" => "candidate", "layer" => "project",
    "content" => "  TEMPORARY   detail. ", "source" => { "kind" => "chat" },
    "confidence" => 0.5, "created_at" => "2026-08-21T12:00:00Z",
    "updated_at" => "2026-08-24T12:01:00Z"
  }
]

canonicalize = lambda do |value|
  case value
  when Hash then value.keys.sort.to_h { |key| [key, canonicalize.call(value.fetch(key))] }
  when Array then value.map { |item| canonicalize.call(item) }
  else value
  end
end
approved_records = records.select { |record| record["status"] == "approved" }.sort_by { |record| record.fetch("id") }
source_digest = Digest::SHA256.hexdigest(JSON.generate(canonicalize.call(approved_records)))
index = {
  "schema" => "soul.approved_memory_index.v1",
  "source_digest" => source_digest,
  "dimensions" => 3,
  "entries" => [
    {
      "memory_id" => "mem_alpha", "content" => "The operator prefers bounded evidence.",
      "embedding" => [0.1, 0.2, 0.3]
    }
  ]
}

service = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(records),
  index_service: IndexService.new(index)
)
first = service.build
second = service.build
check.call("projection completes", first["lifecycle_state"] == "complete")
bundle = first.dig("data", "bundle")
receipt = first.dig("data", "receipt")
check.call("projection is deterministic", first == second)
check.call("canonical ledger remains authority", receipt["authority"] == "conversation_memory_ledger")
check.call("receipt is content free", receipt["content_included"] == false && !receipt.to_s.include?("bounded evidence"))
check.call("receipt contains no vectors", !receipt.to_s.include?("0.1"))
check.call("one approved vector point", receipt.dig("qdrant", "point_count") == 1)
check.call("vector payload omits raw content", !bundle.fetch("qdrant").to_s.include?("bounded evidence"))
check.call("vector payload carries canonical id", bundle.dig("qdrant", "points", 0, "payload", "memory_id") == "mem_alpha")
check.call("vector point id is deterministic uuid", bundle.dig("qdrant", "points", 0, "id").match?(/\A[0-9a-f-]{36}\z/))
check.call("all lifecycle states remain graph visible", receipt.dig("falkor", "node_count") == 4)
check.call("supersession remains explicit", bundle.dig("falkor", "edges").any? { |edge| edge["relation"] == "SUPERSEDED_BY" })
check.call("exact duplicate is deterministic", bundle.dig("falkor", "edges").any? { |edge| edge["relation"] == "EXACT_DUPLICATE" })
check.call("graph omits raw content", !bundle.fetch("falkor").to_s.include?("Temporary detail"))
check.call("fallback is authoritative local retrieval", receipt["fallback"] == "local_authoritative_retrieval")
check.call("projection never mutates canonical memory", first["mutation"] == "none" && receipt["mutation"] == "none")

bad_dimension = Marshal.load(Marshal.dump(index))
bad_dimension["entries"][0]["embedding"] = [0.1]
failed_dimension = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(records), index_service: IndexService.new(bad_dimension)
).build
check.call("dimension mismatch fails closed", failed_dimension["lifecycle_state"] == "failed" && failed_dimension["mutation"] == "none")

lexical = index.merge("dimensions" => 0)
failed_lexical = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(records), index_service: IndexService.new(lexical)
).build
check.call("lexical-only index fails closed", failed_lexical["lifecycle_state"] == "failed")

unknown = Marshal.load(Marshal.dump(records))
unknown[0]["status"] = "authoritative_by_consensus"
failed_state = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(unknown), index_service: IndexService.new(index)
).build
check.call("unknown lifecycle state fails closed", failed_state["lifecycle_state"] == "failed")

missing_index = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(records), index_service: IndexService.new(nil, "index is absent")
).build
check.call("missing index fails closed", missing_index["lifecycle_state"] == "failed")

drifted_index = index.merge("source_digest" => "a" * 64)
failed_drift = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(records), index_service: IndexService.new(drifted_index)
).build
check.call("source digest mismatch fails closed", failed_drift["lifecycle_state"] == "failed")

unsafe_source = Marshal.load(Marshal.dump(records))
unsafe_source[0]["source"]["kind"] = "chat\nsecret=value"
failed_source = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(unsafe_source), index_service: IndexService.new(index)
).build
check.call("unsafe source metadata fails closed", failed_source["lifecycle_state"] == "failed")

bad_time = Marshal.load(Marshal.dump(records))
bad_time[0]["updated_at"] = "yesterday"
failed_time = SoulCore::MemoryProjectionContract.new(
  memory_store: RecordStore.new(bad_time), index_service: IndexService.new(index)
).build
check.call("invalid timestamps fail closed", failed_time["lifecycle_state"] == "failed")

source = File.read(File.expand_path("../lib/soul_core/memory_projection_contract.rb", __dir__))
forbidden = %w[Net::HTTP TCPSocket UDPSocket system( spawn( exec( fork( `]
check.call("contract has no network or process execution", forbidden.none? { |token| source.include?(token) })

abort "Memory rebuildable projection A18 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory rebuildable projection A18 verification passed (#{checks} checks)."
