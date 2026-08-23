#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/memory_observatory_service"
require_relative "../lib/soul_core/memory_retrieval_index"
require_relative "../lib/soul_core/memory_retrieval_service"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'} #{name}"
  errors << name unless condition
end

request = lambda do |operation, parameters = {}|
  {
    "schema_version" => "soul.application.v1",
    "request_id" => "memory-observatory-#{operation.tr('.', '-')}",
    "operation" => operation,
    "parameters" => parameters,
    "context" => { "interface" => "dashboard_test" }
  }
end

Dir.mktmpdir("soul-memory-observatory-a2") do |root|
  sequence = 0
  clock = -> { Time.utc(2026, 8, 23, 12, 0, 0) }
  store = SoulCore::ConversationMemoryStore.new(root: root, clock: clock, id_generator: -> { sequence += 1; format("fixture%02d", sequence) })
  first = store.propose(layer: "project", content: "The Operator prefers bounded memory retrieval.", source: { "kind" => "chat", "reference" => "fixture" }, confidence: 0.9)
  second = store.propose(layer: "project", content: "The Operator prefers bounded memory retrieval.", source: { "kind" => "chat", "reference" => "fixture" }, confidence: 0.8)
  replacement = store.propose(layer: "preference", content: "Memory diagnostics should explain why a record was recalled.", source: { "kind" => "review", "reference" => "fixture" }, confidence: 0.95)
  [first, second, replacement].each { |record| store.approve(record.fetch("id")) }
  store.supersede(first.fetch("id"), by: replacement.fetch("id"), reason: "reviewed fixture replacement")

  index = SoulCore::ApprovedMemoryIndexService.new(
    memory_store: store,
    index_path: File.join(root, "private", "approved-memory-index.json"),
    clock: clock
  )
  check.call("foreground lexical index rebuild completes", index.rebuild["lifecycle_state"] == "complete")
  retrieval = SoulCore::ApprovedMemoryRetrievalService.new(memory_store: store, index_service: index, clock: clock)
  observatory = SoulCore::MemoryObservatoryService.new(memory_store: store, index_service: index, retrieval_service: retrieval)
  facade = SoulCore::ApplicationFacade.new(root: root, clock: clock, memory_observatory_service: observatory)

  summary = facade.call(request.call("memory.observatory.summary"))
  check.call("facade exposes a complete read-only summary", summary["lifecycle_state"] == "complete" && summary.dig("meta", "mutation") == "none")
  check.call("summary counts canonical states", summary.dig("data", "counts", "states", "approved") == 2 && summary.dig("data", "counts", "states", "superseded") == 1)
  check.call("summary exposes bounded lifecycle evidence", summary.dig("data", "lifecycle_events").length <= 100)
  check.call("summary exposes exact duplicate observations", summary.dig("data", "duplicates").length == 0)
  check.call("summary exposes explicit supersession links", summary.dig("data", "supersessions", 0, "replacement_id") == replacement.fetch("id"))
  check.call("summary does not expose memory content in lifecycle evidence", summary.dig("data", "lifecycle_events").none? { |event| event.key?("content") })

  query = facade.call(request.call("memory.observatory.query", "query" => "explain recalled record", "limit" => 8))
  check.call("facade query returns approved-memory evidence", query["lifecycle_state"] == "complete" && query.dig("data", "results", 0, "memory_id") == replacement.fetch("id"))
  check.call("lexical-only index is labeled without a semantic claim", query.dig("data", "retrieval_mode") == "indexed_lexical")
  check.call("query reports explainable score components", query.dig("data", "results", 0, "score_components", "final").is_a?(Numeric))
  check.call("query cannot mutate memory", query.dig("meta", "mutation") == "none" && store.records(include_deleted: true).length == 3)
end

Dir.mktmpdir("soul-memory-observatory-read-only") do |root|
  store = SoulCore::ConversationMemoryStore.new(root: root, create: false)
  ledger_path = store.path
  index = SoulCore::ApprovedMemoryIndexService.new(memory_store: store, index_path: File.join(root, "private", "index.json"))
  observatory = SoulCore::MemoryObservatoryService.new(
    memory_store: store,
    index_service: index,
    retrieval_service: SoulCore::ApprovedMemoryRetrievalService.new(memory_store: store, index_service: index)
  )
  observatory.summary
  check.call("read-only summary does not create a missing ledger", !File.exist?(ledger_path))
end

abort "Memory Observatory facade verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory Observatory facade verification passed (#{12 - errors.length} checks)."
