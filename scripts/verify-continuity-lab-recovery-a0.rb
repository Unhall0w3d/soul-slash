#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "timeout"
require_relative "../lib/soul_core/continuity_lab/runtime"

Lab = SoulCore::ContinuityLab
class InjectedCrash < Exception; end
checks = 0
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks += 1
end
raises = lambda do |type, &operation|
  begin
    operation.call
  rescue type
    true
  else
    false
  end
end
write = JSON.generate("action" => "tool", "tool" => "note.write",
                      "arguments" => { "note_id" => "lesson", "expected_revision" => 0, "content" => "Synthetic retained note" })
wait = JSON.generate("action" => "wait")
config = Lab::Config.new

# The note and actual result are the same authoritative transaction. Faults in
# staging are not external side effects and must not be reported as such.
%w[accepted model_intent model_response action_result terminal].each do |kind|
  %i[before_stage after_stage after_commit].each do |point|
    Dir.mktmpdir("continuity-recovery-") do |parent|
      path = File.join(parent, "store")
      fired = false
      fault = lambda do |observed_point, record|
        if !fired && observed_point == point && record["kind"] == kind
          fired = true
          raise InjectedCrash
        end
      end
      store = Lab::Store.create(path: path, config: config, fault: fault)
      first_backend = Lab::FakeBackend.new(responses: [write, wait])
      runtime = Lab::Runtime.new(store: store, backend: first_backend)
      check.call("fault fired #{kind}/#{point}", raises.call(InjectedCrash) { runtime.submit(event_id: "event", content: "Synthetic task") })
      store.close
      reopened = Lab::Store.open(path: path, config: config)
      second_backend = Lab::FakeBackend.new(responses: [write, wait])
      continued = Lab::Runtime.new(store: reopened, backend: second_backend)
      result = continued.submit(event_id: "event", content: "Synthetic task")
      ambiguous = (kind == "model_intent" && point == :after_commit) ||
                  (kind == "model_response" && point != :after_commit)
      snapshot = reopened.snapshot
      if ambiguous
        check.call("ambiguous intent stops #{kind}/#{point}", result["state"] == "blocked_for_human_review" && second_backend.calls.zero? && snapshot["notes"].empty?)
        check.call("blocked lineage does not accept new work", raises.call(Lab::Busy) { continued.submit(event_id: "new", content: "Do not continue") })
      else
        check.call("recovery completes #{kind}/#{point}", result["state"] == "complete" && result["reason"] == "wait")
        check.call("one note revision #{kind}/#{point}", snapshot["notes"]["lesson"]["revision"] == 1 && snapshot["operations"].length == 1)
        check.call("committed calls not repeated #{kind}/#{point}", first_backend.calls + second_backend.calls == 2)
      end
      check.call("reconstructed journal valid #{kind}/#{point}", reopened.integrity["ok"])
      before_retry = reopened.integrity["transaction_count"]
      continued.resume(event_id: "event")
      check.call("terminal replay adds no records #{kind}/#{point}", reopened.integrity["transaction_count"] == before_retry)
      reopened.close
    end
  end
end

