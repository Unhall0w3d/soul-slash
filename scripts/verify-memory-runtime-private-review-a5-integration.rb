#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/application_facade"

errors = []
check = lambda do |label, condition|
  puts "#{condition ? 'PASS' : 'FAIL'} #{label}"
  errors << label unless condition
end

fixture = Object.new
fixture.define_singleton_method(:runtime) do
  {
    "lifecycle_state" => "complete",
    "data" => {
      "selected_core" => { "id" => "daily", "label" => "Soul Core" },
      "embedding_profile" => { "name" => "fixture-embed", "dimensions" => 8 },
      "endpoint_reachability" => "reachable",
      "model_installed" => true,
      "model_loaded" => false,
      "compatibility_disposition" => "qualification_required",
      "mutation" => "none"
    }
  }
end
fixture.define_singleton_method(:private_review) do
  {
    "lifecycle_state" => "complete",
    "data" => {
      "case_file_digest" => "a" * 64,
      "approved_memory_source_digest" => "b" * 64,
      "case_count" => 1,
      "cases" => [{ "case_id" => "fixture", "query_sha256" => "c" * 64, "returned_memory_ids" => ["mem_fixture"] }],
      "aggregate" => { "recall" => 1.0, "reciprocal_rank" => 1.0, "forbidden_hit_count" => 0, "abstention_count" => 0 },
      "mutation" => "none"
    }
  }
end

request = lambda do |operation, parameters = {}|
  {
    "schema_version" => "soul.application.v1",
    "request_id" => "memory-a5-#{operation.tr('.', '-')}",
    "operation" => operation,
    "parameters" => parameters,
    "context" => { "interface" => "dashboard_test" }
  }
end

Dir.mktmpdir("soul-memory-a5-integration") do |root|
  facade = SoulCore::ApplicationFacade.new(root: root, memory_runtime_private_review_service: fixture)
  runtime = facade.call(request.call("memory.observatory.runtime"))
  review = facade.call(request.call("memory.observatory.private_review"))
  check.call("facade exposes runtime evidence", runtime["lifecycle_state"] == "complete" && runtime.dig("data", "model_installed") == true)
  check.call("facade exposes supervised private review", review["lifecycle_state"] == "complete" && review.dig("data", "case_count") == 1)
  check.call("facade preserves no-mutation authority", runtime.dig("meta", "mutation") == "none" && review.dig("meta", "mutation") == "none")

  rejected = facade.call(request.call("memory.observatory.runtime", "endpoint" => "http://example.invalid"))
  check.call("contract rejects runtime parameter injection", rejected["lifecycle_state"] == "failed")
end

dashboard = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
javascript = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
check.call("Dashboard exposes explicit runtime refresh", dashboard.include?('id="refresh-memory-observatory-runtime"') && javascript.include?('callSoul("memory.observatory.runtime")'))
check.call("Dashboard exposes explicit supervised review", dashboard.include?('id="run-memory-observatory-private-review"') && javascript.include?('callSoul("memory.observatory.private_review")'))
forbidden_input_ids = %w[
  memory-observatory-runtime-endpoint
  memory-observatory-runtime-model
  memory-observatory-private-review-path
  memory-observatory-private-review-json
]
check.call("Dashboard has no runtime or private-review configuration inputs", forbidden_input_ids.none? { |id| dashboard.include?("id=\"#{id}\"") })

abort "Memory runtime/private-review A5 integration verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory runtime/private-review A5 integration verification passed (#{7 - errors.length} checks)."
