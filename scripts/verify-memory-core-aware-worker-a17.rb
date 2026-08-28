#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/memory_core_aware_worker"
require_relative "../lib/soul_core/memory_core_aware_worker_deployment"

class FixtureLifecycle
  attr_reader :runs, :status_calls

  def initialize(work_available: true, digest: "a" * 64, cycle: nil)
    @work_available = work_available
    @digest = digest
    @cycle = cycle || { "ok" => true, "lifecycle_state" => "complete",
      "cycle_id" => "mac_fixture", "cycle_sha256" => "b" * 64,
      "mode" => "derive_and_admit", "decision_counts" => { "admitted_active" => 1 },
      "rollback_references" => ["memory-admit:mpr_fixture"], "idempotent" => false,
      "content_included" => false }
    @runs = []
    @status_calls = 0
  end

  def work_status
    @status_calls += 1
    { "ok" => true, "lifecycle_state" => "complete", "work_available" => @work_available,
      "pending_derivation_packet" => false,
      "pending_observation_count" => @work_available ? 2 : 0,
      "work_digest" => @digest, "content_included" => false }
  end

  def run(request_id:)
    @runs << request_id
    @cycle
  end
end

class FixtureRunner
  attr_reader :commands

  def initialize
    @commands = []
  end

  def call(command)
    @commands << command
    { "success" => true, "stdout" => "ActiveState=active\n", "stderr" => "" }
  end
end

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

clock = -> { Time.utc(2026, 8, 24, 21, 0, 0) }
Dir.mktmpdir("soul-memory-a17-worker-") do |root|
  status_path = File.join(root, "worker-status.json")
  lifecycle = FixtureLifecycle.new
  worker = SoulCore::MemoryCoreAwareWorker.new(
    root: root, lifecycle_service: lifecycle,
    core_status: -> { { "ok" => true, "data" => { "active_core_id" => "dev" } } },
    status_path: status_path, clock: clock
  )
  result = worker.run
  assert.call(result["ok"] && result["outcome"] == "cycle_complete", "eligible Core runs one cycle")
  assert.call(lifecycle.runs == ["a17-cycle-#{'a' * 32}"], "request identity is stable from work digest")
  assert.call(File.stat(status_path).mode & 0o077 == 0, "last-run status is owner-private")
  assert.call(worker.status == result && !JSON.generate(result).match?(/text|content.*Amber/i), "status is bounded and content-free")

  projection = FixtureLifecycle.new(cycle: {
    "ok" => true, "lifecycle_state" => "complete", "cycle_id" => "mprc_fixture",
    "cycle_sha256" => "c" * 64, "mode" => "projection_reconciliation",
    "decision_counts" => { "projection_generations_activated" => 1 },
    "rollback_references" => [], "idempotent" => false,
    "projection_reconciliation_required" => false,
    "generation_id" => "generation_1234567890abcdefabcd", "content_included" => false
  })
  projected = SoulCore::MemoryCoreAwareWorker.new(
    root: root, lifecycle_service: projection,
    core_status: -> { { "ok" => true, "data" => { "active_core_id" => "dev" } } },
    status_path: File.join(root, "projection.json"), clock: clock
  ).run
  assert.call(projected["mutation"] == "derived_projection_reconciled", "projection cycle reports derived mutation authority")
  assert.call(projected.dig("details", "generation_id") == "generation_1234567890abcdefabcd", "projection cycle retains generation evidence")

  empty = FixtureLifecycle.new(work_available: false)
  no_work = SoulCore::MemoryCoreAwareWorker.new(root: root, lifecycle_service: empty,
    core_status: -> { { "ok" => true, "data" => { "active_core_id" => "daily" } } },
    status_path: File.join(root, "empty.json"), clock: clock).run
  assert.call(no_work["outcome"] == "no_work" && empty.runs.empty?, "no work abstains before model lifecycle")

  %w[free music].each do |core|
    skipped = FixtureLifecycle.new
    result = SoulCore::MemoryCoreAwareWorker.new(root: root, lifecycle_service: skipped,
      core_status: -> { { "ok" => true, "data" => { "active_core_id" => core } } },
      status_path: File.join(root, "#{core}.json"), clock: clock).run
    assert.call(result["outcome"] == "skipped_core" && skipped.status_calls.zero? && skipped.runs.empty?, "#{core} skips without work inspection")
  end
end

Dir.mktmpdir("soul-memory-a17-deploy-") do |home|
  runner = FixtureRunner.new
  deployment = SoulCore::MemoryCoreAwareWorkerDeployment.new(
    root: File.expand_path("..", __dir__), home: home, ruby_path: RbConfig.ruby,
    systemctl_path: "/usr/bin/systemctl", runner: runner
  )
  plan = deployment.plan
  data = plan.fetch("data")
  assert.call(plan["lifecycle_state"] == "blocked_for_human_review" && data["expected_digest"].match?(/\A[0-9a-f]{64}\z/), "deployment requires reviewed digest")
  service = data.dig("units", SoulCore::MemoryCoreAwareWorkerDeployment::SERVICE)
  timer = data.dig("units", SoulCore::MemoryCoreAwareWorkerDeployment::TIMER)
  assert.call(service.include?("Type=oneshot") && service.include?("TimeoutStartSec=12min") && service.include?("NoNewPrivileges=true"), "service is bounded and hardened")
  assert.call(timer.include?("OnBootSec=10min") && timer.include?("OnUnitInactiveSec=15min") && timer.include?("Persistent=false"), "timer has reviewed non-catch-up cadence")
  assert.call(!deployment.install(confirmation: "wrong", expected_digest: data["expected_digest"])["ok"], "wrong install confirmation blocks")
  assert.call(!deployment.install(confirmation: SoulCore::MemoryCoreAwareWorkerDeployment::CONFIRM_INSTALL, expected_digest: "0" * 64)["ok"], "stale install digest blocks")
  installed = deployment.install(confirmation: SoulCore::MemoryCoreAwareWorkerDeployment::CONFIRM_INSTALL, expected_digest: data["expected_digest"])
  assert.call(installed["ok"] && installed.dig("data", "installed_exact"), "exact reviewed units install")
  assert.call(runner.commands.any? { |command| command.include?("enable") && command.include?("--now") }, "install enables only reviewed timer")
  assert.call(!deployment.uninstall(confirmation: "wrong")["ok"], "uninstall has separate exact gate")
  removed = deployment.uninstall(confirmation: SoulCore::MemoryCoreAwareWorkerDeployment::CONFIRM_UNINSTALL)
  assert.call(removed["ok"] && runner.commands.any? { |command| command.include?("disable") }, "exact removal disables timer")
end

worker_source = File.read(File.join(__dir__, "../lib/soul_core/memory_core_aware_worker.rb"))
assert.call(!worker_source.match?(/Thread|sleep|loop\s+do|Net::HTTP|TCPSocket|UDPSocket/), "worker adds no background loop or listener")
assert.call(worker_source.include?("a17-cycle-") && worker_source.include?("work_available"), "worker gates stable cycles on verified work")

puts "Memory Core-aware worker A17 verifier passed (#{checks} checks)."
