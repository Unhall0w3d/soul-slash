#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/memory_automatic_projection_reconciliation_service"
require_relative "../lib/soul_core/memory_lifecycle_projection_coordinator"
require_relative "../lib/soul_core/memory_projection_reconciliation_request_store"

class A33MemoryFixture
  attr_accessor :records_value
  def initialize
    @records_value = [{"id" => "mem_a", "status" => "approved", "content" => "fixture",
      "layer" => "semantic", "source" => {"kind" => "fixture"}, "confidence" => 1.0,
      "created_at" => "2026-08-27T00:00:00Z", "updated_at" => "2026-08-27T00:00:00Z",
      "approved_at" => "2026-08-27T00:00:00Z"}]
  end
  def records(status: nil, **) = @records_value.select { |row| status.nil? || row["status"] == status }
end

class A33AuditFixture
  attr_accessor :head
  def initialize = @head = "a" * 64
  def verify = {"ok" => true, "chain_head_sha256" => @head}
end

class A33IndexFixture
  attr_accessor :source, :rebuild_error, :after_rebuild
  attr_reader :rebuilds
  def initialize
    @source = nil
    @rebuilds = 0
  end
  def availability = {"available" => !@source.nil?, "source_digest" => @source}
  def rebuild
    @rebuilds += 1
    raise @rebuild_error if @rebuild_error
    @after_rebuild.call if @after_rebuild
    @source = $a33_source
    {"lifecycle_state" => "complete", "source_digest" => @source}
  end
end

class A33SelectorFixture
  attr_accessor :value
  def active = @value
  def activate(value) = @value = value
  def deactivate = @value = nil
end

class A33ReconcilerFixture
  attr_accessor :fail_execute
  attr_reader :previews, :executions
  def initialize
    @previews = 0
    @executions = 0
  end
  def preview
    @previews += 1
    {"lifecycle_state" => "blocked_for_human_review", "data" => {
      "source_digests" => {"approved_index" => $a33_source},
      "confirmation_phrase" => "REBUILD_MEMORY_PROJECTION", "expected_digest" => "b" * 64
    }}
  end
  def execute(confirmation:, expected_digest:)
    @executions += 1
    raise "remote fixture failure" if @fail_execute
    raise "gate mismatch" unless confirmation == "REBUILD_MEMORY_PROJECTION" && expected_digest == "b" * 64
    {"ok" => true, "data" => {"generation_id" => "generation_fixture"}}
  end
end

class A33MaintenanceFixture
  attr_accessor :work
  attr_reader :runs
  def initialize(work: false)
    @work = work
    @runs = []
  end
  def work_status = {"ok" => true, "work_available" => @work, "work_digest" => "c" * 64, "content_included" => false}
  def run(request_id:)
    @runs << request_id
    {"ok" => true, "cycle_id" => "cycle_fixture", "cycle_sha256" => "d" * 64,
      "mode" => "exact_duplicate_consolidation", "decision_counts" => {}, "rollback_references" => [],
      "idempotent" => false, "projection_reconciliation_required" => true, "content_included" => false}
  end
end

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Dir.mktmpdir("soul-a33-") do |root|
  memory = A33MemoryFixture.new
  audit = A33AuditFixture.new
  index = A33IndexFixture.new
  selector = A33SelectorFixture.new
  reconciler = A33ReconcilerFixture.new
  requests = SoulCore::MemoryProjectionReconciliationRequestStore.new(root: root,
    path: File.join(root, "private/request.json"), audit_path: File.join(root, "private/audit.jsonl"))
  service = SoulCore::MemoryAutomaticProjectionReconciliationService.new(
    memory_store: memory, audit_service: audit, index_service: index,
    reconciler: reconciler, selector_store: selector, request_store: requests)

  status = service.work_status
  $a33_source = requests.current.fetch("source_digest")
  assert.call(status["work_available"] && status["request_id"].start_with?("mpr_"), "drift creates durable work")
  assert.call(File.stat(File.join(root, "private/request.json")).mode & 0o077 == 0, "request remains owner private")
  result = service.run(request_id: status.fetch("request_id"))
  assert.call(result["ok"] && result["generation_id"] == "generation_fixture", "local rebuild and verified activation complete")
  assert.call(index.rebuilds == 1 && reconciler.previews == 1 && reconciler.executions == 1, "reconciliation performs one bounded sequence")
  assert.call(requests.current["state"] == "complete", "completion is durably checkpointed")
  audit_rows = File.readlines(File.join(root, "private/audit.jsonl")).map { |line| JSON.parse(line) }
  forbidden = %w[content embedding query credential path payload]
  assert.call(audit_rows.all? { |row| row["content_included"] == false && (row.keys & forbidden).empty? }, "audit is content-free")

  selector.value = {"source_digests" => {"approved_index" => $a33_source,
    "canonical_state" => requests.current.fetch("canonical_state_digest")}}
  assert.call(service.work_status["work_available"] == false, "aligned derived state abstains")

  memory.records_value.first["updated_at"] = "2026-08-27T00:01:00Z"
  audit.head = "e" * 64
  index.source = nil
  reconciler.fail_execute = true
  3.times do
    current = service.work_status
    service.run(request_id: current.fetch("request_id")) if current["work_available"]
  end
  blocked = service.work_status
  assert.call(blocked["work_available"] == false && blocked["blocked_for_human_review"], "three failures stop automatic retries")

  memory.records_value.first["updated_at"] = "2026-08-27T00:02:00Z"
  audit.head = "f" * 64
  newer = service.work_status
  assert.call(newer["work_available"] && newer["attempts"] == 0, "new canonical state supersedes a blocked request")
  requests.cancel
  canceled = service.work_status
  assert.call(canceled["work_available"] == false && canceled["canceled"], "explicit cancellation suppresses the same source digest")

  maintenance = A33MaintenanceFixture.new(work: true)
  coordination = SoulCore::MemoryLifecycleProjectionCoordinator.new(
    maintenance_service: maintenance, reconciliation_service: service)
  assert.call(coordination.work_status["work_kind"] == "canonical_memory", "canonical work has priority")
  executions_before = reconciler.executions
  cycle = coordination.run(request_id: "a33-canonical")
  assert.call(cycle["projection_request_persisted"] == true && reconciler.executions == executions_before,
    "canonical activation records later work without reconciling it")

  source = File.read(File.join(__dir__, "../lib/soul_core/memory_automatic_projection_reconciliation_service.rb"))
  assert.call(!source.match?(/Thread|sleep|loop\s+do|setInterval|system\(|`/), "service adds no loop or shell authority")
  worker = File.read(File.join(__dir__, "soul-memory-lifecycle-worker"))
  assert.call(worker.include?("MemoryLifecycleProjectionCoordinator") && worker.include?("build_reconciler"), "existing worker owns A33 integration")
  deployment = File.read(File.join(__dir__, "../lib/soul_core/memory_core_aware_worker_deployment.rb"))
  assert.call(deployment.scan(/soul-memory-lifecycle\.timer/).any? && !deployment.include?("projection.timer"), "existing timer is reused")
end

puts "Memory automatic projection reconciliation A33 verifier passed (#{checks} checks)."
