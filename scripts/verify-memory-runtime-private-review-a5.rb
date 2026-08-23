#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/memory_runtime_private_review_service"

include SoulCore

errors = []
check = lambda do |label, condition|
  errors << label unless condition
end

class PrivateReviewFixtureStore
  attr_reader :read_count

  def initialize(records)
    @records = records
    @read_count = 0
  end

  def records(status: nil, **_unused)
    @read_count += 1
    status ? @records.select { |record| record["status"] == status } : @records
  end
end

class PrivateReviewRetrievalFixture
  attr_reader :queries

  def initialize
    @queries = []
  end

  def query(query:, limit:)
    @queries << [query, limit]
    ids = query.include?("alpha") ? %w[mem_alpha mem_forbidden] : ["mem_beta"]
    {
      "lifecycle_state" => "complete",
      "data" => {
        "results" => ids.map { |id| { "memory_id" => id, "excerpt" => "fixture-only text" } }.first(limit),
        "ranking_profile" => "hybrid-a5-fixture",
        "index_available" => true,
        "mutation" => "none"
      }
    }
  end
end

def fixture_record(id, content, status: "approved")
  {
    "id" => id,
    "status" => status,
    "layer" => "project",
    "content" => content,
    "source" => { "kind" => "fixture", "reference" => id },
    "confidence" => 0.9,
    "approved_at" => "2026-08-23T12:00:00.000000Z"
  }
end

