#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"

CL = SoulCore::ContinuityLab

errors = []
checks = 0
check = lambda do |name, condition|
  checks += 1
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end

expect_error = lambda do |klass, &operation|
  begin
    operation.call
  rescue klass
    true
  rescue StandardError
    false
  else
    false
  end
end

response = ->(value) { JSON.generate(value) }
tool = lambda do |name, arguments|
  response.call("action" => "tool", "tool" => name, "arguments" => arguments)
end
wait = response.call("action" => "wait")

with_store = lambda do |config: CL::Config.new("context_mode" => "explicit_v1"), corpus: [], &operation|
  Dir.mktmpdir("continuity-lab-context-a1-") do |root|
    store = CL::Store.create(config:, path: File.join(root, "store"), corpus:)
    begin
      operation.call(store, root)
    ensure
      store.close
    end
  end
end

lineage = ->(store) { store.integrity.fetch("lineage_id") }
context_for = lambda do |store, event_id|
  CL::ContextBuilder.build(state: store.snapshot, event_id:, config: store.config)
end

puts "Continuity Lab A1 context verification:"

explicit = CL::Config.new("context_mode" => "explicit_v1")
check.call("explicit context mode is selected and names a deterministic byte counter",
           explicit["context_mode"] == "explicit_v1" && explicit["context_tokens"] == 4096 &&
             CL::ContextBuilder::COUNTER == "fake_utf8_bytes_div4_v1" && CL::ContextBuilder.count("12345") == 2)
check.call("context budget bounds and reserved output plus margin are enforced",
           expect_error.call(CL::ValidationError) { CL::Config.new("context_mode" => "explicit_v1", "context_tokens" => 127) } &&
             expect_error.call(CL::ValidationError) { CL::Config.new("context_mode" => "explicit_v1", "context_tokens" => 4097) } &&
             expect_error.call(CL::ValidationError) do
               CL::Config.new("context_mode" => "explicit_v1", "context_tokens" => 128,
                              "output_tokens" => 64, "context_margin" => 64)
             end)
check.call("raw fixture mode remains available for A0",
           CL::Config.new["context_mode"] == "raw_fixture")

Dir.mktmpdir("continuity-lab-corpus-input-a1-") do |root|
  path = File.join(root, "invalid-store")
  invalid = [
    [{ "id" => "manual", "content" => "Synthetic", "path" => "/tmp/never-read" }],
    [{ "id" => "duplicate", "content" => "one" }, { "id" => "duplicate", "content" => "two" }],
    [{ "id" => "invalid-utf8", "content" => "bad\xff".b }]
  ]
  rejected = invalid.all? do |corpus|
    expect_error.call(CL::ValidationError) { CL::Store.create(path:, config: explicit, corpus:) } && !File.exist?(path)
  end
  check.call("corpus accepts only unique explicit UTF-8 id/content documents without reading paths", rejected)
end

Dir.mktmpdir("continuity-lab-raw-fixture-a1-") do |root|
  raw = CL::Store.create(path: File.join(root, "store"))
  backend = CL::FakeBackend.new(responses: [
    tool.call("search", { "lineage_id" => raw.integrity.fetch("lineage_id"), "collection" => "notes", "query" => "synthetic", "limit" => 8 }),
    wait
  ])
  receipt = CL::Runtime.new(store: raw, backend:).submit(event_id: "raw-denies-search", content: "Search is not enabled here.")
  result = raw.snapshot.dig("events", "raw-denies-search", "calls", 0, "result")
  check.call("raw fixture mode denies retrieval tools",
             receipt["state"] == "complete" && result["reason"] == "invalid_action" && backend.calls == 2)
  raw.close
end

with_store.call do |store, root|
  id = lineage.call(store)
  check.call("fresh A1 store exposes a stable lineage and isolated synthetic corpus",
             id.match?(/\A[a-f0-9]{32}\z/) && store.snapshot["corpus"] == [] && store.integrity["ok"] &&
               store.snapshot["corpus_digest"].is_a?(String))
  reopened = CL::Store.open(path: File.join(root, "store"), config: store.config)
  check.call("corpus manifest and lineage survive reopen",
             reopened.integrity["lineage_id"] == id && reopened.integrity["ok"])
  reopened.close
end