mutations = {
  "truncated commit" => ->(path) { file = Dir.glob("#{path}/commit-*.json").first; File.write(file, File.read(file)[0..-8]) },
  "tampered content" => ->(path) { file = Dir.glob("#{path}/commit-*.json").first; File.write(file, File.read(file).sub("Synthetic task", "Other contents")) },
  "missing middle commit" => ->(path) { File.rename("#{path}/commit-00000002.json", "#{path}/.stage-#{'a' * 32}.json") },
  "symlink commit" => lambda { |path|
    file = "#{path}/commit-00000001.json"
    moved = "#{File.dirname(path)}/outside.json"
    File.rename(file, moved)
    File.symlink(moved, file)
  },
  "hardlinked commit" => ->(path) { File.link("#{path}/commit-00000001.json", "#{File.dirname(path)}/duplicate.json") },
  "public commit" => ->(path) { File.chmod(0o644, "#{path}/commit-00000001.json") },
  "unexpected file" => ->(path) { File.write("#{path}/foreign.json", "{}") },
  "special file" => ->(path) { File.mkfifo("#{path}/.stage-#{'b' * 32}.json", 0o600) }
}
mutations.each do |label, mutate|
  Dir.mktmpdir("continuity-integrity-") do |parent|
    path = File.join(parent, "store")
    store = Lab::Store.create(path: path)
    backend = Lab::FakeBackend.new(responses: [wait])
    Lab::Runtime.new(store: store, backend: backend).submit(event_id: "event", content: "Synthetic task")
    mutate.call(path)
    check.call("reject #{label}", raises.call(Lab::IntegrityError) { store.integrity })
    check.call("bad journal never invokes backend #{label}", raises.call(Lab::IntegrityError) { Lab::Runtime.new(store: store, backend: backend).submit(event_id: "next", content: "Denied") } && backend.calls == 1)
    store.close
  end
end

Dir.mktmpdir("continuity-directory-") do |parent|
  path = File.join(parent, "store")
  store = Lab::Store.create(path: path)
  check.call("create never overwrites store", raises.call(Lab::Conflict) { Lab::Store.create(path: path) })
  outside = File.join(parent, "outside")
  Dir.mkdir(outside, 0o700)
  File.rename(path, File.join(parent, "retained"))
  File.symlink(outside, path)
  backend = Lab::FakeBackend.new(responses: [write, wait])
  result = Lab::Runtime.new(store: store, backend: backend).submit(event_id: "event", content: "Synthetic task")
  check.call("directory descriptor prevents path redirection", result["state"] == "complete" && Dir.children(outside).empty?)
  check.call("reopen refuses symlink root", raises.call(Lab::IntegrityError) { Lab::Store.open(path: path) })
  File.symlink(File.join(parent, "retained"), File.join(parent, "alias"))
  check.call("create refuses symlink ancestor", raises.call(Lab::IntegrityError) { Lab::Store.create(path: File.join(parent, "alias", "child")) })
  store.close
end

Dir.mktmpdir("continuity-lock-") do |parent|
  path = File.join(parent, "store")
  store = Lab::Store.create(path: path)
  File.rename("#{path}/lock", "#{parent}/old-lock")
  File.open("#{path}/lock", File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write("") }
  check.call("replaced writer lock is rejected", raises.call(Lab::IntegrityError) { store.integrity })
  store.close
end

Dir.mktmpdir("continuity-quota-") do |parent|
  path = File.join(parent, "store")
  small = Lab::Config.new("max_journal_bytes" => 4096)
  store = Lab::Store.create(path: path, config: small)
  backend = Lab::FakeBackend.new(responses: [JSON.generate("action" => "reply", "content" => "x" * 5000)])
  runtime = Lab::Runtime.new(store: store, backend: backend)
  check.call("storage quota aborts without pruning", raises.call(Lab::QuotaExceeded) { runtime.submit(event_id: "large", content: "Bounded task") })
  check.call("quota preserves committed intent", store.snapshot["events"]["large"]["calls"].length == 1 && store.integrity["ok"])
  result = runtime.resume(event_id: "large")
  check.call("uncertain response after quota is not regenerated", result["state"] == "blocked_for_human_review" && backend.calls == 1)
  store.close
end

Dir.mktmpdir("continuity-escaped-") do |parent|
  store = Lab::Store.create(path: File.join(parent, "store"))
  raw = "\u0001" * 65_536
  backend = Lab::FakeBackend.new(responses: [raw, wait])
  result = Lab::Runtime.new(store: store, backend: backend).submit(event_id: "escaped", content: "Bounded invalid response")
  check.call("encoded record sizing permits safe reopen", result["state"] == "complete" && store.integrity["ok"])
  store.close
