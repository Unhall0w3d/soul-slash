#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require_relative "../lib/soul_core/memory_projection_reconciler"

def canonical(value)
  case value
  when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
  when Array then value.map { |item| canonical(item) }
  else value
  end
end

def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))

class ContractFixture
  attr_accessor :result
  def initialize(result) = @result = result
  def build = @result
end

class ProjectionClientFixture
  attr_accessor :prepare_state, :fail_prepare, :fail_verify
  def initialize(label, events) = (@label, @events, @prepare_state = label, events, "created")
  def prepare(name:, payload:)
    @events << [@label, "prepare", name]
    raise "prepare failure" if @fail_prepare
    @payload = payload
    @prepare_state
  end
  def verify(name:)
    @events << [@label, "verify", name]
    raise "verify failure" if @fail_verify
    {"payload_digest" => digest(@payload)}
  end
  def delete(name:) = (@events << [@label, "delete", name]; true)
end

class SelectorFixture
  attr_reader :events
  attr_accessor :fail_activate
  def initialize(events, active = nil) = (@events, @active = events, active)
  def active = @active
  def activate(value)
    @events << ["selector", "activate", value.fetch("generation_id")]
    raise "selector failure" if @fail_activate
    @active = value
  end
end

errors = []
checks = 0
check = lambda { |label, condition| checks += 1; errors << label unless condition }
secret = "private raw memory sentence"
bundle = {
  "schema" => "soul.memory_projection_contract.a18.v1", "authority" => "conversation_memory_ledger",
  "source_digests" => {"canonical_state" => "a" * 64, "approved_index" => "b" * 64},
  "qdrant" => {"schema" => "soul.memory_qdrant_projection.a18.v1", "dimensions" => 3,
    "points" => [{"id" => "5d14f8c0-a9c5-55c4-a17e-6da89258a031", "vector" => [0.1, 0.2, 0.3],
      "payload" => {"memory_id" => "mem_1", "content_digest" => "c" * 64}}]},
  "falkor" => {"schema" => "soul.memory_falkor_projection.a18.v1",
    "nodes" => [{"id" => "mem_1", "labels" => %w[Memory Semantic], "properties" => {"state" => "approved"}}], "edges" => []}
}
receipt = {
  "schema" => bundle.fetch("schema"), "authority" => bundle.fetch("authority"),
  "source_digests" => bundle.fetch("source_digests"), "payload_digest" => digest(bundle),
  "qdrant" => {"schema" => bundle.dig("qdrant", "schema"), "point_count" => 1, "dimensions" => 3},
  "falkor" => {"schema" => bundle.dig("falkor", "schema"), "node_count" => 1, "edge_count" => 0}, "content_included" => false
}
contract = ContractFixture.new({"lifecycle_state" => "complete", "data" => {"bundle" => bundle, "receipt" => receipt}, "mutation" => "none"})
make = lambda do |events, selector: nil|
  qdrant = ProjectionClientFixture.new("qdrant", events)
  falkor = ProjectionClientFixture.new("falkor", events)
  selector ||= SelectorFixture.new(events, {"generation_id" => "generation_previous"})
  [SoulCore::MemoryProjectionReconciler.new(contract: contract, qdrant_client: qdrant, falkor_client: falkor, selector_store: selector), qdrant, falkor, selector]
end

events = []
service, qdrant, falkor, selector = make.call(events)
preview = service.preview
plan = preview.fetch("data")
check.call("preview is review gated", !preview.fetch("ok") && preview.fetch("lifecycle_state") == "blocked_for_human_review")
check.call("preview is content and vector free", !JSON.generate(preview).include?(secret) && !JSON.generate(preview).include?("0.1"))
check.call("preview names are digest-derived", plan.fetch("qdrant_collection").match?(/\Asoul_memory_vectors_[0-9a-f]{20}\z/) && plan.fetch("falkor_graph").match?(/\ASoulMemory_[0-9a-f]{20}\z/))
check.call("preview is deterministic", preview == service.preview)
stale = service.execute(confirmation: "REBUILD_MEMORY_PROJECTION", expected_digest: "0" * 64)
check.call("stale digest executes nothing", stale.fetch("lifecycle_state") == "blocked_for_human_review" && events.empty?)
completed = service.execute(confirmation: plan.fetch("confirmation_phrase"), expected_digest: plan.fetch("expected_digest"))
check.call("dual verification precedes activation", events.map { |event| event[0, 2] } == [["qdrant", "prepare"], ["falkor", "prepare"], ["qdrant", "verify"], ["falkor", "verify"], ["selector", "activate"]])
check.call("successful activation is content free", completed.fetch("ok") && completed.dig("data", "previous_generation_id") == "generation_previous" && !JSON.generate(completed).include?(secret))
check.call("selector records exact paired generation", selector.active.fetch("qdrant_collection") == plan.fetch("qdrant_collection") && selector.active.fetch("falkor_graph") == plan.fetch("falkor_graph"))

events = []
service, qdrant, falkor, selector = make.call(events)
falkor.fail_prepare = true
failed = service.execute(confirmation: plan.fetch("confirmation_phrase"), expected_digest: plan.fetch("expected_digest"))
check.call("partial creation cleans only created Qdrant generation", events.map { |event| event[0, 2] } == [["qdrant", "prepare"], ["falkor", "prepare"], ["qdrant", "delete"]])
check.call("partial failure preserves selector and fallback", !failed.fetch("ok") && selector.active.fetch("generation_id") == "generation_previous" && failed.dig("data", "fallback") == "local_authoritative_retrieval")
check.call("client error details are not returned", !JSON.generate(failed).include?("prepare failure") && failed.fetch("reason").include?("falkor_prepare"))

events = []
service, qdrant, falkor, = make.call(events)
qdrant.prepare_state = "existing"
falkor.fail_verify = true
service.execute(confirmation: plan.fetch("confirmation_phrase"), expected_digest: plan.fetch("expected_digest"))
check.call("pre-existing generation is not compensation-deleted", !events.any? { |event| event[0] == "qdrant" && event[1] == "delete" } && events.any? { |event| event[0] == "falkor" && event[1] == "delete" })

events = []
selector = SelectorFixture.new(events, {"generation_id" => "generation_previous"})
selector.fail_activate = true
service, = make.call(events, selector: selector)
failed = service.execute(confirmation: plan.fetch("confirmation_phrase"), expected_digest: plan.fetch("expected_digest"))
check.call("selector failure preserves previous activation", !failed.fetch("ok") && selector.active.fetch("generation_id") == "generation_previous")
check.call("selector failure compensates both new generations", events.count { |event| event[1] == "delete" } == 2)
contract.result = {"lifecycle_state" => "failed", "message" => "contains #{secret}", "mutation" => "none"}
failed = service.preview
check.call("contract failure is redacted and local-fallback", !JSON.generate(failed).include?(secret) && failed.dig("data", "fallback") == "local_authoritative_retrieval")
source = File.binread(File.expand_path("../lib/soul_core/memory_projection_reconciler.rb", __dir__))
check.call("coordinator has no transport or persistence primitives", !source.match?(/Net::HTTP|TCPSocket|OpenSSL|File\.(write|open|rename)|Kernel\.system|Open3|Process\.spawn|IO\.popen/))
check.call("coordinator performs no canonical mutation", !source.match?(/\.approve|\.supersede|\.delete\(memory|\.propose/))
abort "Memory projection reconciliation A21 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection reconciliation A21 verification passed (#{checks} checks)."
