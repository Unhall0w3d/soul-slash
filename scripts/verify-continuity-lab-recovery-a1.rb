#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"

Lab = SoulCore::ContinuityLab
checks = 0
check = lambda do |name, truth|
  raise "FAIL: #{name}" unless truth
  checks += 1
end
raises = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
config = Lab::Config.new("context_mode" => "explicit_v1")
wait = Lab.encode("action" => "wait")
tool = ->(name, args) { Lab.encode("action" => "tool", "tool" => name, "arguments" => args) }
run = lambda do |store, id, responses, content = "Synthetic task"|
  backend = Lab::FakeBackend.new(responses: responses)
  receipt = Lab::Runtime.new(store: store, backend: backend).submit(event_id: id, content: content)
  [receipt, backend]
end

# New tools use the same atomic transaction boundary as writes. Exercise each
# side of that boundary with a real close/open, not just an in-memory retry.
%w[search read note.tombstone].each do |name|
  %i[before_stage after_stage after_commit].each do |point|
    Dir.mktmpdir("continuity-a1-fault-") do |root|
      path = "#{root}/store"
      armed = false
      crash = Class.new(StandardError)
      fault = lambda do |at, record|
        next unless armed && at == point && record["kind"] == "action_result" && record.dig("payload", "event_id") == "query"
        armed = false
        raise crash
      end
      store = Lab::Store.create(path: path, config: config, corpus: [{ "id" => "manual", "content" => "amber beacon" }], fault: fault)
      run.call(store, "seed", [tool.call("note.write", { "note_id" => "note", "expected_revision" => 0, "content" => "old evidence" }), wait])
      lineage = store.integrity["lineage_id"]
      args = case name
             when "search" then { "lineage_id" => lineage, "collection" => "corpus", "query" => "amber", "limit" => 8 }
             when "read" then { "lineage_id" => lineage, "collection" => "corpus", "id" => "manual", "revision" => 1, "start" => 0, "length" => 20 }
             else { "note_id" => "note", "expected_revision" => 1 }
             end
      armed = true
      backend = Lab::FakeBackend.new(responses: [tool.call(name, args), wait])
      runtime = Lab::Runtime.new(store: store, backend: backend)
      check.call("#{name}/#{point} inject", raises.call(crash) { runtime.submit(event_id: "query", content: "Retrieve once") })
      before = store.snapshot
      check.call("#{name}/#{point} one backend call", backend.calls == 1)
      check.call("#{name}/#{point} boundary result", !!before.dig("events", "query", "calls", 0, "result") == (point == :after_commit))
      store.close
      store = Lab::Store.open(path: path, config: config)
      resumed_backend = Lab::FakeBackend.new(responses: ["not called", wait])
      receipt = Lab::Runtime.new(store: store, backend: resumed_backend).resume(event_id: "query")
      state = store.snapshot
      check.call("#{name}/#{point} complete no regenerated response", receipt["state"] == "complete" && resumed_backend.calls == 1)
      check.call("#{name}/#{point} single committed result", state["operations"].count { |op| op["event_id"] == "query" } == 1)
      check.call("#{name}/#{point} revision exactly once", state["notes"]["note"]["revision"] == (name == "note.tombstone" ? 2 : 1))
      check.call("#{name}/#{point} exact retrieved input", resumed_backend.inputs == [state.dig("events", "query", "calls", 1, "context", "formatted")])
      store.close
    end
  end
end

Dir.mktmpdir("continuity-a1-isolation-") do |root|
  path = "#{root}/store"
  store = Lab::Store.create(path: path, config: config, corpus: [{ "id" => "manual", "content" => "corpus_canary" }])
  run.call(store, "prior", [tool.call("note.write", { "note_id" => "note", "expected_revision" => 0, "content" => "notebook_canary" }), Lab.encode("action" => "reply", "content" => "history_canary")])
  store.close
  store = Lab::Store.open(path: path, config: config)
  _, backend = run.call(store, "fresh", [wait])
  check.call("restarted context excludes note/history/corpus unless requested", %w[notebook_canary history_canary corpus_canary].none? { |text| backend.inputs.join.include?(text) })
  id = store.integrity["lineage_id"]
  actions = [
    tool.call("search", { "lineage_id" => id, "collection" => "notes", "query" => "notebook_canary", "limit" => 8 }),
    tool.call("read", { "lineage_id" => id, "collection" => "notes", "id" => "note", "revision" => 1, "start" => 0, "length" => 100 }), wait
  ]
  receipt, backend = run.call(store, "recall", actions)
  check.call("restarted explicit retrieval makes retained note available", receipt["state"] == "complete" && backend.inputs.last.include?("notebook_canary"))
  check.call("no unrelated history or corpus piggybacks on retrieval", %w[history_canary corpus_canary].none? { |text| backend.inputs.join.include?(text) })
  original = store.snapshot.dig("events", "recall", "calls", 1, "result", "source")
  run.call(store, "delete", [tool.call("note.tombstone", { "note_id" => "note", "expected_revision" => 1 }), wait])
  check.call("tombstone does not erase historical result evidence", store.snapshot.dig("events", "recall", "calls", 1, "result", "source") == original)
  run.call(store, "restore", [tool.call("note.write", { "note_id" => "note", "expected_revision" => 2, "content" => "revised_canary" }), wait])
  check.call("explicit restore advances revision not resurrection of old revision", store.snapshot["notes"]["note"].values_at("revision", "tombstone", "content") == [3, false, "revised_canary"])
  store.close
