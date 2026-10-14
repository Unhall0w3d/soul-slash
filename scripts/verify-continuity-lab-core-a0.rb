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

with_store = lambda do |config = CL::Config.new, fault: nil, &operation|
  Dir.mktmpdir("continuity-lab-core-a0-") do |root|
    store = CL::Store.create(path: File.join(root, "store"), config:, fault:)
    begin
      operation.call(store, root)
    ensure
      store.close
    end
  end
end

response = ->(value) { JSON.generate(value) }
tool = lambda do |note_id:, revision:, content:|
  { "action" => "tool", "tool" => "note.write",
    "arguments" => { "note_id" => note_id, "expected_revision" => revision, "content" => content } }
end

puts "Continuity Lab A0 core verification:"

defaults = CL::Config.new
check.call("defaults select fake backend and disable optional capabilities",
           defaults.to_h["backend"] == "fake" && %w[autonomy browser code_execution training fallback].all? { |key| defaults.to_h[key] == false })
check.call("unknown configuration keys are rejected",
           expect_error.call(CL::ValidationError) { CL::Config.new("unknown" => true) })
check.call("configuration requires exact boolean types",
           expect_error.call(CL::ValidationError) { CL::Config.new("browser" => 0) })
check.call("non-fake backends are rejected",
           expect_error.call(CL::ValidationError) { CL::Config.new("backend" => "remote") })
check.call("configuration bounds are enforced",
           expect_error.call(CL::ValidationError) { CL::Config.new("max_model_calls" => 17) } &&
             expect_error.call(CL::ValidationError) { CL::Config.new("max_tool_calls" => "8") } &&
             expect_error.call(CL::ValidationError) { CL::Config.new("max_journal_bytes" => 4095) } &&
             expect_error.call(CL::ValidationError) { CL::Config.new("max_seconds" => 61) })

with_store.call do |store, root|
  reopened = CL::Store.open(path: File.join(root, "store"), config: defaults)
  check.call("fresh store reopens with matching manifest and empty state",
             reopened.snapshot["transaction_count"] == 0 && reopened.integrity.is_a?(Hash))
  reopened.close
  drifted = CL::Config.new("max_model_calls" => 8)
  check.call("manifest configuration drift is rejected",
             expect_error.call(CL::IntegrityError) { CL::Store.open(path: File.join(root, "store"), config: drifted) })
end

with_store.call do |store, _root|
  runtime = CL::Runtime.new(store:, backend: CL::FakeBackend.new(responses: [response.call("action" => "wait")]))
  receipt = runtime.submit(event_id: "wait-1", content: "Synthetic wait")
  snapshot = store.snapshot
  check.call("wait completes without creating a note",
             receipt["event_id"] == "wait-1" && !snapshot.fetch("notes").any? && snapshot.fetch("events").key?("wait-1"))
end

with_store.call do |store, _root|
  backend = CL::FakeBackend.new(responses: [response.call("action" => "reply", "content" => "Synthetic reply")])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "reply-1", content: "Synthetic prompt")
  check.call("reply is returned and receipts expose no unrelated notes",
             receipt["event_id"] == "reply-1" && receipt["reply"] == "Synthetic reply" && !receipt.key?("notes"))
end

with_store.call do |store, _root|
  backend = CL::FakeBackend.new(responses: [
    response.call(tool.call(note_id: "alpha", revision: 0, content: "first synthetic note")),
    response.call(tool.call(note_id: "alpha", revision: 1, content: "revised synthetic note")),
    response.call("action" => "reply", "content" => "updated")
  ])
  runtime = CL::Runtime.new(store:, backend:)
  receipt = runtime.submit(event_id: "note-revisions", content: "Create and revise a note")
  snapshot = store.snapshot
  note = snapshot.fetch("notes").fetch("alpha")
  operations = snapshot.fetch("operations")
  check.call("note revisions retain ancestry and actual tool results",
             note["revision"] == 2 && note["ancestry"] == [1] && note["content"] == "revised synthetic note" &&
               operations.is_a?(Array) && operations.length == 2 && operations.all? { |operation| operation.dig("result", "ok") } &&
               snapshot.fetch("transaction_count") >= 6 &&
               !JSON.generate(receipt).include?("revised synthetic note"))
end

with_store.call do |store, _root|
  backend = CL::FakeBackend.new(responses: [
    response.call("action" => "tool", "tool" => "note.search", "arguments" => {}),
    response.call("action" => "wait")
  ])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "allowlist-1", content: "Try a forbidden tool")
  check.call("non-allowlisted tool is rejected and bounded retry can complete",
             receipt["event_id"] == "allowlist-1" && store.snapshot.fetch("notes").empty? && backend.calls == 2)
end

with_store.call(CL::Config.new("max_invalid_actions" => 1)) do |store, _root|
  backend = CL::FakeBackend.new(responses: [
    response.call("action" => "wait", "unexpected" => true),
    "{\"action\":\"wait\""
  ])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "invalid-1", content: "Malformed model output")
  check.call("extra fields and partial JSON consume invalid-action budget",
             receipt["state"] == "failed" && backend.calls == 2 && store.snapshot.fetch("notes").empty?)
end

with_store.call(CL::Config.new("max_model_calls" => 1)) do |store, _root|
  backend = CL::FakeBackend.new(responses: [response.call(tool.call(note_id: "budget", revision: 0, content: "must not commit"))])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "budget-1", content: "Exhaust model budget")
  check.call("model-call budget exhaustion fails after the configured call limit",
             receipt["state"] == "failed" && backend.calls == 1)