end

Dir.mktmpdir("continuity-delivery-") do |parent|
  store = Lab::Store.create(path: File.join(parent, "store"))
  backend = Lab::FakeBackend.new(responses: [write, wait])
  runtime = Lab::Runtime.new(store: store, backend: backend)
  delivered_outside_lock = false
  begin
    runtime.submit(event_id: "event", content: "Synthetic task") do |_receipt|
      delivered_outside_lock = store.integrity["ok"]
      raise IOError, "simulated client disconnect"
    end
  rescue IOError
    # Client receipt loss is not loss of the already-committed operation.
  end
  result = runtime.submit(event_id: "event", content: "Synthetic task")
  check.call("delivery is outside lock and safely replayable", delivered_outside_lock && result["state"] == "complete" && backend.calls == 2 && store.snapshot["notes"]["lesson"]["revision"] == 1)
  store.close
end

%w[leaf ancestor].each do |placement|
  Dir.mktmpdir("continuity-fifo-path-") do |parent|
    fifo = File.join(parent, "fifo")
    File.mkfifo(fifo, 0o600)
    path = placement == "leaf" ? fifo : File.join(fifo, "store")
    check.call("FIFO #{placement} rejected without blocking", Timeout.timeout(2) { raises.call(Lab::IntegrityError) { Lab::Store.open(path: path) } })
  end
end

Dir.mktmpdir("continuity-manifest-") do |parent|
  path = File.join(parent, "store")
  store = Lab::Store.create(path: path)
  File.write("#{path}/manifest.json", JSON.generate("schema" => "foreign"))
  check.call("open handle rejects manifest drift", raises.call(Lab::IntegrityError) { store.integrity })
  store.close
end

Dir.mktmpdir("continuity-semantic-journal-") do |parent|
  store = Lab::Store.create(path: File.join(parent, "store"))
  store.synchronize do
    id = "event"
    store.append("accepted", { "event_id" => id, "content" => "Synthetic", "content_digest" => Digest::SHA256.hexdigest("Synthetic") })
    store.append("model_intent", { "event_id" => id, "call_index" => 0 })
    store.append("model_response", { "event_id" => id, "call_index" => 0, "response" => wait })
    invented = { "event_id" => id, "call_index" => 0, "operation_id" => Lab.digest({ "event_id" => id, "call_index" => 0 }),
                 "invalid" => false, "tool_attempt" => true }
    invented.merge!(Lab::Actions.note_result({}, { "note_id" => "forged", "expected_revision" => 0, "content" => "not requested" }, config))
    check.call("wait response cannot authorize a note", raises.call(Lab::IntegrityError) { store.append("action_result", invented) })
    check.call("wait response cannot become an invented reply", raises.call(Lab::IntegrityError) { store.append("terminal", { "event_id" => id, "state" => "complete", "reason" => "reply", "reply" => "invented" }) })
  end
  check.call("rejected journal transition writes no commit", store.integrity["transaction_count"] == 3 && store.snapshot["notes"].empty?)
  store.close
end

Dir.mktmpdir("continuity-cross-lineage-") do |parent|
  a_path = File.join(parent, "a")
  b_path = File.join(parent, "b")
  a = Lab::Store.create(path: a_path)
  b = Lab::Store.create(path: b_path)
  Lab::Runtime.new(store: a, backend: Lab::FakeBackend.new(responses: [wait])).submit(event_id: "event", content: "Synthetic")
  Dir.glob("#{a_path}/commit-*.json").each do |source|
    File.open(File.join(b_path, File.basename(source)), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(File.binread(source)) }
  end
  check.call("journal cannot be transplanted between lineages", raises.call(Lab::IntegrityError) { b.integrity })
  a.close
  b.close
end

