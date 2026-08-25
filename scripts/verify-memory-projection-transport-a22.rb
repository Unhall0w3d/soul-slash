#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/memory_projection_transports"

errors = []
checks = 0
check = lambda { |label, condition| checks += 1; errors << label unless condition }

selector_value = {
  "schema" => "soul.memory_projection_reconciler.a21.v1",
  "generation_id" => "generation_#{'a' * 20}", "payload_digest" => "b" * 64,
  "source_digests" => {"canonical_state" => "c" * 64, "approved_index" => "d" * 64},
  "qdrant_collection" => "soul_memory_vectors_#{'a' * 20}", "falkor_graph" => "SoulMemory_#{'a' * 20}"
}
Dir.mktmpdir("selector-a22-") do |root|
  private_root = File.join(root, "private")
  path = File.join(private_root, "projection", "active-generation.json")
  store = SoulCore::MemoryProjectionSelectorStore.new(private_root: private_root, path: path)
  check.call("absent selector is nil", store.active.nil?)
  store.activate(selector_value)
  check.call("selector round trips exactly", store.active == selector_value)
  check.call("selector is owner private", (File.stat(path).mode & 0o777) == 0o600)
  check.call("selector replacement leaves no temporary residue", Dir.children(File.dirname(path)) == [File.basename(path)])
  File.delete(path)
  File.symlink(Dir.mktmpdir("outside-a22-"), File.join(private_root, "projection-link"))
  unsafe = File.join(private_root, "projection-link", "active.json")
  begin
    SoulCore::MemoryProjectionSelectorStore.new(private_root: private_root, path: unsafe).activate(selector_value)
    rejected = false
  rescue StandardError
    rejected = true
  end
  check.call("selector rejects nested symlink", rejected)
end

Response = SoulCore::BoundedJsonTlsTransport::Response
qdrant_payload = {
  "schema" => "soul.memory_qdrant_projection.a18.v1", "dimensions" => 3,
  "points" => [{"id" => "5d14f8c0-a9c5-55c4-a17e-6da89258a031", "vector" => [0.1, 0.2, 0.3],
    "payload" => {"memory_id" => "mem_1", "state" => "approved"}}]
}
q_requests = []
q_transport = Object.new
q_transport.define_singleton_method(:request) do |method, path, body: nil|
  q_requests << [method, path, body]
  if method == "GET"
    Response.new(code: 404, body: "")
  elsif path.end_with?("/scroll")
    Response.new(code: 200, body: JSON.generate("result" => {"points" => qdrant_payload.fetch("points"), "next_page_offset" => nil}))
  else
    Response.new(code: 200, body: JSON.generate("status" => "ok"))
  end
end
qdrant = SoulCore::QdrantProjectionClient.new(transport: q_transport)
q_name = "soul_memory_vectors_#{'a' * 20}"
check.call("Qdrant generation is created", qdrant.prepare(name: q_name, payload: qdrant_payload) == "created")
check.call("Qdrant writes wait for commit", q_requests.any? { |request| request[1].end_with?("points?wait=true") })
check.call("Qdrant verifies exact payload", qdrant.verify(name: q_name).fetch("payload_digest").match?(/\A[0-9a-f]{64}\z/))

falkor_payload = {
  "schema" => "soul.memory_falkor_projection.a18.v1",
  "nodes" => [{"id" => "mem_1", "labels" => %w[Memory Semantic], "properties" => {
    "layer" => "semantic", "source_kind" => "conversation", "content_digest" => "e" * 64,
    "canonical_source_digest" => "f" * 64, "state" => "approved",
    "created_at" => "2026-08-24T00:00:00Z", "updated_at" => "2026-08-24T00:00:01Z"
  }}], "edges" => []
}
f_commands = []
f_client = Object.new
f_client.define_singleton_method(:call) do |*parts|
  f_commands << parts
  return [] if parts.first == "GRAPH.LIST"
  query = parts[2].to_s
  if query.include?("RETURN n.id")
    node = falkor_payload.fetch("nodes").first
    [[], [[node.fetch("id"), node.fetch("labels"), *SoulCore::FalkorProjectionClient::NODE_FIELDS.map { |field| node.fetch("properties").fetch(field) }]], []]
  elsif query.include?("RETURN a.id")
    [[], [], []]
  else
    [[], [], []]
  end
end
f_client.define_singleton_method(:pipeline) { |commands| f_commands.concat(commands); commands.map { [[], [], []] } }
falkor = SoulCore::FalkorProjectionClient.new(command_client: f_client)
f_name = "SoulMemory_#{'a' * 20}"
check.call("FalkorDB generation is created", falkor.prepare(name: f_name, payload: falkor_payload) == "created")
check.call("FalkorDB uses bounded command batches", f_commands.length <= 128)
check.call("FalkorDB verifies exact payload", falkor.verify(name: f_name).fetch("payload_digest").match?(/\A[0-9a-f]{64}\z/))
check.call("FalkorDB readback uses read-only queries", f_commands.any? { |command| command.first == "GRAPH.RO_QUERY" })

source = File.binread(File.expand_path("../lib/soul_core/memory_projection_transports.rb", __dir__))
cli_source = File.binread(File.expand_path("soul-memory-projection-reconcile", __dir__))
check.call("transport does not use shell commands", !source.match?(/Open3|Kernel\.system|Process\.spawn|IO\.popen|`/))
check.call("Redis password is sent only through RESP AUTH", source.include?('frame(["AUTH", @password])'))
check.call("Redis TLS work has a bounded read timeout", source.include?("Timeout.timeout(@read_timeout)"))
check.call("no background or retry loop exists", ![source, cli_source].join.match?(/Thread\.new|setInterval|systemd|retry/))
check.call("CLI requires a fresh exact execute gate", cli_source.include?('command == "execute" && argv.length == 2') && cli_source.include?("expected_digest: argv.shift.to_s"))
check.call("CLI rejects symlinked or broadly readable private files", cli_source.include?("private path contains a symlink component") && cli_source.include?("private path permissions are too broad"))
check.call("CLI retains local authoritative fallback", cli_source.include?("local_authoritative_retrieval"))

abort "Memory projection transport A22 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection transport A22 verification passed (#{checks} checks)."