end

with_store.call do |store, _root|
  backend = CL::FakeBackend.new(responses: [response.call(tool.call(note_id: "locked", revision: 7, content: "wrong revision"))])
  receipt = CL::Runtime.new(store:, backend:).submit(event_id: "revision-1", content: "Conflicting revision")
  check.call("expected-revision conflict produces no note effect",
             receipt["state"] == "failed" && store.snapshot.fetch("notes").empty?)
end

with_store.call do |store, _root|
  backend = CL::FakeBackend.new(responses: [response.call("action" => "reply", "content" => "same")])
  runtime = CL::Runtime.new(store:, backend:)
  first = runtime.submit(event_id: "dedup-1", content: "same content")
  duplicate = runtime.submit(event_id: "dedup-1", content: "same content")
  conflict = expect_error.call(CL::Conflict) { runtime.submit(event_id: "dedup-1", content: "different content") }
  check.call("request retry deduplicates terminal receipt and conflicting reuse is rejected",
             first == duplicate && conflict && backend.calls == 1)
  reopened = CL::Store.open(path: File.join(_root, "store"), config: defaults)
  resumed = CL::Runtime.new(store: reopened, backend: CL::FakeBackend.new(responses: [response.call("action" => "wait")]))
  persisted = resumed.resume(event_id: "dedup-1")
  check.call("terminal receipt and counters persist across reopen",
             persisted == first && reopened.integrity.is_a?(Hash) && reopened.snapshot.fetch("transaction_count") > 0)
  reopened.close
end

with_store.call do |store, root|
  other = CL::Store.open(path: File.join(root, "store"), config: defaults)
  nested_busy = expect_error.call(CL::Busy) { store.synchronize { other.synchronize {} } }
  other.close
  check.call("per-store nonblocking writer lock rejects a second writer", nested_busy)
end

crash_class = Class.new(Exception)
crashed = false
fault = lambda do |point, record|
  if point == :after_commit && record["kind"] == "accepted" && !crashed
    crashed = true
    raise crash_class
  end
end
with_store.call(defaults, fault:) do |store, _root|
  runtime = CL::Runtime.new(store:, backend: CL::FakeBackend.new(responses: [response.call("action" => "wait")]))
  expect_error.call(crash_class) { runtime.submit(event_id: "pending-1", content: "Pending synthetic request") }
  blocked = expect_error.call(CL::Busy) { runtime.submit(event_id: "pending-2", content: "Must not pass pending work") }
  resumed = runtime.resume(event_id: "pending-1")
  check.call("pending event blocks new admission until explicit resume",
             blocked && resumed["event_id"] == "pending-1" && store.snapshot.fetch("events").key?("pending-1"))
end

response_crash = false
response_fault = lambda do |point, record|
  if point == :after_commit && record["kind"] == "model_response" && !response_crash
    response_crash = true
    raise crash_class
  end
end
with_store.call(CL::Config.new("max_model_calls" => 1), fault: response_fault) do |store, _root|
  backend = CL::FakeBackend.new(responses: [response.call(tool.call(note_id: "persisted", revision: 0, content: "one committed effect")), response.call("action" => "wait")])
  runtime = CL::Runtime.new(store:, backend:)
  expect_error.call(crash_class) { runtime.submit(event_id: "counter-1", content: "Persist the model-call count") }
  receipt = runtime.resume(event_id: "counter-1")
  check.call("resumption reuses the committed response and persisted call budget",
             receipt["state"] == "failed" && backend.calls == 1 && store.snapshot.fetch("notes").key?("persisted"))
end

with_store.call(CL::Config.new("max_notes" => 1)) do |store, _root|
  first_backend = CL::FakeBackend.new(responses: [
    response.call(tool.call(note_id: "one", revision: 0, content: "one")), response.call("action" => "wait")
  ])
  second_backend = CL::FakeBackend.new(responses: [
    response.call(tool.call(note_id: "two", revision: 0, content: "two")), response.call("action" => "wait")
  ])
  CL::Runtime.new(store:, backend: first_backend).submit(event_id: "quota-1", content: "First note")
  second = CL::Runtime.new(store:, backend: second_backend).submit(event_id: "quota-2", content: "Exceed note quota")
  check.call("note quota prevents a second committed note",
             second["event_id"] == "quota-2" && store.snapshot.fetch("notes").keys == ["one"] &&
               store.snapshot.fetch("operations").last.dig("result", "reason") == "note_count_quota")
end

with_store.call do |store, _root|
  backend = CL::FakeBackend.new(responses: [response.call("action" => "reply", "content" => "committed")])
  runtime = CL::Runtime.new(store:, backend:)
  delivery_failed = false
  begin
    runtime.submit(event_id: "delivery-1", content: "Retry receipt",) { raise "fixture delivery failure" }
  rescue RuntimeError
    delivery_failed = true
  end
  calls_after_commit = backend.calls
  retry_receipt = runtime.submit(event_id: "delivery-1", content: "Retry receipt")
  check.call("failed receipt delivery can be retried without repeating model work",
             delivery_failed && retry_receipt["reply"] == "committed" && backend.calls == calls_after_commit)
end

puts "#{checks - errors.length}/#{checks} checks passed"
exit(errors.empty? ? 0 : 1)