with_store.call(corpus: [
  { "id" => "manual", "content" => "Synthetic field manual: amber beacon near north ridge." },
  { "id" => "amber-only", "content" => "Synthetic amber marker by the river." }
]) do |store, _root|
  id = lineage.call(store)
  backend = CL::FakeBackend.new(responses: [
    tool.call("search", { "lineage_id" => id, "collection" => "corpus", "query" => "amber beacon", "limit" => 8 }),
    tool.call("read", { "lineage_id" => id, "collection" => "corpus", "id" => "manual", "revision" => 1, "start" => 0, "length" => 23 }),
    wait
  ])
  CL::Runtime.new(store:, backend:).submit(event_id: "corpus-read", content: "Find the amber beacon in the field manual.")
  calls = store.snapshot.dig("events", "corpus-read", "calls")
  search = calls.fetch(0).fetch("result")
  source = search.fetch("hits").fetch(0)
  read = calls.fetch(1).fetch("result").fetch("source")
  check.call("search uses AND terms and returns explicit corpus provenance, digest and character span",
             search["ok"] && search.fetch("hits").length == 1 &&
               source.values_at("collection", "id", "revision") == ["corpus", "manual", 1] &&
               source["lineage_id"] == id &&
               source["content_digest"].match?(/\A[a-f0-9]{64}\z/) && source["provenance"] &&
               source["span"].is_a?(Array) && source["span"].length == 2 &&
               source["span"][1] - source["span"][0] == source["text"].length && source["text"].length <= 160)
  check.call("read returns the requested synthetic source slice and exact span",
             read["collection"] == "corpus" && read["id"] == "manual" && read["revision"] == 1 &&
               read["span"] == [0, 23] && read["text"] == "Synthetic field manual:")
  check.call("fake backend receives exactly the persisted formatted context strings",
             backend.inputs == calls.map { |call| call.dig("context", "formatted") })
  check.call("retrieval result stays within its encoded byte bound",
             CL.encode(search).bytesize <= CL::Retrieval::RESULT_BYTES)
  reopened = CL::Store.open(path: File.join(_root, "store"), config: store.config)
  replayed = context_for.call(reopened, "corpus-read")
  check.call("restart replay recomputes the same persisted context package",
             replayed == context_for.call(store, "corpus-read") &&
               reopened.snapshot.dig("events", "corpus-read", "calls", 2, "context") == replayed)
  reopened.close
end

with_store.call do |store, _root|
  id = lineage.call(store)
  backend = CL::FakeBackend.new(responses: [
    tool.call("note.write", { "note_id" => "fixture-note", "expected_revision" => 0, "content" => "Synthetic amber beacon at north ridge." }),
    tool.call("note.write", { "note_id" => "fixture-note", "expected_revision" => 1, "content" => "Synthetic amber beacon at north ridge, revised." }),
    tool.call("read", { "lineage_id" => id, "collection" => "notes", "id" => "fixture-note", "revision" => 1, "start" => 0, "length" => 32 }),
    tool.call("search", { "lineage_id" => id, "collection" => "notes", "query" => "amber beacon", "limit" => 8 }),
    tool.call("note.tombstone", { "note_id" => "fixture-note", "expected_revision" => 2 }),
    tool.call("search", { "lineage_id" => id, "collection" => "notes", "query" => "amber beacon", "limit" => 8 }),
    wait
  ])
  CL::Runtime.new(store:, backend:).submit(event_id: "note-revision", content: "Create and retrieve a synthetic note.")
  calls = store.snapshot.dig("events", "note-revision", "calls")
  stale_read = calls.fetch(2).fetch("result")
  found = calls.fetch(3).fetch("result")
  tombstone = calls.fetch(4).fetch("result")
  absent = calls.fetch(5).fetch("result")
  note = store.snapshot.fetch("notes").fetch("fixture-note")
  check.call("search uses AND terms and returns current note revision with provenance",
             found["ok"] && found.fetch("hits").length == 1 && found.dig("hits", 0, "revision") == 2 &&
               found.dig("hits", 0, "provenance") && note["revision"] == 3)
  check.call("stale revision read fails rather than falling back to current content",
             stale_read["ok"] == false && stale_read["reason"] == "revision_conflict")
  check.call("tombstone advances revision and removes note from retrieval eligibility",
             tombstone["ok"] && note["tombstone"] == true && absent["ok"] && absent.fetch("hits").empty?)
end