end

Dir.mktmpdir("continuity-a1-boundaries-") do |root|
  corpus = [{ "id" => "unicode", "content" => "🌙 café Straße amber" }]
  store = Lab::Store.create(path: "#{root}/store", config: config, corpus: corpus)
  lineage = store.integrity["lineage_id"]
  run.call(store, "unicode", [tool.call("read", { "lineage_id" => lineage, "collection" => "corpus", "id" => "unicode", "revision" => 1, "start" => 2, "length" => 4 }), wait])
  source = store.snapshot.dig("events", "unicode", "calls", 0, "result", "source")
  check.call("UTF8 spans count characters rather than bytes", source["span"] == [2, 6] && source["text"] == "café")
  run.call(store, "budget-sample", [wait])
  sample = store.snapshot.dig("events", "budget-sample", "calls", 0, "context", "manifest")
  count = sample["input_tokens"]
  # Same fixed-length lineage ID and request ID make the fixture count exact.
  [0, -1].each do |offset|
    edge = Lab::Config.new("context_mode" => "explicit_v1", "context_tokens" => count + 2 + offset, "output_tokens" => 1, "context_margin" => 1)
    target = Lab::Store.create(path: "#{root}/edge-#{offset.abs}", config: edge)
    receipt, backend = run.call(target, "budget-sample", [wait])
    check.call("input exact budget edge #{offset}", offset.zero? ? receipt["state"] == "complete" && backend.calls == 1 : receipt["reason"] == "context_budget_exceeded" && backend.calls.zero?)
    target.close
  end
  store.close
end

Dir.mktmpdir("continuity-a1-protocol-") do |root|
  state = nil
  store = Lab::Store.create(path: "#{root}/store", config: config)
  lineage = store.integrity["lineage_id"]
  base = { "lineage_id" => lineage, "collection" => "notes", "id" => "safe", "revision" => 1, "start" => 0, "length" => 32 }
  invalid = [base.merge("collection" => "journal"), base.merge("id" => "../secret"), base.merge("id" => "/etc/passwd"),
             base.merge("revision" => "1"), base.merge("revision" => 0), base.merge("start" => -1), base.merge("length" => 1025),
             base.merge("lineage_id" => "../lineage"), base.merge("path" => "/tmp/secret")]
  invalid.each_with_index do |args, index|
    check.call("invalid read protocol #{index}", Lab::Actions.parse(tool.call("read", args), config).empty?)
  end
  store.synchronize { |current| state = JSON.parse(JSON.generate(current)) }
  # Ranking and output are regenerated from canonical state, never an index file.
  state["corpus"] = 8.times.map { |index| { "id" => "doc-#{index}", "content" => "amber " + "\u0001" * 8000 } }
  result = Lab::Retrieval.result(state, "search", { "lineage_id" => lineage, "collection" => "corpus", "query" => "amber", "limit" => 8 }, "none")
  check.call("escaped search output is bounded and omission explicit", Lab.encode(result).bytesize <= Lab::Retrieval::RESULT_BYTES && result["truncated"] && result["hits"].length < 8)
  check.call("search tie order is deterministic", result["hits"].map { |hit| hit["id"] } == result["hits"].map { |hit| hit["id"] }.sort)
  store.close
end

