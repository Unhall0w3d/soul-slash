#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/memory_fusion_retrieval_service"
require_relative "../lib/soul_core/memory_production_qualification_service"

FixtureRetrieval = Struct.new(:results, :available, :calls) do
  def query(query:, limit:)
    calls << [query, limit]
    selected = results.fetch(query, []).first(limit)
    {
      "lifecycle_state" => "complete", "schema" => SoulCore::MemoryFusionRetrievalService::SCHEMA, "mutation" => "none",
      "data" => {"results" => selected.map { |id| {"memory_id" => id} }, "retrieval_mode" => "projection_gate_local_order",
        "ranking_profile" => SoulCore::MemoryFusionRetrievalService::PROFILE, "projection_available" => available,
        "content_source" => "canonical_local_ledger", "authority" => "approved_memory_context", "mutation" => "none"}
    }
  end
end
FixturePolicy = Struct.new(:value) { def active = value }

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Dir.mktmpdir("soul-memory-a29-") do |root|
  private_root = File.join(root, "private")
  FileUtils.mkdir_p(File.join(private_root, "projection"), mode: 0o700)
  path = File.join(private_root, "projection", "qualification-cases.json")
  cases = {
    "schema_version" => "soul.memory_projection_qualification_cases.a24.v1",
    "cases" => [
      {"id" => "positive", "query" => "known fixture", "expected_memory_ids" => ["mem_expected"], "forbidden_memory_ids" => ["mem_forbidden"], "result_limit" => 3},
      {"id" => "negative", "query" => "unknown fixture", "expected_memory_ids" => [], "forbidden_memory_ids" => ["mem_forbidden"], "result_limit" => 3}
    ]
  }
  File.write(path, JSON.generate(cases))
  File.chmod(0o600, path)
  policy = FixturePolicy.new({"profile" => "projection_gate_local_order_a29", "projection_threshold" => 0.55})
  retrieval = FixtureRetrieval.new({"known fixture" => %w[mem_expected mem_other], "unknown fixture" => []}, true, [])
  service = SoulCore::MemoryProductionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_other mem_forbidden],
    retrieval: retrieval, policy_store: policy, clock: -> { Time.utc(2026, 8, 25) }
  )
  result = service.qualify
  assert.call(result["lifecycle_state"] == "complete" && result["mutation"] == "none", "production qualification completes without mutation")
  assert.call(result.dig("data", "positive_hit_count") == 1 && result.dig("data", "negative_abstention_count") == 1, "positive and negative decisions are measured")
  assert.call(result.dig("data", "forbidden_hit_count").zero?, "forbidden results are measured")
  assert.call(result.dig("data", "all_routes_used_active_policy") && result.dig("data", "projection_available_for_all_cases"), "active route identity is proven")
  assert.call(!JSON.generate(result).include?("known fixture") && result.dig("data", "content_included") == false, "receipt withholds query and memory content")
  assert.call(retrieval.calls.length == 2, "qualification is bounded by corpus")

  aliased_cases = JSON.parse(JSON.generate(cases))
  aliased_cases.fetch("cases").first["expected_memory_ids"] = ["mem_superseded"]
  File.write(path, JSON.generate(aliased_cases))
  File.chmod(0o600, path)
  aliased = SoulCore::MemoryProductionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_other mem_forbidden],
    retrieval: retrieval, policy_store: policy,
    memory_id_resolver: ->(id) { id == "mem_superseded" ? "mem_expected" : id }
  ).qualify
  assert.call(aliased["lifecycle_state"] == "complete" && aliased.dig("data", "positive_hit_count") == 1,
    "qualification follows canonical supersession aliases")
  File.write(path, JSON.generate(cases))
  File.chmod(0o600, path)

  local_policy = FixturePolicy.new({"profile" => "local_hybrid_a4", "projection_threshold" => nil})
  blocked = SoulCore::MemoryProductionQualificationService.new(case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_other mem_forbidden], retrieval: retrieval, policy_store: local_policy).qualify
  assert.call(blocked["lifecycle_state"] == "failed", "unqualified policy fails closed")

  unavailable = FixtureRetrieval.new(retrieval.results, false, [])
  blocked = SoulCore::MemoryProductionQualificationService.new(case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_other mem_forbidden], retrieval: unavailable, policy_store: policy).qualify
  assert.call(blocked["lifecycle_state"] == "failed", "projection fallback fails production qualification")

  link = File.join(private_root, "projection", "linked.json")
  File.symlink(path, link)
  blocked = SoulCore::MemoryProductionQualificationService.new(case_path: link, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_other mem_forbidden], retrieval: retrieval, policy_store: policy).qualify
  assert.call(blocked["lifecycle_state"] == "failed", "symlinked corpus fails closed")
end

source = File.read(File.join(__dir__, "../lib/soul_core/memory_production_qualification_service.rb"))
assert.call(!source.match?(/Thread\.new|systemd|setInterval|setTimeout|File\.(?:write|rename|delete)/), "qualification adds no persistence or background behavior")

cli_source = File.read(File.join(__dir__, "soul-memory-production-qualify"))
assert.call(cli_source.include?("SoulCore::ApplicationFacade.new") && cli_source.include?('"memory.observatory.query"'), "live qualification traverses the public production facade route")
assert.call(cli_source.include?("memory supersession cycle detected") && cli_source.include?("64.times"), "live qualification resolves bounded canonical supersession chains")

puts "Memory production qualification A29 passed (#{checks} checks)."