with_store.call do |store, root|
  foreign = CL::Store.create(path: File.join(root, "foreign"),
                             config: store.config)
  begin
    backend = CL::FakeBackend.new(responses: [
      tool.call("search", { "lineage_id" => lineage.call(foreign), "collection" => "notes", "query" => "synthetic", "limit" => 8 }),
      tool.call("search", { "lineage_id" => lineage.call(store), "collection" => "notes", "query" => "synthetic", "limit" => 8, "path" => "/tmp/not-read" }),
      wait
    ])
    CL::Runtime.new(store:, backend:).submit(event_id: "denied-access", content: "Attempt cross-lineage and path access.")
    results = store.snapshot.dig("events", "denied-access", "calls").map { |call| call.fetch("result") }
    check.call("cross-lineage retrieval is denied with a structured failure",
               results[0]["ok"] == false && results[0]["reason"])
    check.call("search rejects path-bearing arguments without fetching a path",
               results[1]["ok"] == false && results[1]["reason"] && foreign.snapshot.fetch("notes").empty?)
  ensure
    foreign.close
  end
end

with_store.call(corpus: [{ "id" => "manual", "content" => "Synthetic catalog text." }]) do |store, _root|
  id = lineage.call(store)
  backend = CL::FakeBackend.new(responses: [wait])
  CL::Runtime.new(store:, backend:).submit(event_id: "no-implicit", content: "Answer only from the request.")
  state = store.snapshot
  package = context_for.call(store, "no-implicit")
  manifest = package.fetch("manifest")
  formatted = package.fetch("formatted")
  check.call("corpus is absent from context until an explicit retrieval result cites it",
             !formatted.include?("Synthetic catalog text") &&
               manifest.fetch("sources").none? { |source| source["collection"] == "corpus" })
  check.call("context packages bind lineage, config, corpus and formatter hashes",
             manifest["lineage_id"] == id && manifest["counter"] == "fake_utf8_bytes_div4_v1" &&
               manifest["config_digest"] == store.config.digest &&
               manifest["corpus_digest"].is_a?(String) && manifest["formatter_digest"].is_a?(String) &&
               manifest["formatted_digest"] == Digest::SHA256.hexdigest(formatted))
  check.call("context manifest records bounded input, reserve, margin and group decisions",
             manifest["total_tokens"] == store.config["context_tokens"] &&
               manifest["input_tokens"].is_a?(Integer) && manifest["input_tokens"] <= manifest["total_tokens"] &&
               manifest["output_reserve"] == store.config["output_tokens"] &&
               manifest["margin"] == store.config["context_margin"] &&
               manifest["included_groups"].is_a?(Array) && manifest["omitted_groups"].is_a?(Array))
  check.call("context input is reproducible from event state",
             package == context_for.call(store, "no-implicit") && package["formatted"] == state.dig("events", "no-implicit", "calls", 0, "context", "formatted"))
end

with_store.call do |store, _root|
  backend_for = ->(answer) { CL::FakeBackend.new(responses: [response.call("action" => "reply", "content" => answer)]) }
  CL::Runtime.new(store:, backend: backend_for.call("Only observed synthetic dialogue.")).submit(
    event_id: "eligible-history", content: "synthetic shared phrase")
  CL::Runtime.new(store:, backend: CL::FakeBackend.new(responses: [wait])).submit(
    event_id: "ineligible-wait", content: "synthetic wait phrase")
  id = lineage.call(store)
  backend = CL::FakeBackend.new(responses: [
    tool.call("search", { "lineage_id" => id, "collection" => "history", "query" => "synthetic shared", "limit" => 8 }),
    tool.call("search", { "lineage_id" => id, "collection" => "history", "query" => "synthetic wait", "limit" => 8 }),
    tool.call("search", { "lineage_id" => id, "collection" => "history", "query" => "current unique", "limit" => 8 }),
    wait
  ])
  CL::Runtime.new(store:, backend:).submit(event_id: "history-query", content: "current unique phrase")
  calls = store.snapshot.dig("events", "history-query", "calls")
  eligible = calls.fetch(0).fetch("result")
  waiting = calls.fetch(1).fetch("result")
  current = calls.fetch(2).fetch("result")
  check.call("history retrieval includes only completed reply exchanges with observed provenance",
             eligible["ok"] && eligible.dig("hits", 0, "id") == "eligible-history" &&
               eligible.dig("hits", 0, "provenance") == "observed_exchange_not_verified_fact")
  check.call("history retrieval excludes wait events and the current event",
             waiting["ok"] && waiting["hits"].empty? && current["ok"] && current["hits"].empty?)
end

with_store.call(config: CL::Config.new("context_mode" => "explicit_v1", "context_tokens" => 128,
                                      "output_tokens" => 32, "context_margin" => 8)) do |store, _root|
  backend = CL::FakeBackend.new(responses: [wait])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "essential-overflow", content: "x" * 1024)
  check.call("essential request overflow fails without invoking fake backend",
             receipt["state"] == "failed" && receipt["reason"] == "context_budget_exceeded" && backend.inputs.empty?)
