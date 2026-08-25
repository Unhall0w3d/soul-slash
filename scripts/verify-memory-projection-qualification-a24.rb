#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/memory_projection_qualification_service"

RetrievalFixture = Struct.new(:outputs, :calls) do
  def query(query:, limit:)
    calls << [query, limit]
    JSON.parse(JSON.generate(outputs.fetch(query)))
  end
end

def envelope(results, projection: false)
  data = {"results" => results, "retrieval_mode" => projection ? "remote_projection_local_join" : "hybrid", "mutation" => "none"}
  if projection
    data.merge!(
      "projection_available" => true,
      "content_source" => "canonical_local_ledger",
      "authority" => "approved_memory_context",
      "projection_generation" => "generation_0123456789abcdef0123"
    )
  end
  {"lifecycle_state" => "complete", "schema" => ("soul.memory_projection_query.a23.v1" if projection), "data" => data, "mutation" => "none"}
end

def write_private(path, document)
  File.write(path, JSON.generate(document))
  File.chmod(0o600, path)
end

errors = []
checks = 0
check = lambda { |label, value| checks += 1; errors << label unless value }

Dir.mktmpdir("soul-a24") do |root|
  private_root = File.join(root, "private")
  FileUtils.mkdir_p(File.join(private_root, "projection"))
  path = File.join(private_root, "projection", "qualification-cases.json")
  document = {
    "schema_version" => "soul.memory_projection_qualification_cases.a24.v1",
    "cases" => [
      {"id" => "positive", "query" => "known operator preference", "expected_memory_ids" => ["mem_expected"], "forbidden_memory_ids" => ["mem_forbidden"], "result_limit" => 3},
      {"id" => "negative", "query" => "unknown purple recipe", "expected_memory_ids" => [], "forbidden_memory_ids" => ["mem_forbidden"], "result_limit" => 3}
    ]
  }
  write_private(path, document)
  local = RetrievalFixture.new({
    "known operator preference" => envelope([{"memory_id" => "mem_expected", "score" => 0.9}]),
    "unknown purple recipe" => envelope([])
  }, [])
  projection = RetrievalFixture.new({
    "known operator preference" => envelope([{"memory_id" => "mem_expected", "score" => 0.74}, {"memory_id" => "mem_forbidden", "score" => 0.52}], projection: true),
    "unknown purple recipe" => envelope([{"memory_id" => "mem_forbidden", "score" => 0.58}], projection: true)
  }, [])
  service = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local,
    projection_retrieval: projection, clock: -> { Time.utc(2026, 8, 25) }
  )
  result = service.qualify
  encoded = JSON.generate(result)
  check.call("qualification completes", result["lifecycle_state"] == "complete")
  check.call("positive and negative cases are counted", result.dig("data", "positive_case_count") == 1 && result.dig("data", "negative_case_count") == 1)
  check.call("local baseline is measured", result.dig("data", "local", "hit_count") == 1 && result.dig("data", "local", "correct_decision_count") == 2)
  check.call("precision and negative abstention are explicit", result.dig("data", "local", "mean_precision") == 1.0 && result.dig("data", "local", "negative_abstention_count") == 1)
  check.call("positive-only quality is separated from negative abstention", result.dig("data", "local", "mean_positive_precision") == 1.0 && result.dig("data", "local", "mean_positive_recall") == 1.0)
  check.call("threshold sweep is closed", result.dig("data", "thresholds") == SoulCore::MemoryProjectionQualificationService::THRESHOLDS && result.dig("data", "projection_thresholds").keys == %w[0.50 0.55 0.60 0.65 0.70 0.75 0.80])
  check.call("lower threshold exposes forbidden evidence", result.dig("data", "projection_thresholds", "0.50", "forbidden_hit_count") == 2)
  check.call("higher threshold filters weak distractors", result.dig("data", "projection_thresholds", "0.60", "forbidden_hit_count") == 0)
  check.call("excessive threshold loses expected result", result.dig("data", "projection_thresholds", "0.75", "hit_count") == 0)
  check.call("private query text is withheld", !encoded.include?("known operator preference") && !encoded.include?("unknown purple recipe"))
  check.call("query digests identify cases", result.dig("data", "cases").all? { |item| item.key?("query_sha256") && !item.key?("query") })
  check.call("no profile is selected", result.dig("data", "decision") == "human_review_required" && result.dig("data", "production_profile_changed") == false)
  check.call("Chat and Voice remain unchanged", result.dig("data", "chat_voice_routing_changed") == false)
  check.call("qualification cannot mutate", result["mutation"] == "none" && result.dig("data", "mutation") == "none")
  check.call("collaborators receive bounded cases", local.calls.length == 2 && projection.calls.length == 2 && (local.calls + projection.calls).all? { |_query, limit| limit == 3 })

  fallback_projection = RetrievalFixture.new(projection.outputs.transform_values do |output|
    output.merge("data" => output.fetch("data").merge("projection_available" => false, "retrieval_mode" => "hybrid"))
  end, [])
  failed = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local,
    projection_retrieval: fallback_projection
  ).qualify
  check.call("projection fallback cannot qualify", failed["lifecycle_state"] == "failed")

  null_results = RetrievalFixture.new({
    "known operator preference" => envelope(nil, projection: true),
    "unknown purple recipe" => envelope([], projection: true)
  }, [])
  failed = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local,
    projection_retrieval: null_results
  ).qualify
  check.call("null result arrays fail safely", failed["lifecycle_state"] == "failed")

  missing_score = RetrievalFixture.new({
    "known operator preference" => envelope([{"memory_id" => "mem_expected"}], projection: true),
    "unknown purple recipe" => envelope([], projection: true)
  }, [])
  failed = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local,
    projection_retrieval: missing_score
  ).qualify
  check.call("missing projection scores fail safely", failed["lifecycle_state"] == "failed")

  wrong_only = RetrievalFixture.new({
    "known operator preference" => envelope([{"memory_id" => "mem_forbidden", "score" => 0.9}]),
    "unknown purple recipe" => envelope([])
  }, [])
  wrong_result = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: wrong_only,
    projection_retrieval: projection
  ).qualify
  check.call("wrong-only positive results are incorrect", wrong_result.dig("data", "local", "correct_decision_count") == 1)

  wrong_schema = RetrievalFixture.new(projection.outputs.transform_values { |output| output.merge("schema" => "wrong") }, [])
  failed = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local,
    projection_retrieval: wrong_schema
  ).qualify
  check.call("wrong projection schema fails safely", failed["lifecycle_state"] == "failed")

  bad = JSON.parse(JSON.generate(document))
  bad["cases"] = [bad["cases"].first, bad["cases"].first.merge("id" => "second_positive")]
  write_private(path, bad)
  check.call("corpus without negative case fails", service.qualify["lifecycle_state"] == "failed")

  unapproved = JSON.parse(JSON.generate(document))
  unapproved["cases"].first["expected_memory_ids"] = ["mem_not_approved"]
  write_private(path, unapproved)
  check.call("corpus cannot reference non-approved memory", service.qualify["lifecycle_state"] == "failed")

  write_private(path, document)
  File.chmod(0o644, path)
  check.call("public-readable private corpus fails", service.qualify["lifecycle_state"] == "failed")
  File.chmod(0o600, path)

  outside = File.join(root, "outside.json")
  write_private(outside, document)
  escaped = SoulCore::MemoryProjectionQualificationService.new(case_path: outside, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local, projection_retrieval: projection).qualify
  check.call("case path cannot escape private root", escaped["lifecycle_state"] == "failed")

  link = File.join(private_root, "projection", "linked.json")
  File.symlink(outside, link)
  linked = SoulCore::MemoryProjectionQualificationService.new(case_path: link, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: local, projection_retrieval: projection).qualify
  check.call("symlink corpus fails safely", linked["lifecycle_state"] == "failed")

  slow = Object.new
  def slow.query(query:, limit:)
    sleep 2
    envelope = {"lifecycle_state" => "complete", "data" => {"results" => [], "retrieval_mode" => "hybrid", "mutation" => "none"}, "mutation" => "none"}
    envelope
  end
  timed = SoulCore::MemoryProjectionQualificationService.new(
    case_path: path, allowed_root: private_root, approved_memory_ids: %w[mem_expected mem_forbidden], local_retrieval: slow,
    projection_retrieval: projection, operation_timeout: 1
  ).qualify
  check.call("qualification has an overall deadline", timed["lifecycle_state"] == "failed")
end

source = File.read(File.join(__dir__, "../lib/soul_core/memory_projection_qualification_service.rb"))
check.call("service has no persistence or process execution", !source.match?(/File\.(?:write|rename|delete)|\b(?:system|exec|spawn|fork|popen)\s*\(/))
check.call("service has no background execution", !source.match?(/Thread\.new|setInterval|setTimeout|systemd|retry/))

abort "Memory projection qualification A24 failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection qualification A24 passed (#{checks} checks)."
