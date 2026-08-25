#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/memory_retrieval_policy_store"
require_relative "../lib/soul_core/memory_retrieval_policy_service"

errors = []
checks = 0
check = lambda { |label, value| checks += 1; errors << label unless value }

Dir.mktmpdir("soul-a26") do |root|
  private_root = File.join(root, "private")
  FileUtils.mkdir_p(private_root, mode: 0o700)
  path = File.join(private_root, "retrieval", "active-policy.json")
  clock = -> { Time.utc(2026, 8, 25, 12, 0, 0) }
  store = SoulCore::MemoryRetrievalPolicyStore.new(private_root: private_root, path: path, clock: clock)
  service = SoulCore::MemoryRetrievalPolicyService.new(store: store)

  check.call("missing policy defaults locally", store.active["profile"] == "local_hybrid_a4")
  preview = service.preview(profile: "projection_gate_local_order_a25", reason: "A25 private corpus qualification")
  check.call("activation preview is non-mutating", preview["lifecycle_state"] == "complete" && preview["mutation"] == "none" && !File.exist?(path))
  blocked = service.execute(profile: "projection_gate_local_order_a25", reason: "A25 private corpus qualification", confirmation: "wrong", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong confirmation blocks", blocked["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(path))
  blocked = service.execute(profile: "projection_gate_local_order_a25", reason: "changed", confirmation: SoulCore::MemoryRetrievalPolicyService::ACTIVATE_CONFIRMATION, expected_digest: preview.dig("data", "expected_digest"))
  check.call("stale preview blocks", blocked["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(path))
  activated = service.execute(profile: "projection_gate_local_order_a25", reason: "A25 private corpus qualification", confirmation: SoulCore::MemoryRetrievalPolicyService::ACTIVATE_CONFIRMATION, expected_digest: preview.dig("data", "expected_digest"))
  check.call("reviewed policy activates", activated["lifecycle_state"] == "complete" && store.active["profile"] == "projection_gate_local_order_a25")
  check.call("threshold is fixed", store.active["projection_threshold"] == 0.65)
  check.call("policy file is owner private", (File.stat(path).mode & 0o077).zero?)
  check.call("audit is content free", activated.dig("data", "audit", 0, "reason_sha256").to_s.match?(/\A[0-9a-f]{64}\z/) && !File.read(path).include?("A25 private corpus"))
  check.call("prior local policy is retained", activated.dig("data", "previous", "profile") == "local_hybrid_a4")

  corrected = service.preview(profile: "projection_gate_local_order_a29", reason: "production-aligned A29 qualification")
  corrected_result = service.execute(profile: "projection_gate_local_order_a29", reason: "production-aligned A29 qualification", confirmation: SoulCore::MemoryRetrievalPolicyService::ACTIVATE_CONFIRMATION, expected_digest: corrected.dig("data", "expected_digest"))
  check.call("corrected A29 policy is distinct and fixed", corrected_result["lifecycle_state"] == "complete" && store.active == {"profile" => "projection_gate_local_order_a29", "projection_threshold" => 0.55})

  rollback = service.rollback_preview(reason: "restore local retrieval")
  restored = service.rollback_execute(reason: "restore local retrieval", confirmation: SoulCore::MemoryRetrievalPolicyService::ROLLBACK_CONFIRMATION, expected_digest: rollback.dig("data", "expected_digest"))
  check.call("rollback restores prior policy", restored["lifecycle_state"] == "complete" && store.active["profile"] == "projection_gate_local_order_a25")
  check.call("rollback is audited", restored.dig("data", "audit").length == 3 && restored.dig("data", "audit", -1, "action") == "rollback")

  File.chmod(0o644, path)
  check.call("broad policy permissions fall back locally", store.active["profile"] == "local_hybrid_a4" && store.active["fallback_reason"] == "policy_unavailable")
  File.chmod(0o600, path)
  outside = File.join(root, "outside.json")
  begin
    SoulCore::MemoryRetrievalPolicyStore.new(private_root: private_root, path: outside)
    escaped = false
  rescue ArgumentError
    escaped = true
  end
  check.call("policy path cannot escape private root", escaped)

  link_dir = File.join(private_root, "linked")
  File.symlink(root, link_dir)
  linked_store = SoulCore::MemoryRetrievalPolicyStore.new(private_root: private_root, path: File.join(link_dir, "policy.json"))
  check.call("symlink parent falls back locally", linked_store.active["profile"] == "local_hybrid_a4")
end

source = File.read(File.join(__dir__, "../lib/soul_core/memory_retrieval_policy_service.rb"))
check.call("control service has no background behavior", !source.match?(/Thread\.new|systemd|setInterval|setTimeout/))
store_source = File.read(File.join(__dir__, "../lib/soul_core/memory_retrieval_policy_store.rb"))
check.call("policy reads detect replacement races", store_source.include?("changed while being read") && store_source.include?("before.ino == after.ino"))
abort "Memory retrieval policy A26 failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory retrieval policy A26 passed (#{checks} checks)."
