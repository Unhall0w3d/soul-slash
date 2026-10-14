#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/model_runtime_lease_store"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/broker_session"

CL = SoulCore::ContinuityLab

checks = 0
errors = []
check = lambda do |name, condition|
  checks += 1
  puts "- #{name}: #{condition ? "ok" : "FAIL"}"
  errors << name unless condition
end
expect_error = lambda do |klass, &operation|
  operation.call
  false
rescue klass
  true
rescue StandardError
  false
end

with_lease_store = lambda do |&operation|
  Dir.mktmpdir("continuity-lab-admission-a2-") do |root|
    store = SoulCore::ModelRuntimeLeaseStore.new(root:)
    operation.call(store, root)
  end
end

now = 100.0
snapshot_for = lambda do |time = now, changes = {}|
  {
    "captured_at" => time,
    "core" => "amd-free",
    "profile_id" => "nvidia-fallback",
    "model_file" => "Qwen3-8B-Q4_K_M.gguf",
    "service_active" => true,
    "active_slots" => 0,
    "pending_transition" => false,
    "dedicated_window" => true
  }.merge(changes)
end

puts "Continuity Lab A2 admission and broker verification:"

with_lease_store.call do |store, _root|
  gate = CL::AdmissionGate.new(lease_store: store, snapshot_provider: -> { snapshot_for.call }, clock: -> { now })
  yielded = gate.with_window { "fixture-window" }
  check.call("fresh exact idle NVIDIA fallback observation admits and returns block result", yielded == "fixture-window")

  invalid_observations = [
    snapshot_for.call(97.99),
    snapshot_for.call(100.01),
    snapshot_for.call(100.0, "core" => "free"),
    snapshot_for.call(100.0, "profile_id" => "other"),
    snapshot_for.call(100.0, "model_file" => "other.gguf"),
    snapshot_for.call(100.0, "service_active" => false),
    snapshot_for.call(100.0, "active_slots" => 1),
    snapshot_for.call(100.0, "pending_transition" => true),
    snapshot_for.call(100.0, "dedicated_window" => false),
    snapshot_for.call(100.0, "unexpected" => true),
    snapshot_for.call(100.0, "active_slots" => "0"),
    snapshot_for.call(100.0, "captured_at" => "100")
  ]
  denied = invalid_observations.all? do |observation|
    candidate = CL::AdmissionGate.new(lease_store: store, snapshot_provider: -> { observation }, clock: -> { now })
    expect_error.call(CL::AdmissionDenied) { candidate.with_window { raise "must not admit" } }
  end
  check.call("stale, future, free-core, wrong-profile/model, busy, pending, and malformed observations deny", denied)

  selection_path = File.join(_root, SoulCore::ModelRuntimeLeaseStore::DEFAULT_DIRECTORY, "selected_profile.json")
  File.write(selection_path, JSON.generate("profile_id" => "nvidia-fallback") + "\n")
  selection_before = File.binread(selection_path)
  free_core = CL::AdmissionGate.new(lease_store: store, snapshot_provider: -> { snapshot_for.call(100.0, "core" => "free") }, clock: -> { now })
  check.call("free-core denial preserves the fixture's selected profile", expect_error.call(CL::AdmissionDenied) { free_core.with_window {} } && File.binread(selection_path) == selection_before)

  active_id = store.acquire(provider_id: "fixture", model_id: "fixture-model", request_id: "active", ttl_seconds: 60).fetch("lease_id")
  expired_id = store.acquire(provider_id: "fixture", model_id: "fixture-model", request_id: "expired", ttl_seconds: 60).fetch("lease_id")
  lease_dir = File.join(_root, SoulCore::ModelRuntimeLeaseStore::DEFAULT_DIRECTORY, "leases")
  expired_path = File.join(lease_dir, "#{expired_id}.json")
  expired_record = JSON.parse(File.read(expired_path))
  expired_record["expires_at"] = (Time.now - 60).iso8601
  File.write(expired_path, JSON.generate(expired_record) + "\n")
  lease_paths = [active_id, expired_id].map { |id| File.join(lease_dir, "#{id}.json") }
  before = lease_paths.to_h { |path| [path, File.binread(path)] }
  candidate = CL::AdmissionGate.new(lease_store: store, snapshot_provider: -> { snapshot_for.call }, clock: -> { now })
  denied_leases = expect_error.call(CL::AdmissionDenied) { candidate.with_window {} }
  check.call("active and retained expired lease records both deny admission without pruning", denied_leases && lease_paths.all? { |path| File.file?(path) && File.binread(path) == before.fetch(path) })
  store.release(active_id)
  expired_only = expect_error.call(CL::AdmissionDenied) { candidate.with_window {} }
  check.call("expired-only lease is refused and retained byte-for-byte", expired_only && File.binread(expired_path) == before.fetch(expired_path))
  store.release(expired_id)
