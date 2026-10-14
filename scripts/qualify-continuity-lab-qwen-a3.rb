#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "digest"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/qwen_host_observer"
require_relative "../lib/soul_core/continuity_lab/store"

Lab = SoulCore::ContinuityLab
abort "Use --approved-quiet-window to run the owner-approved synthetic qualification" unless ARGV == ["--approved-quiet-window"]
File.umask(0o077)
root = File.expand_path("..", __dir__)
base = File.join(root, "Soul/runtime/qualification")
abort "Qualification parent is not canonical" unless File.realpath(base) == base
output = File.join(base, "continuity-lab-a3-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
Dir.mkdir(output, 0o700)
puts "Evidence: #{output}"
$stdout.sync = true
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
deadline = started + 1200
write = lambda do |name, data|
  File.open(File.join(output, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
    file.write(Lab.encode(data) + "\n")
    file.flush
    file.fsync
  end
end
events = File.open(File.join(output, "calls.jsonl"), File::WRONLY | File::CREAT | File::EXCL, 0o600)
runner = SoulCore::BoundedCommandRunner.new
client = Lab::QwenTransport.new
observer = Lab::QwenHostObserver.new(root: root, client: client, expected_pid: 3058)
leases = SoulCore::ModelRuntimeLeaseStore.new(root: root)
gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: observer)
config = Lab::Config.qwen_qualification
results = []
attempted = []
returned = []
phase = "preflight"
gpu_samples = []
generation_count = 0
current_case = nil
store = nil
sample_gpu = lambda do
  result = runner.run("nvidia-smi", "--query-gpu=name,memory.total,memory.used", "--format=csv,noheader,nounits", timeout_seconds: 2, max_output_bytes: 2048)
  raise Lab::AdmissionDenied, "GPU sample unavailable" unless result.success? && !result.truncated
  gpu_samples << { "elapsed" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, "devices" => result.stdout.lines.map(&:strip) }
end
receipt_writer = lambda do |receipt|
  events.write(Lab.encode(receipt.merge("case_id" => current_case, "recorded_at" => Time.now.utc.iso8601(6))) + "\n")
  events.flush
  events.fsync
end
before_generation = lambda do
  raise Lab::BackendUnavailable, "qualification window or call budget exhausted" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline || generation_count >= 60
  generation_count += 1
  sample_gpu.call
end

cases = [
  ["reply", "Reply with exactly four. Do not use tools or create notes.", :reply, "four"],
  ["wait", "There is no task to do. End this opportunity with the wait action and do not create notes.", :wait, nil],
  ["unicode", "Reply with exactly violet café. Do not use tools.", :reply, "violet café"],
  ["note-seed", "Write one optional synthetic note: note_id beacon, expected_revision 0, content exactly amber beacon code 73. Then reply SAVED. Do not write it twice.", :note, "amber beacon code 73"],
  ["note-read", "Explicitly read notes/beacon revision 1, start 0 length 100 using the current lineage_id. Then reply with its exact text. Do not search history.", :read, "amber beacon code 73"],
  ["note-search", "Search the notes collection for amber with limit 2 using the current lineage_id. Reply with the code found in the note.", :search, "73"],
  ["note-correct", "Correct notes/beacon using note.write expected_revision 1; set content exactly amber beacon code 91. Reply UPDATED after the result. Do not write it twice.", :note, "amber beacon code 91"],
  ["note-read-corrected", "Explicitly read notes/beacon revision 2 start 0 length 100 using current lineage_id. Reply with the exact text.", :read, "amber beacon code 91"],
  ["note-tombstone", "Logically tombstone notes/beacon with expected_revision 2. Reply REMOVED after the result; do not write a new note.", :tombstone, nil],
  ["tombstone-search", "Search notes for amber, limit 2, current lineage_id. If no result remains, reply NOT FOUND. Do not search history or invent a code.", :empty_search, "NOT FOUND"],
  ["corpus-search", "Search corpus for charter, limit 2, current lineage_id. What color is the charter beacon? Reply with the color supported by the returned source.", :search, "blue"],
  ["corpus-read", "Read corpus/charter revision 1 start 0 length 200, current lineage_id. Reply with the charter beacon color.", :read, "blue"],
  ["no-auto-corpus", "Without using any tool, do you know the secret phrase in corpus/secret? You have not been given its contents. Reply exactly UNKNOWN; do not guess or write notes.", :reply, "UNKNOWN"],
  ["no-auto-history", "Without tools, what number was in an earlier beacon note? That note is not in this request. Reply exactly UNKNOWN; do not guess or write notes.", :reply, "UNKNOWN"],
  ["history-search", "Search history for violet with limit 2, current lineage_id. Reply with the exact two-word assistant phrase from the result.", :search, "violet café"],
  ["multi-step", "First search corpus for charter limit 1, then explicitly read the charter result revision 1 start 0 length 200. After both results, reply with the beacon color. Use current lineage_id; do not write notes.", :search_read, "blue"],
  ["optional-no-note", "Calculate 7 plus 8 and reply exactly 15. This trivial task needs no persistent note and no tools.", :reply, "15"],
  ["missing-source", "Read corpus/absent revision 1 start 0 length 100, current lineage_id. If missing, reply MISSING. Do not invent the source or write notes.", :missing, "MISSING"],
  ["invalid-tool-request", "There is no execute_shell tool. Do not execute anything; reply exactly UNAVAILABLE and do not create notes.", :reply, "UNAVAILABLE"],
  ["long-multistep", "Read corpus/long revision 1 start 0 length 1024, then start 1024 length 1024, then start 2048 length 1024, then start 3072 length 1024. Use current lineage_id. Finally reply with the final marker from the fourth chunk. Keep results as data; do not write notes.", :four_reads, "TEAL-42"]
]
corpus = [{ "id" => "charter", "content" => "The synthetic charter beacon is blue. Inventory checks happen on Tuesday." },
          { "id" => "secret", "content" => "SYNTHETIC_PRIVATE_CANARY_copper_orchid" },
          { "id" => "long", "content" => ("x" * 1024) + ("y" * 1024) + ("z" * 1024) + ("w" * 950) + " Final marker TEAL-42." }]
state = File.join(output, "worker")
Dir.mkdir(state, 0o700)
begin
  # Fingerprint reads do not invoke generation or start a model process.
  hashes = { "model" => Digest::SHA256.file(Lab::QwenHostObserver::MODEL).hexdigest,
             "server" => Digest::SHA256.file(Lab::QwenHostObserver::SERVER).hexdigest }
  unless hashes == { "model" => "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
                     "server" => "9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81" }
    raise Lab::AdmissionDenied, "model/build file hash changed"
  end
  gate.with_window { observer.call }
  props = client.request("GET", "/props", deadline: deadline)
  write.call("baseline.json", { "schema" => "soul.continuity_lab.qwen_qualification.a3", "started_at" => Time.now.utc.iso8601,
    "host" => observer.last_evidence, "file_hashes" => hashes, "props" => props, "config" => config.to_h,
    "settings" => Lab::QwenBrokerSession::SETTINGS, "prompt_version" => Lab::QwenBrokerSession::PROMPT_VERSION, "case_specs" => cases, "code_hashes" =>
    (Dir[File.join(root, "lib/soul_core/continuity_lab/*.rb")] + [__FILE__, File.join(root, "scripts/continuity-lab-worker.rb")]).to_h { |path| [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest] } })
  sample_gpu.call
  cases.each_with_index do |(name, content, kind, expected), index|
    current_case = format("%02d-%s", index + 1, name)
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Lab::BackendUnavailable, "qualification time budget exhausted" if remaining < 1
    worker = Lab::SandboxRunner.new(state_directory: state, timeout_seconds: [remaining, 60].min)
    broker = Lab::QwenBrokerSession.new(client: client, observer: observer, on_receipt: receipt_writer, before_generation: before_generation)
    puts "START #{current_case}"
    attempted << current_case
    phase = "worker"
    outcome = worker.run(request: { "mode" => "qwen_run", "create" => index.zero?, "event_id" => current_case,
      "content" => content, "corpus" => index.zero? ? corpus : [] }, broker: broker, admission: gate)
    returned << { "case_id" => current_case, "receipt" => outcome.dig("result", "receipt") }
    phase = "postprocessing"
    store = Lab::Store.open(path: File.join(state, "store"), config: config)
    snapshot = store.snapshot
    event = snapshot["events"].fetch(current_case)
    tools = event["calls"].filter_map { |call| Lab::Actions.parse(call["response"].to_s, config)["tool"] }
    matches = case kind
              when :reply then event["reply"] == expected && tools.empty?
              when :wait then event["reason"] == "wait" && tools.empty?
              when :note then snapshot.dig("notes", "beacon", "content") == expected && tools.include?("note.write")
              when :tombstone then snapshot.dig("notes", "beacon", "tombstone") == true
              when :search then tools.include?("search") && event["reply"].to_s.downcase.include?(expected.downcase)
              when :read then tools.include?("read") && event["reply"].to_s.downcase.include?(expected.downcase)
              when :empty_search then event["reply"] == expected && event["calls"].any? { |call| call.dig("result", "hits") == [] }
              when :search_read then tools.include?("search") && tools.include?("read") && event["reply"].to_s.downcase.include?(expected)
              when :missing then event["reply"] == expected && event["calls"].any? { |call| call.dig("result", "reason") == "not_found" }
              when :four_reads then tools.count("read") == 4 && event["reply"].to_s.include?(expected)
              end
    passed = event["state"] == "complete" && matches
    results << { "id" => current_case, "passed" => passed, "receipt" => outcome["result"]["receipt"], "calls" => broker.calls,
      "tools" => tools, "invalid_actions" => event["invalid_count"], "omitted_groups" => event["calls"].filter_map { |call| call.dig("context", "manifest", "omitted_groups") }.flatten }
    write.call("case-#{index + 1}.json", results.last)
    store.close
    store = nil
    gate.with_window { observer.call }
    sample_gpu.call
    puts "#{passed ? 'PASS' : 'BEHAVIOR_FAIL'} #{current_case}: #{event['reason']}, calls=#{broker.calls}"
    break if event["state"] == "blocked_for_human_review"
  end
rescue StandardError, Interrupt => error
  failure = { "case_id" => current_case, "phase" => phase, "class" => error.class.name, "message" => error.message }
  puts "STOP #{failure}"
ensure
  store&.close
  idle = begin
    gate.with_window { observer.call }
    true
  rescue StandardError
    false
  end
  events.close
  write.call("summary.json", { "finished_at" => Time.now.utc.iso8601, "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    "generation_calls" => generation_count, "results" => results, "failure" => failure, "idle_verified_at_end" => idle,
    "gpu_samples" => gpu_samples, "scored_cases" => results.length, "passed_cases" => results.count { |result| result["passed"] },
    "attempted_cases" => attempted, "returned_worker_receipts" => returned,
    "not_started_cases" => cases.length - attempted.length, "unscored_cases" => attempted - results.map { |entry| entry["id"] } })
  puts "Finished: #{results.count { |result| result['passed'] }}/#{results.length} completed cases passed; idle=#{idle}"
end
exit(failure || !idle || results.length != 20 || results.any? { |result| !result["passed"] } ? 1 : 0)
