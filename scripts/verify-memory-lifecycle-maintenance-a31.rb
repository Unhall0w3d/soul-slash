#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/memory_lifecycle_maintenance_service"

class A31LifecycleFixture
  attr_reader :runs

  def initialize(work:, digest: "1" * 64)
    @work = work
    @digest = digest
    @runs = []
  end

  def work_status
    { "ok" => true, "work_available" => @work, "work_digest" => @digest,
      "content_included" => false }
  end

  def run(request_id:)
    @runs << request_id
    { "ok" => true, "lifecycle_state" => "complete", "cycle_id" => "mac_fixture",
      "cycle_sha256" => "2" * 64, "mode" => "derive_and_admit",
      "decision_counts" => { "admitted_active" => 1 }, "rollback_references" => [],
      "idempotent" => false, "content_included" => false }
  end
end

class A31ConsolidationFixture
  attr_reader :runs

  def initialize(work:, idempotent: false)
    @work = work
    @idempotent = idempotent
    @runs = []
  end

  def preview
    { "ok" => true, "data" => { "work_available" => @work,
      "survivor_id" => @work ? "mem_a" : nil,
      "superseded_id" => @work ? "mem_b" : nil, "content_included" => false } }
  end

  def run(request_id:)
    @runs << request_id
    { "ok" => true, "data" => { "no_work" => false, "idempotent" => @idempotent,
      "rollback_reference" => "memory-consolidate:fixture", "content_included" => false } }
  end
end

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

lifecycle = A31LifecycleFixture.new(work: true)
consolidation = A31ConsolidationFixture.new(work: true)
service = SoulCore::MemoryLifecycleMaintenanceService.new(
  lifecycle_service: lifecycle, consolidation_service: consolidation
)
status = service.work_status
assert.call(status["work_kind"] == "observation_lifecycle", "ordinary lifecycle work has priority")
cycle = service.run(request_id: "a31-fixture")
assert.call(cycle["mode"] == "derive_and_admit" && lifecycle.runs.one?, "ordinary lifecycle runs unchanged")
assert.call(consolidation.runs.empty?, "consolidation does not share an ordinary lifecycle activation")

lifecycle = A31LifecycleFixture.new(work: false)
consolidation = A31ConsolidationFixture.new(work: true)
service = SoulCore::MemoryLifecycleMaintenanceService.new(
  lifecycle_service: lifecycle, consolidation_service: consolidation
)
first = service.work_status
second = service.work_status
assert.call(first["work_kind"] == "exact_duplicate_consolidation", "consolidation runs only after ordinary work is clear")
assert.call(first["work_digest"] == second["work_digest"] && first["work_digest"].match?(/\A[0-9a-f]{64}\z/), "maintenance identity is deterministic")
cycle = service.run(request_id: "a31-consolidate")
assert.call(cycle["mode"] == "exact_duplicate_consolidation" && consolidation.runs.one?, "one exact duplicate is consolidated")
assert.call(cycle["decision_counts"] == { "superseded_exact_duplicates" => 1 }, "receipt reports one bounded mutation")
assert.call(cycle["projection_reconciliation_required"] == true, "canonical change exposes projection reconciliation requirement")
assert.call(cycle["rollback_references"] == ["memory-consolidate:fixture"], "canonical rollback remains visible")

empty = SoulCore::MemoryLifecycleMaintenanceService.new(
  lifecycle_service: A31LifecycleFixture.new(work: false),
  consolidation_service: A31ConsolidationFixture.new(work: false)
).work_status
assert.call(empty["work_available"] == false && empty["work_kind"] == "none", "no work abstains")

source = File.read(File.join(__dir__, "../lib/soul_core/memory_lifecycle_maintenance_service.rb"))
assert.call(!source.match?(/Thread|sleep|loop\s+do|Net::HTTP|TCPSocket|UDPSocket/), "integration adds no loop or network authority")
worker = File.read(File.join(__dir__, "soul-memory-lifecycle-worker"))
assert.call(worker.include?("MemoryLifecycleMaintenanceService") && worker.include?("MemoryExactDuplicateConsolidationService"), "existing Core-aware worker owns the integration")
assert.call(!worker.match?(/projection.*(reconcile|execute)/i), "worker never rebuilds the remote projection")
retrieval_cli = File.read(File.join(__dir__, "memory-retrieval-observatory.rb"))
assert.call(retrieval_cli.include?("EnvLoader.load") && retrieval_cli.include?("env.equal?(ENV)"), "manual index rebuild loads configured local embedding profile")
assert.call(!JSON.generate(cycle).match?(/content.*secret/i), "receipt is content-free")

puts "Memory lifecycle maintenance A31 verifier passed (#{checks} checks)."
