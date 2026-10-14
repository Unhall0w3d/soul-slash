#!/usr/bin/env ruby
# frozen_string_literal: true

# New fixed A18 qualification. A16 entrypoint and frozen hash gates are unchanged.
require_relative "qualify-continuity-lab-qwen-a16"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a18"

def a18_config(condition)
  { "agentic" => Lab::Config.qwen_v8_qualification, "direct" => Lab::Config.qwen_v9_qualification }.fetch(condition)
end

def a18_mode(condition) = { "agentic" => "qwen_v8_run", "direct" => "qwen_v9_run" }.fetch(condition)

def run_a18_batch(condition, batch, suite_root, suite_deadline, frozen_sources)
  message_profile = condition == "direct" ? Lab::QwenMessageProjection::PROFILE_DIRECT : Lab::QwenMessageProjection::PROFILE_RECENT_PAIRS
  message_guide = condition == "direct" ? Lab::DirectEvidence::SYSTEM + "\n" + Lab::DirectEvidence::PROTOCOL : Lab::QwenMessageProjection::GUIDE_RECEIPT_PAIRS
  File.umask(0o077)
  root = File.expand_path("..", __dir__)
  base = File.join(root, "Soul/runtime/qualification")
  abort "Qualification parent is not canonical" unless File.realpath(base) == base
  output = File.join(suite_root, "#{condition}-#{batch}")
  Dir.mkdir(output, 0o700)
  puts "Evidence: #{output}"
  $stdout.sync = true
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  # Reserve twenty seconds inside the overall budget for cancellation/read-back.
  overall_deadline = [started + 1200, suite_deadline].min
  deadline = overall_deadline - 20
  write = lambda do |name, data|
    File.open(File.join(output, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(Lab.encode(data) + "\n")
      file.flush
      file.fsync
    end
  end
  events = File.open(File.join(output, "calls.jsonl"), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600)
  runner = SoulCore::BoundedCommandRunner.new
  client = Lab::QwenTransport.new
  observer = Lab::QwenHostObserver.new(root: root, client: client, expected_pid: 3065)
  leases = SoulCore::ModelRuntimeLeaseStore.new(root: root)
  admission_events = []
  gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: observer, lock_wait_seconds: 5,
    on_contention: ->(event) { admission_events << event.merge("elapsed" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) })
  cases = Lab::QualificationCasesA18.cases(batch)
  abort "Case ceiling exceeded" unless cases.length.between?(1, 4)
  results, attempted, returned, gpu_samples = [], [], [], []
  generation_count = 0
  current_case, store, failure = nil, nil, nil
  phase = "preflight"
  config = a18_config(condition)
  state_path = File.join(output, "worker-#{batch}")
  worker_pids = []
  sample_gpu = lambda do
    sample = runner.run("nvidia-smi", "--query-gpu=name,memory.total,memory.used", "--format=csv,noheader,nounits", timeout_seconds: 2, max_output_bytes: 2048)
    raise Lab::AdmissionDenied, "GPU sample unavailable" unless sample.success? && !sample.truncated
    gpu_samples << { "elapsed" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, "devices" => sample.stdout.lines.map(&:strip) }
  end
  receipt_writer = lambda do |receipt|
    events.write(Lab.encode(receipt.merge("case_id" => current_case, "recorded_at" => Time.now.utc.iso8601(6), "condition" => condition)) + "\n")
    events.flush
    events.fsync
  end
  before_generation = lambda do
    raise Lab::BackendUnavailable, "qualification budget exhausted" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline || generation_count >= cases.length * config["max_model_calls"]
    generation_count += 1
    sample_gpu.call
  end
  begin
    Timeout.timeout([deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.001].max) do
      drift = frozen_sources.keys.reject { |path| Digest::SHA256.file(path).hexdigest == frozen_sources.fetch(path) }
      raise Lab::IntegrityError, "frozen A18 source changed" unless drift.empty?
      hashes = { "model" => Digest::SHA256.file(Lab::QwenHostObserver::MODEL).hexdigest,
                 "server" => Digest::SHA256.file(Lab::QwenHostObserver::SERVER).hexdigest }
      # Pin the approved installed bytes; do not select a replacement model/build.
      unless hashes == {
          "model" => "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
          "server" => "9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81" }
        raise Lab::AdmissionDenied, "model/build hash changed"
      end
      gate.with_window { observer.call }
      props = client.request("GET", "/props", deadline: deadline)
      write.call("baseline.json", { "schema" => "soul.continuity_lab.qwen_qualification.a18", "condition" => condition, "started_at" => Time.now.utc.iso8601,
        "host" => observer.last_evidence, "file_hashes" => hashes, "props" => props,
        "config" => config.to_h, "batch" => batch, "settings" => Lab::QwenBrokerSession::V3_SETTINGS.merge("stream" => true).merge(condition == "direct" ? { "grammar" => Lab::QwenBrokerSession::DIRECT_GRAMMAR } : {}),
        "message_profile" => message_profile, "message_guide" => message_guide,
        "execution_profile" => Lab::Config::STREAM_PROFILE, "cold_scope" => "new_worker_not_model_server",
        "bounds" => { "request_seconds" => 60, "event_seconds" => 420, "worker_seconds" => 430, "batch_seconds" => 1200, "work_seconds" => 1180, "cleanup_reserve_seconds" => 20, "generation_calls" => cases.length * config["max_model_calls"] },
        "prompt_version" => Lab::QwenBrokerSession::V4_PROMPT_VERSION, "case_version" => Lab::QualificationCasesA18::VERSION,
        "case_specs" => cases, "code_hashes" => frozen_sources })
      Dir.mkdir(state_path, 0o700)
      store = Lab::Store.create(path: File.join(state_path, "store"), config: config, corpus: Lab::QualificationCasesA18.corpus(batch))
      write.call("setup.json", { "source" => "empty_store_operator_selected_corpus_no_seeded_model_actions", "integrity" => store.integrity })
      store.close
      store = nil
      sample_gpu.call
      cases.each_with_index do |spec, index|
        current_case = spec.fetch("id")
        store = Lab::Store.open(path: File.join(state_path, "store"), config: config)
        before = store.snapshot
        raise Lab::IntegrityError, "pre-event journal failed integrity" unless store.integrity["ok"]
        # A callback needs the earlier exchange to exist, not its answer to have
        # passed. This measures recovery from prior mistakes without inventing state.
        store.close
        store = nil
        predecessors = spec.fetch("requires_events").all? { |id| before.dig("events", id, "state") == "complete" && before.dig("events", id, "reason") == "reply" }
        unless predecessors
          results << { "id" => current_case, "group" => batch, "passed" => false, "status" => "unmet_prerequisite",
            "reasons" => ["required_predecessor_or_note_missing"], "calls" => 0, "tools" => [], "omitted_groups" => [], "invalid_actions" => 0 }
          write.call("case-#{index + 1}.json", results.last)
          puts "SKIP #{current_case}: unmet prerequisite"
          next
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Lab::BackendUnavailable, "qualification time budget exhausted" if remaining < 1
        worker = Lab::SandboxRunner.new(state_directory: state_path, timeout_seconds: [remaining, 430].min, execution_profile: Lab::Config::STREAM_PROFILE)
        broker = Lab::QwenBrokerSession.new(client: client, observer: observer, on_receipt: receipt_writer,
          before_generation: before_generation, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: Lab::TokenContext.budget(config), execution_profile: Lab::Config::STREAM_PROFILE, message_profile: message_profile)
        puts "START #{current_case}"
        attempted << current_case
        phase = "worker"
        outcome = worker.run(request: { "mode" => a18_mode(condition),
          "create" => false, "event_id" => current_case, "content" => spec["content"], "corpus" => [] }, broker: broker, admission: gate)
        returned << { "case_id" => current_case, "receipt" => outcome.dig("result", "receipt"), "worker_pid" => outcome["worker_pid"] }
        phase = "postprocessing"
        store = Lab::Store.open(path: File.join(state_path, "store"), config: config)
        after = store.snapshot
        event = after["events"].fetch(current_case)
        integrity = store.integrity
        raise Lab::IntegrityError, "post-event journal failed integrity" unless integrity["ok"]
        pid = outcome.fetch("worker_pid")
        fresh_worker = !worker_pids.include?(pid) && !File.exist?("/proc/#{pid}")
        worker_pids << pid
        receipt_matches = outcome.dig("result", "receipt") == event.slice("event_id", "state", "reason", "reply")
        score = Lab::QualificationCasesA18.evaluate(event: event, config: config,
          spec: spec, before: before, after: after)
        score["passed"] &&= fresh_worker && receipt_matches
        score["status"] = "invalid_worker_evidence" unless fresh_worker && receipt_matches
        score["reasons"] << "fresh_worker_or_receipt_mismatch" unless fresh_worker && receipt_matches
        results << score.merge("id" => current_case, "group" => batch, "receipt" => outcome["result"]["receipt"], "calls" => broker.calls,
          "tools" => event["calls"].filter_map { |call| Lab::Actions.parse(call["response"].to_s, config)["tool"] },
          "invalid_actions" => event["invalid_count"], "omitted_groups" => event["calls"].flat_map { |call| call.dig("context", "manifest", "omitted_groups") || [] })
        results.last["fresh_worker_exited"] = fresh_worker
        results.last["receipt_matches_durable_event"] = receipt_matches
        results.last["journal_integrity"] = integrity
        results.last["before_notes_digest"] = Lab.digest(before["notes"])
        results.last["after_notes_digest"] = Lab.digest(after["notes"])
        write.call("case-#{index + 1}.json", results.last)
        evidence_failures = %w[context_replay_mismatch tool_result_replay_mismatch durable_notes_mismatch
          event_identity_mismatch invalid_action_result_mismatch fresh_worker_or_receipt_mismatch]
        if score["status"] == "invalid_evidence" || !(score.fetch("reasons") & evidence_failures).empty?
          raise Lab::IntegrityError, "case assessment evidence invalid; no further inference"
        end
        store.close
        store = nil
        gate.with_window { observer.call }
        sample_gpu.call
        puts "#{score['passed'] ? 'MECHANICAL_OK' : 'SCREEN_FAIL'} #{current_case}: #{event['reason']}, calls=#{broker.calls}, #{score['reasons']}"
        break if a16_stop_receipt?(event)
      end
    end
  rescue StandardError, Interrupt => error
    failure = { "case_id" => current_case, "phase" => phase, "class" => error.class.name, "message" => error.message }
    puts "STOP #{failure}"
  ensure
    store&.close
    idle = begin
      remaining = overall_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise Timeout::Error, "idle verification budget exhausted" unless remaining.positive?
      Timeout.timeout([8, remaining].min) { gate.with_window { observer.call } }
      true
    rescue StandardError
      false
    end
    idle_immediately = idle
    settle_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    settle_errors = []
    unless idle
      begin
        remaining = overall_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Timeout::Error, "idle settle budget exhausted" unless remaining.positive?
        Timeout.timeout([5, remaining].min) do
          until idle
            sleep 0.2
            begin
              gate.with_window { observer.call }
              idle = true
            rescue StandardError => error
              settle_errors << error.class.name
            end
          end
        end
      rescue Timeout::Error
        # This observes cancellation only; it never retries generation or kills
        # the resident service to manufacture an idle result.
      end
    end
    events.close
    batch_summary = { "finished_at" => Time.now.utc.iso8601, "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
      "batch" => batch, "assessment" => "mechanical_screen_only_requires_primary_semantic_review", "cold_scope" => "new_worker_not_model_server",
      "generation_calls" => generation_count, "results" => results, "failure" => failure, "idle_verified_at_end" => idle,
      "idle_verified_immediately" => idle_immediately, "idle_settle_seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - settle_started,
      "idle_settle_errors" => settle_errors, "admission_contention" => admission_events,
      "gpu_samples" => gpu_samples, "recorded_cases" => results.length,
      "scored_cases" => results.count { |entry| entry.key?("receipt") }, "mechanical_passed_cases" => results.count { |entry| entry["passed"] },
      "attempted_cases" => attempted, "returned_worker_receipts" => returned,
      "unmet_prerequisites" => results.count { |entry| entry["status"] == "unmet_prerequisite" },
      "not_started_cases" => cases.length - attempted.length - results.count { |entry| !entry.key?("receipt") },
      "unscored_cases" => attempted - results.map { |entry| entry["id"] }, "condition" => condition }
    write.call("summary.json", batch_summary)
    puts "Finished: #{results.count { |entry| entry['passed'] }}/#{results.length} recorded cases mechanically eligible; semantic review still required; idle=#{idle}"
  end
  batch_summary
end

if $PROGRAM_NAME == __FILE__
  abort "Requires --approved-quiet-window for the fixed A18 suite" unless ARGV == ["--approved-quiet-window"]
  File.umask(0o077)
  root = File.expand_path("..", __dir__)
  base = File.join(root, "Soul/runtime/qualification")
  abort "Qualification parent is not canonical" unless File.realpath(base) == base
  suite_root = File.join(base, "continuity-lab-a18-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
  Dir.mkdir(suite_root, 0o700)
  puts "Suite evidence: #{suite_root}"
  $stdout.sync = true
  suite_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  suite_deadline = suite_start + 1200
  persist = lambda do |name, value|
    File.open(File.join(suite_root, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(Lab.encode(value) + "\n")
      file.flush
      file.fsync
    end
  end
  order = %w[planning holdout conversation transfer distractors heldout].each_with_index.flat_map do |batch, index|
    (index.even? ? %w[agentic direct] : %w[direct agentic]).map { |condition| [condition, batch] }
  end
  batches, suite_error, preservation = [], nil, nil
  history_before, source_before = nil, nil
  begin
    history_before = a16_history_hashes(base, exclude: suite_root)
    source_paths = Dir.glob(File.join(root, "lib/soul_core/continuity_lab/*.{rb,gbnf}")) +
      %w[lib/soul_core/model_runtime_lease_store.rb lib/soul_core/bounded_command_runner.rb].map { |path| File.join(root, path) } +
      Dir.glob(File.join(root, "scripts/*continuity-lab*")) +
      Dir.glob(File.join(root, "docs/{soul,assessments}/CONTINUITY_LAB*"))
    source_before = source_paths.sort.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
    persist.call("suite-baseline.json", {
      "schema" => "soul.continuity_lab.a18_suite.v1",
      "started_at" => Time.now.utc.iso8601, "order" => order, "max_seconds" => 1200, "max_generations" => 168, "max_events" => 48,
      "history_hashes" => history_before, "source_hashes" => source_before,
      "historical_integrity" => a16_validate_stores(base, exclude: suite_root),
      "conditions" => %w[agentic direct].to_h { |condition| [condition, a18_config(condition).to_h] },
      "cases" => %w[planning holdout conversation transfer distractors heldout].to_h { |batch| [batch, Lab::QualificationCasesA18.cases(batch)] }
    })
    order.each do |condition, batch|
      raise Lab::BackendUnavailable, "suite cleanup reserve reached" if suite_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC) <= 20
      drift = source_before.keys.reject { |path| Digest::SHA256.file(path).hexdigest == source_before.fetch(path) }
      raise Lab::IntegrityError, "A18 source changed during suite" unless drift.empty?
      result = run_a18_batch(condition, batch, suite_root, suite_deadline, source_before)
      batches << result
      break if result["failure"] || !result["idle_verified_at_end"] ||
        result.fetch("results").any? { |row| row["receipt"] && a16_stop_receipt?(row["receipt"]) }
    end
  rescue StandardError, Interrupt => error
    suite_error = { "class" => error.class.name, "message" => error.message }
    puts "SUITE STOP #{suite_error}"
  ensure
    begin
      preservation = {
        "historical_files_unchanged" => !history_before.nil? && a16_history_hashes(base, exclude: suite_root) == history_before,
        "historical_file_count" => history_before&.length,
        "historical_integrity" => a16_validate_stores(base, exclude: suite_root),
        "source_files_unchanged" => !source_before.nil? && source_before.all? { |path, hash| Digest::SHA256.file(path).hexdigest == hash }
      }
    rescue StandardError => error
      preservation = { "error" => error.class.name, "message" => error.message }
    end
    summary = { "finished_at" => Time.now.utc.iso8601,
      "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - suite_start,
      "batches" => batches, "failure" => suite_error, "preservation" => preservation,
      "generation_calls" => batches.sum { |batch| batch.fetch("generation_calls") },
      "unstarted_batches" => order.drop(batches.length),
      "assessment" => "mechanical_screens_only_primary_semantic_review_required" }
    persist.call("suite-summary.json", summary)
    puts "A18 suite ended: #{batches.length}/12 batches, #{summary['generation_calls']} generations"
  end
  exit(suite_error || batches.length != 12 || batches.any? { |batch| batch["failure"] || !batch["idle_verified_at_end"] ||
    batch.fetch("results").any? { |row| !row["passed"] } } ||
    !preservation["historical_files_unchanged"] || !preservation["source_files_unchanged"] ? 1 : 0)
end