end

rollover_corpus = 8.times.map do |index|
  { "id" => "rollover-#{index}", "content" => ("rolloverterm " * 40) + "synthetic document #{index}" }
end
with_store.call(corpus: rollover_corpus) do |store, _root|
  id = lineage.call(store)
  search = tool.call("search", { "lineage_id" => id, "collection" => "corpus", "query" => "rolloverterm", "limit" => 8 })
  backend = CL::FakeBackend.new(responses: Array.new(5, search) + [wait])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "group-rollover", content: "Exercise whole-group rollover.")
  call_context = store.snapshot.dig("events", "group-rollover", "calls", 5, "context")
  manifest = call_context.fetch("manifest")
  included = manifest.fetch("included_groups")
  omitted = manifest.fetch("omitted_groups")
  check.call("rollover keeps the newest complete result group and drops older groups oldest-first",
             receipt["state"] == "complete" && included.last == 4 &&
               omitted.map { |entry| entry["call_index"] } == omitted.map { |entry| entry["call_index"] }.sort &&
               omitted.any? && omitted.first["call_index"] == 0 && omitted.all? { |entry| entry["reason"] == "input_budget" })
  check.call("rollover manifest accounts for every prior result group exactly once",
             (included + omitted.map { |entry| entry["call_index"] }).sort == (0..4).to_a &&
               manifest.fetch("input_tokens") <= store.config["context_tokens"] - store.config["output_tokens"] - store.config["context_margin"])
  check.call("fake backend receives the same rolled input that the journal persists",
             backend.inputs.fetch(5) == call_context.fetch("formatted"))
end

with_store.call do |store, _root|
  id = lineage.call(store)
  backend = CL::FakeBackend.new(responses: [
    tool.call("search", { "lineage_id" => id, "collection" => "notes", "query" => "missing term", "limit" => 8 }),
    wait
  ])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "empty-search", content: "A missing term should yield no sources.")
  result = store.snapshot.dig("events", "empty-search", "calls", 0, "result")
  check.call("optional no-note search is a bounded empty result with no injected memory",
             receipt["state"] == "complete" && result["ok"] && result["hits"].empty? && backend.inputs.length == 2)
end

with_store.call do |store, _root|
  accepted = { "event_id" => "forged-context", "content" => "Synthetic request.",
               "content_digest" => Digest::SHA256.hexdigest("Synthetic request.") }
  forged_rejected = store.synchronize do |state|
    store.append("accepted", accepted)
    canonical = CL::ContextBuilder.build(state:, event_id: "forged-context", config: store.config)
    forged = canonical.merge("formatted" => canonical.fetch("formatted") + " unbound text")
    expect_error.call(CL::IntegrityError) do
      store.append("model_intent", { "event_id" => "forged-context", "call_index" => 0, "context" => forged })
    end
  end
  check.call("journal rejects a forged formatted context before model intent commits",
             forged_rejected && store.integrity.fetch("transaction_count") == 1)
end

with_store.call do |store, _root|
  id = lineage.call(store)
  raw = tool.call("search", { "lineage_id" => id, "collection" => "notes", "query" => "synthetic", "limit" => 8 })
  forged_rejected = store.synchronize do |state|
    store.append("accepted", { "event_id" => "forged-result", "content" => "Synthetic request.",
                                "content_digest" => Digest::SHA256.hexdigest("Synthetic request.") })
    package = CL::ContextBuilder.build(state:, event_id: "forged-result", config: store.config)
    store.append("model_intent", { "event_id" => "forged-result", "call_index" => 0, "context" => package })
    store.append("model_response", { "event_id" => "forged-result", "call_index" => 0, "response" => raw })
    forged = { "event_id" => "forged-result", "call_index" => 0,
               "operation_id" => CL.digest({ "event_id" => "forged-result", "call_index" => 0 }),
               "invalid" => false, "tool_attempt" => true,
               "result" => { "ok" => true, "hits" => [{ "id" => "invented" }], "truncated" => false } }
    expect_error.call(CL::IntegrityError) { store.append("action_result", forged) }
  end
  check.call("journal replay validation rejects a forged retrieval result",
             forged_rejected && store.integrity.fetch("transaction_count") == 3 &&
               store.snapshot.dig("events", "forged-result", "calls", 0, "result").nil?)
end

puts "#{checks - errors.length}/#{checks} checks passed"
exit(errors.empty? ? 0 : 1)