Dir.mktmpdir("soul-memory-private-review-a5") do |root|
  case_dir = File.join(root, "Soul", "private", "memory")
  FileUtils.mkdir_p(case_dir)
  case_path = File.join(case_dir, "retrieval_review_cases.json")
  cases = {
    "schema_version" => "soul.memory_retrieval.private_review.v1",
    "cases" => [
      { "id" => "case_alpha", "query" => "private alpha phrase", "expected_approved_memory_ids" => ["mem_alpha"], "forbidden_approved_memory_ids" => ["mem_forbidden"], "result_limit" => 2 },
      { "id" => "case_beta", "query" => "private beta phrase", "expected_approved_memory_ids" => ["mem_beta"], "result_limit" => 1 }
    ]
  }
  File.write(case_path, JSON.generate(cases))

  store = PrivateReviewFixtureStore.new([
    fixture_record("mem_alpha", "private alpha content"),
    fixture_record("mem_beta", "private beta content"),
    fixture_record("mem_forbidden", "private forbidden content"),
    fixture_record("mem_candidate", "candidate content", status: "candidate")
  ])
  retrieval = PrivateReviewRetrievalFixture.new
  requests = []
  http_get = lambda do |url|
    requests << url
    url.end_with?("/api/tags") ? { "models" => [{ "name" => "fixture-embed", "model" => "fixture-embed" }] } : { "models" => [{ "name" => "fixture-embed", "size_vram" => 123 }] }
  end

  service = MemoryRuntimePrivateReviewService.new(
    root: root,
    memory_store: store,
    retrieval_service: retrieval,
    embedding_endpoint: "http://127.0.0.1:11434/api/embed",
    embedding_profile: "fixture-embed",
    embedding_dimensions: 8,
    selected_core: "free",
    case_path: case_path,
    http_get: http_get
  )

  runtime = service.runtime
  check.call("runtime observation completes", runtime["lifecycle_state"] == "complete")
  check.call("runtime performs only bounded GET tags and ps", requests == ["http://127.0.0.1:11434/api/tags", "http://127.0.0.1:11434/api/ps"])
  check.call("runtime reports exact installed model", runtime.dig("data", "model_installed") == true)
  check.call("runtime reports exact loaded model", runtime.dig("data", "model_loaded") == true)
  check.call("Free Core is never compatible", runtime.dig("data", "compatibility_disposition") == "incompatible_free_core")
  check.call("runtime exposes configured dimensions", runtime.dig("data", "dimensions") == 8)

  service = MemoryRuntimePrivateReviewService.new(
    root: root,
    memory_store: store,
    retrieval_service: retrieval,
    embedding_endpoint: "http://127.0.0.1:11434/api/embed",
    embedding_profile: "fixture-embed",
    embedding_dimensions: 8,
    selected_core: "daily",
    case_path: case_path,
    http_get: http_get
  )
  daily_runtime = service.runtime
  check.call("qualified Core is not auto-approved", daily_runtime.dig("data", "compatibility_disposition") == "qualification_required")

  unloaded_free = MemoryRuntimePrivateReviewService.new(
    root: root, memory_store: store, retrieval_service: retrieval,
    embedding_endpoint: "http://127.0.0.1:11434/api/embed",
    embedding_profile: "fixture-embed", embedding_dimensions: 8,
    selected_core: "free", case_path: case_path,
    http_get: ->(url) { url.end_with?("/api/tags") ? { "models" => [{ "name" => "fixture-embed" }] } : { "models" => [] } }
  ).runtime
  check.call("unloaded Free Core is reported without a compatibility claim", unloaded_free.dig("data", "compatibility_disposition") == "free_core_unloaded")

  before_case = Digest::SHA256.file(case_path).hexdigest
  before_reads = store.read_count
  review = service.private_review
  review_json = JSON.generate(review)
  check.call("private review completes", review["lifecycle_state"] == "complete")
  check.call("private review evaluates all fixed cases", review.dig("data", "case_count") == 2 && review.dig("data", "cases").length == 2)
  check.call("private review computes recall", review.dig("data", "aggregate", "recall") == 1.0)
  check.call("private review computes reciprocal rank", review.dig("data", "aggregate", "reciprocal_rank") == 1.0)
  check.call("private review counts forbidden hit", review.dig("data", "aggregate", "forbidden_hit_count") == 1)
  check.call("private review records no abstentions", review.dig("data", "aggregate", "abstention_count") == 0)
  check.call("private review returns query digests only", !review_json.include?("private alpha phrase") && !review_json.include?("private beta phrase") && review.dig("data", "cases").all? { |item| item.key?("query_sha256") })
  check.call("private review returns no memory content", !review_json.include?("private alpha content") && !review_json.include?("private beta content"))
  check.call("private review does not write case file", Digest::SHA256.file(case_path).hexdigest == before_case)
  check.call("private review reads canonical store", store.read_count > before_reads)
  check.call("retrieval receives bounded fixture queries", retrieval.queries == [["private alpha phrase", 2], ["private beta phrase", 1]])

  remote = MemoryRuntimePrivateReviewService.new(root: root, memory_store: store, retrieval_service: retrieval, embedding_endpoint: "http://192.0.2.10:11434", embedding_profile: "fixture-embed", embedding_dimensions: 8, case_path: case_path, http_get: http_get)
  check.call("remote runtime endpoint fails safely", remote.runtime["lifecycle_state"] == "failed")

  symlink = File.join(root, "symlink-cases.json")
  File.symlink(case_path, symlink)
  unsafe = MemoryRuntimePrivateReviewService.new(root: root, memory_store: store, retrieval_service: retrieval, case_path: symlink)
  check.call("symlink case path fails safely", unsafe.private_review["lifecycle_state"] == "failed")

  invalid = JSON.parse(JSON.generate(cases))
  invalid["cases"] = 33.times.map { |index| cases["cases"].first.merge("id" => "case_#{index}") }
  File.write(case_path, JSON.generate(invalid))
  check.call("case count bound fails safely", service.private_review["lifecycle_state"] == "failed")

  unsupported = JSON.parse(JSON.generate(cases))
  unsupported["unexpected"] = true
  File.write(case_path, JSON.generate(unsupported))
  check.call("unknown document fields fail safely", service.private_review["lifecycle_state"] == "failed")

  unsupported_case = JSON.parse(JSON.generate(cases))
  unsupported_case["cases"].first["limit"] = 2
  File.write(case_path, JSON.generate(unsupported_case))
  check.call("unknown case fields fail safely", service.private_review["lifecycle_state"] == "failed")

  source = File.read(File.join(__dir__, "../lib/soul_core/memory_runtime_private_review_service.rb"))
  check.call("implementation has no process execution", !source.match?(/\b(system|exec|spawn|fork|popen)\s*\(/))
  check.call("implementation has no POST", !source.include?("Net::HTTP::Post"))
  check.call("implementation does not mutate Core", !source.match?(/CoreOrchestration|systemctl|load_model|unload_model/))
end

if errors.empty?
  puts "Memory runtime and private review A5 deterministic verification passed."
  exit 0
end

warn "Memory runtime and private review A5 verification failed: #{errors.join(', ')}"
exit 1