end

with_lease_store.call do |store, _root|
  gate = CL::AdmissionGate.new(lease_store: store, snapshot_provider: -> { snapshot_for.call }, clock: -> { now })
  contention = false
  gate.with_window do
    contention = expect_error.call(SoulCore::ModelRuntimeLeaseStore::LockUnavailable) do
      store.acquire(provider_id: "fixture", model_id: "fixture-model", request_id: "contended")
    end
    :held
  end
  released = store.acquire(provider_id: "fixture", model_id: "fixture-model", request_id: "after-window")
  check.call("control lock excludes ordinary lease acquisition for the full window and releases after return", contention && released.is_a?(Hash))
  store.release(released.fetch("lease_id"))

  raised = expect_error.call(RuntimeError) { gate.with_window { raise "fixture exception" } }
  after_exception = store.acquire(provider_id: "fixture", model_id: "fixture-model", request_id: "after-exception")
  check.call("control lock releases when the admitted block raises", raised && after_exception.is_a?(Hash))
  store.release(after_exception.fetch("lease_id"))
end

scripted = ["synthetic answer 🌙", "second fixture response"]
session = CL::BrokerSession.new(responses: scripted)
response = session.dispatch("operation" => "generate", "call_index" => 0, "input" => "Synthetic question")
check.call("generate dispatch returns the scripted UTF-8 response", response == { "ok" => true, "response" => scripted.first })

counter = session.dispatch("operation" => "format_count", "input" => "café🌙")
check.call("format_count uses the deterministic fake UTF-8 byte counter", counter["ok"] && counter["count"] == ("café🌙".bytesize + 3) / 4 && counter["counter"] == "fake_utf8_bytes_div4_v1")

protocol_denials = [
  { "operation" => "http", "input" => "x" },
  { "operation" => "admin", "input" => "x" },
  { "operation" => "execute", "input" => "x" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "url" => "http://127.0.0.1:8082" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "path" => "/tmp/model" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "model" => "other" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "token" => "secret" },
  { "operation" => "generate", "call_index" => 0, "input" => "x", "extra" => true },
  { "operation" => "generate", "call_index" => 0, "input" => "x" * 12_289 },
  { "operation" => "format_count", "input" => "x" * 12_289 },
  { "operation" => "generate", "call_index" => 16, "input" => "x" },
  { "operation" => "generate", "call_index" => "0", "input" => "x" },
  { "operation" => "format_count", "input" => "x", "url" => "http://example.invalid" }
]
invalid_session = CL::BrokerSession.new(responses: ["unused"])
rejected = protocol_denials.all? do |request|
  expect_error.call(CL::ValidationError) { invalid_session.dispatch(request) }
end
check.call("broker rejects unapproved operations, URL/path/model/token fields, malformed types, and oversized input", rejected)

bounded = CL::BrokerSession.new(responses: Array.new(16, "fixture"))
generated = 16.times.all? do |index|
  bounded.dispatch("operation" => "generate", "call_index" => index, "input" => "x")["response"] == "fixture"
end
too_many_generate = expect_error.call(CL::ValidationError) do
  bounded.dispatch("operation" => "generate", "call_index" => 16, "input" => "x")
end
check.call("broker accepts at most sixteen increasing generation calls", generated && too_many_generate)

non_increasing = CL::BrokerSession.new(responses: ["first", "second"])
first_ok = non_increasing.dispatch("operation" => "generate", "call_index" => 0, "input" => "x")["ok"]
repeated_denied = expect_error.call(CL::ValidationError) do
  non_increasing.dispatch("operation" => "generate", "call_index" => 0, "input" => "x")
end
check.call("broker requires unique increasing generation indices", first_ok && repeated_denied)

total_bound = CL::BrokerSession.new(responses: Array.new(16, "fixture"))
32.times { total_bound.dispatch("operation" => "format_count", "input" => "x") }
total_denied = expect_error.call(CL::ValidationError) do
  total_bound.dispatch("operation" => "format_count", "input" => "x")
end
check.call("broker caps all operations at thirty-two calls", total_denied)

if session.calls.respond_to?(:length)
  check.call("calls exposes fake-backend call history", session.calls.length == 1)
else
  check.call("calls exposes fake-backend call count", session.calls == 1)
end

puts "#{checks - errors.length}/#{checks} checks passed"
exit(errors.empty? ? 0 : 1)