Dir.mktmpdir("continuity-a1-unicode-fold-") do |root|
  store = Lab::Store.create(path: "#{root}/store", config: config, corpus: [{ "id" => "sigma", "content" => "ς Straße" }])
  lineage = store.integrity["lineage_id"]
  run.call(store, "unicode-fold", [tool.call("search", { "lineage_id" => lineage, "collection" => "corpus", "query" => "Σ STRASSE", "limit" => 8 }), wait])
  result = store.snapshot.dig("events", "unicode-fold", "calls", 0, "result")
  check.call("Unicode full casefold matches final sigma and expanded sharp S", result["ok"] && result.dig("hits", 0, "id") == "sigma")
  store.close
end

%w[model_intent action_result].each do |kind|
  Dir.mktmpdir("continuity-a1-disk-forgery-") do |root|
    path = "#{root}/store"
    crash = Class.new(StandardError)
    fault = lambda do |point, record|
      raise crash if point == :after_commit && record["kind"] == kind
    end
    store = Lab::Store.create(path: path, config: config, fault: fault)
    lineage = store.integrity["lineage_id"]
    responses = [tool.call("search", { "lineage_id" => lineage, "collection" => "notes", "query" => "amber", "limit" => 8 }), wait]
    check.call("#{kind} captured committed boundary", raises.call(crash) { run.call(store, "forgery", responses) })
    store.close
    commit = Dir.glob("#{path}/commit-*.json").sort.last
    record = Lab.parse(File.read(commit))
    if kind == "model_intent"
      package = record["payload"]["context"]
      package["formatted"] += " injected context"
      package["manifest"]["formatted_digest"] = Digest::SHA256.hexdigest(package["formatted"])
      package["manifest"]["input_tokens"] = Lab::ContextBuilder.count(package["formatted"])
    else
      record["payload"]["result"]["hits"] = [{ "id" => "invented" }]
    end
    record["digest"] = Lab.digest(record.reject { |key, _| key == "digest" })
    File.write(commit, Lab.encode(record) + "\n")
    store = Lab::Store.open(path: path, config: config)
    check.call("#{kind} rejects rehashed forged committed record on replay", raises.call(Lab::IntegrityError) { store.snapshot })
    store.close
  end
end

Dir.mktmpdir("continuity-a1-corpus-quota-") do |root|
  small = Lab::Config.new("context_mode" => "explicit_v1", "max_journal_bytes" => 4096)
  path = "#{root}/store"
  check.call("oversize manifest rejected before creating store", raises.call(Lab::QuotaExceeded) do
    Lab::Store.create(path: path, config: small, corpus: [{ "id" => "large", "content" => "x" * 8192 }])
  end && !File.exist?(path))
end

Dir.mktmpdir("continuity-a1-essential-group-") do |root|
  store = Lab::Store.create(path: "#{root}/store", config: config)
  receipt, backend = run.call(store, "essential-group", [tool.call("note.write", { "note_id" => "large", "expected_revision" => 0, "content" => "x" * 4096 }), wait], "u" * 8192)
  check.call("oversize latest result group fails without silently dropping it", receipt["reason"] == "context_budget_exceeded" && backend.calls == 1)
  check.call("context failure preserves already committed effect", store.snapshot.dig("notes", "large", "revision") == 1)
  store.close
end

Dir.mktmpdir("continuity-a1-ambiguous-intent-") do |root|
  path = "#{root}/store"
  crash = Class.new(StandardError)
  fault = lambda do |point, record|
    raise crash if point == :after_commit && record["kind"] == "model_intent"
  end
  store = Lab::Store.create(path: path, config: config, fault: fault)
  check.call("explicit-context intent interruption", raises.call(crash) { run.call(store, "ambiguous", [wait]) })
  package = store.snapshot.dig("events", "ambiguous", "calls", 0, "context")
  store.close
  store = Lab::Store.open(path: path, config: config)
  backend = Lab::FakeBackend.new(responses: [wait])
  result = Lab::Runtime.new(store: store, backend: backend).resume(event_id: "ambiguous")
  check.call("context-bound ambiguous intent never regenerates model response", result["state"] == "blocked_for_human_review" && backend.calls.zero?)
  check.call("ambiguous context remains exact on reopen", store.snapshot.dig("events", "ambiguous", "calls", 0, "context") == package)
  store.close
  manifest = "#{path}/manifest.json"
  value = Lab.parse(File.read(manifest))
  value["schema"] = "soul.continuity_lab.a0"
  File.write(manifest, Lab.encode(value))
  check.call("old A0 schema is rejected rather than implicitly migrated", raises.call(Lab::IntegrityError) { Lab::Store.open(path: path, config: config) })
end

puts "PASS: #{checks} Continuity Lab A1 recovery/boundary checks (synthetic only)"