Dir.mktmpdir("continuity-invalid-input-") do |parent|
  store = Lab::Store.create(path: File.join(parent, "store"))
  runtime = Lab::Runtime.new(store: store, backend: Lab::FakeBackend.new(responses: [wait]))
  ["id".encode("UTF-16LE"), "bad\xff".b, "../escape", "/absolute", "a.b", "x" * 65].each do |id|
    check.call("invalid event ID is rejected predictably", raises.call(Lab::ValidationError) { runtime.submit(event_id: id, content: "Synthetic") })
  end
  check.call("invalid inputs do not accept events", store.integrity["event_count"].zero?)
  store.close
end

invalid_actions = [
  '{"action":"tool","action":"wait"}',
  JSON.generate("action" => "wait", "state" => "complete"),
  JSON.generate("action" => "tool", "tool" => "shell", "arguments" => { "command" => "not executed" }),
  JSON.generate("action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "../escape", "expected_revision" => 0, "content" => "no" }),
  JSON.generate("action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "note", "expected_revision" => "0", "content" => "no" }),
  JSON.generate("action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "note", "expected_revision" => 0, "content" => "x" * 4097 }),
  JSON.generate("action" => "tool", "tool" => "note.write", "operation_id" => "invented", "arguments" => { "note_id" => "note", "expected_revision" => 0, "content" => "no" }),
  JSON.generate("action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "note", "expected_revision" => 0, "content" => "no", "privileged" => true }),
  "[" * 30 + "0" + "]" * 30
]
invalid_actions.each_with_index do |raw, index|
  Dir.mktmpdir("continuity-invalid-action-") do |parent|
    strict = Lab::Config.new("max_invalid_actions" => 0)
    store = Lab::Store.create(path: File.join(parent, "store"), config: strict)
    backend = Lab::FakeBackend.new(responses: [raw, wait])
    result = Lab::Runtime.new(store: store, backend: backend).submit(event_id: "event", content: "Synthetic")
    check.call("invalid action #{index} has no effect and no hidden retry", result["state"] == "failed" && backend.calls == 1 && store.snapshot["notes"].empty?)
    check.call("actual denial retained #{index}", store.snapshot["operations"].first.dig("result", "ok") == false)
    store.close
  end
end

Dir.mktmpdir("continuity-tool-budget-") do |parent|
  strict = Lab::Config.new("max_tool_calls" => 0)
  store = Lab::Store.create(path: File.join(parent, "store"), config: strict)
  result = Lab::Runtime.new(store: store, backend: Lab::FakeBackend.new(responses: [write])).submit(event_id: "event", content: "Synthetic")
  check.call("zero tool budget permits no note effect", result["reason"] == "tool_call_budget" && store.snapshot["notes"].empty?)
  store.close
end

check.call("configuration values cannot mutate after validation", raises.call(FrozenError) { config["backend"].replace("remote") })

Dir.mktmpdir("continuity-missing-manifest-") do |parent|
  path = File.join(parent, "store")
  store = Lab::Store.create(path: path)
  File.rename("#{path}/manifest.json", "#{parent}/retained-manifest.json")
  check.call("missing manifest returns a typed integrity failure", raises.call(Lab::IntegrityError) { store.integrity })
  store.close
end

Dir.mktmpdir("continuity-transaction-quota-") do |parent|
  strict = Lab::Config.new("max_transactions" => 8)
  store = Lab::Store.create(path: File.join(parent, "store"), config: strict)
  backend = Lab::FakeBackend.new(responses: [wait])
  runtime = Lab::Runtime.new(store: store, backend: backend)
  runtime.submit(event_id: "one", content: "Synthetic")
  runtime.submit(event_id: "two", content: "Synthetic")
  check.call("transaction quota preserves prior terminal history", raises.call(Lab::QuotaExceeded) { runtime.submit(event_id: "three", content: "Synthetic") } && store.integrity["transaction_count"] == 8 && backend.calls == 2)
  store.close
end

puts "PASS: #{checks} Continuity Lab A0 recovery checks (synthetic backend only)"
