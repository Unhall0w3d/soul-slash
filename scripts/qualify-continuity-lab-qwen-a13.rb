#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "digest"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/qwen_host_observer"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a13"
require_relative "../lib/soul_core/continuity_lab/qualification_scorer"

Lab = SoulCore::ContinuityLab
receipt_pairs = ARGV.length == 2 && ARGV.last == "--receipt-pairs"
mode = receipt_pairs ? ARGV.first(1) : ARGV
calibration_only = mode == ["--calibrate-only"]
abort "Requires --calibrate-only or --approved-quiet-window, optionally --receipt-pairs, for A13" unless calibration_only || mode == ["--approved-quiet-window"]
message_profile = receipt_pairs ? Lab::QwenMessageProjection::PROFILE_RECEIPT_PAIRS : Lab::QwenMessageProjection::PROFILE_RECEIPTS
message_guide = receipt_pairs ? Lab::QwenMessageProjection::GUIDE_RECEIPT_PAIRS : Lab::QwenMessageProjection::GUIDE_RECEIPTS
File.umask(0o077)
root = File.expand_path("..", __dir__)
base = File.join(root, "Soul/runtime/qualification")
abort "Qualification parent is not canonical" unless File.realpath(base) == base
output = File.join(base, "continuity-lab-a13#{receipt_pairs ? '-pairs' : ''}#{calibration_only ? '-sizing' : ''}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
Dir.mkdir(output, 0o700)
puts "Evidence: #{output}"
$stdout.sync = true
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
# Reserve twenty seconds inside the overall budget for cancellation/read-back.
overall_deadline = started + (calibration_only ? 120 : 1800)
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
observer = Lab::QwenHostObserver.new(root: root, client: client, expected_pid: 3058)
leases = SoulCore::ModelRuntimeLeaseStore.new(root: root)
admission_events = []
gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: observer, lock_wait_seconds: 5,
  on_contention: ->(event) { admission_events << event.merge("elapsed" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) })
cases = Lab::QualificationCasesA13.cases
abort "Case ceiling exceeded" unless cases.length == 4
results, attempted, returned, gpu_samples = [], [], [], []
generation_count = 0
current_case, store, failure = nil, nil, nil
calibration_valid = false
phase = "preflight"
configs = cases.to_h { |spec| [spec.fetch("id"), Lab::Config.qwen_v6_qualification(rollover: spec.fetch("condition") == "rollover")] }
states = {}
sample_gpu = lambda do
  sample = runner.run("nvidia-smi", "--query-gpu=name,memory.total,memory.used", "--format=csv,noheader,nounits", timeout_seconds: 2, max_output_bytes: 2048)
  raise Lab::AdmissionDenied, "GPU sample unavailable" unless sample.success? && !sample.truncated
  gpu_samples << { "elapsed" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, "devices" => sample.stdout.lines.map(&:strip) }
end
receipt_writer = lambda do |receipt|
  events.write(Lab.encode(receipt.merge("case_id" => current_case, "recorded_at" => Time.now.utc.iso8601(6))) + "\n")
  events.flush
  events.fsync
end
before_generation = lambda do
  raise Lab::BackendUnavailable, "generation forbidden during calibration" if calibration_only
  raise Lab::BackendUnavailable, "qualification budget exhausted" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline || generation_count >= 24
  generation_count += 1
  sample_gpu.call
end
begin
  Timeout.timeout([deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.001].max) do
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
    write.call("baseline.json", { "schema" => "soul.continuity_lab.qwen_qualification.a13", "started_at" => Time.now.utc.iso8601,
      "host" => observer.last_evidence, "file_hashes" => hashes, "props" => props,
      "configs" => configs.transform_values(&:to_h), "settings" => Lab::QwenBrokerSession::V3_SETTINGS.merge("stream" => true),
      "message_profile" => message_profile, "message_guide" => message_guide,
      "execution_profile" => Lab::Config::STREAM_PROFILE, "calibration_only" => calibration_only,
      "bounds" => { "request_seconds" => 60, "event_seconds" => 420, "worker_seconds" => 430, "batch_seconds" => calibration_only ? 120 : 1800, "work_seconds" => calibration_only ? 100 : 1780, "cleanup_reserve_seconds" => 20, "generation_calls" => calibration_only ? 0 : 24 },
      "prompt_version" => Lab::QwenBrokerSession::V4_PROMPT_VERSION, "case_version" => Lab::QualificationCasesA13::VERSION,
      "case_specs" => cases, "code_hashes" =>
        (Dir[File.join(root, "lib/soul_core/continuity_lab/*.{rb,gbnf}")] + [__FILE__, File.join(root, "scripts/continuity-lab-worker.rb")]).to_h { |path| [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest] } })
    configs.each do |group, config|
      states[group] = File.join(output, "worker-#{group}")
      Dir.mkdir(states[group], 0o700)
      store = Lab::Store.create(path: File.join(states[group], "store"), config: config, corpus: Lab::QualificationCasesA13::CORPUS)
      fixtures = []
      write.call("setup-#{group}.json", { "source" => "deterministic_fixture_not_model", "fixtures" => fixtures, "integrity" => store.integrity })
      store.close
      store = nil
    end
    # Tokenizer-only calibration: no expected actions/results enter live journals.
    phase = "tokenizer_calibration"
    cases.each do |spec|
      config = configs.fetch(spec.fetch("id"))
      store = Lab::Store.open(path: File.join(states.fetch(spec.fetch("id")), "store"), config: config)
      lineage = store.snapshot.fetch("lineage_id")
      store.close
      store = nil
      measurements = []
      gate.with_window do
        5.times do |index|
          state = Lab::QualificationCasesA13.expected_state(spec, lineage, index)
          input = Lab::TokenContext.initial(state: state, event_id: "comparison", config: config)
          envelope = Lab.parse(input)
          raise Lab::ValidationError, "sizing fixture byte-trimmed" unless envelope["tool_groups"].length == index
          full_tokens = nil
          loop do
            rendered = client.request("POST", "/apply-template", {
              "messages" => Lab::QwenMessageProjection.messages(Lab.encode(envelope), profile: message_profile),
              "add_generation_prompt" => true, "chat_template_kwargs" => { "enable_thinking" => false }
            }, deadline: deadline)
            prompt = rendered.fetch("prompt")
            raise Lab::ValidationError, "unexpected sizing template" unless prompt.end_with?("<think>\n\n</think>\n\n") && prompt.bytesize <= 32_768
            tokens = client.request("POST", "/tokenize", { "content" => prompt, "add_special" => true, "parse_special" => true }, deadline: deadline).fetch("tokens")
            raise Lab::ValidationError, "invalid sizing tokens" unless tokens.is_a?(Array) && tokens.length.between?(1, 131_072) && tokens.all? { |t| t.is_a?(Integer) && t >= 0 }
            full_tokens ||= tokens.length
            measurements << { "call_index" => index, "input_tokens" => tokens.length,
              "full_input_tokens" => full_tokens, "retained_receipts" => envelope.fetch("execution_receipts").map { |r| r.fetch("call_index") }, "included_groups" => envelope["tool_groups"].map { |g| g["call_index"] },
              "envelope" => Lab.encode(envelope), "prompt_sha256" => Digest::SHA256.hexdigest(prompt), "token_ids_sha256" => Lab.digest(tokens) }
            receipt_writer.call(measurements.last.merge("state" => "calibration_measured", "calibration_case" => spec.fetch("id"),
              "source" => "deterministic_expected_trace_not_model_output"))
            break if tokens.length <= Lab::TokenContext.budget(config)
            raise Lab::ContextBudgetExceeded, "essential sizing fixture overflow" if envelope["tool_groups"].length <= 1
            Lab::ReceiptContext.omit_oldest!(envelope)
          end
        end
      end
      selected = measurements.group_by { |row| row.fetch("call_index") }.values.map(&:last)
      sizing = Lab::QualificationCasesA13.calibration_evidence(spec, selected)
      write.call("sizing-#{spec.fetch("id")}.json", sizing.merge("source" => "deterministic_expected_trace_not_model_output", "measurements" => measurements))
      raise Lab::ValidationError, "intended context contrast not established" unless sizing.fetch("valid")
      puts "SIZED #{spec.fetch("id")}: #{selected.map { |row| row["input_tokens"] }.inspect}"
    end
    phase = "calibration_complete"
    calibration_valid = true
    unless calibration_only
      sample_gpu.call
      cases.each_with_index do |spec, index|
        current_case = format("%02d-%s", index + 1, spec["id"])
        config = configs.fetch(spec["id"])
        state_path = states.fetch(spec["id"])
        store = Lab::Store.open(path: File.join(state_path, "store"), config: config)
        before = store.snapshot
        # Prerequisite status is measured before dispatch. Do not spend inference on
        # chain descendants whose required state was never produced.
        prerequisite = Lab::QualificationScorer.evaluate(event: { "state" => "pending", "calls" => [] }, config: config,
          lineage_id: before["lineage_id"], contract: spec["contract"], before_notes: before["notes"], after_notes: before["notes"])
        store.close
        store = nil
        if prerequisite["reasons"] == ["required_before_notes_missing"]
          results << { "id" => current_case, "group" => spec["id"], "passed" => false, "status" => "unmet_prerequisite",
            "reasons" => prerequisite["reasons"], "calls" => 0, "tools" => [], "omitted_groups" => [], "invalid_actions" => 0 }
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
        outcome = worker.run(request: { "mode" => spec["condition"] == "rollover" ? "qwen_v6_rollover_run" : "qwen_v6_run",
          "create" => false, "event_id" => "comparison", "content" => spec["content"], "corpus" => [] }, broker: broker, admission: gate)
        returned << { "case_id" => current_case, "receipt" => outcome.dig("result", "receipt"), "worker_pid" => outcome["worker_pid"] }
        phase = "postprocessing"
        store = Lab::Store.open(path: File.join(state_path, "store"), config: config)
        after = store.snapshot
        event = after["events"].fetch("comparison")
        score = Lab::QualificationScorer.evaluate(event: event, config: config, lineage_id: after["lineage_id"],
          contract: spec["contract"], before_notes: before["notes"], after_notes: after["notes"])
        results << score.merge("id" => current_case, "group" => spec["id"], "receipt" => outcome["result"]["receipt"], "calls" => broker.calls,
          "tools" => event["calls"].filter_map { |call| Lab::Actions.parse(call["response"].to_s, config)["tool"] },
          "invalid_actions" => event["invalid_count"], "omitted_groups" => event["calls"].flat_map { |call| call.dig("context", "manifest", "omitted_groups") || [] })
        results.last["pair"] = spec.fetch("pair")
        results.last["condition"] = spec.fetch("condition")
        results.last["condition_evidence"] = Lab::QualificationCasesA13.condition_evidence(event, spec)
        results.last["qualified_comparison"] = score["passed"] && results.last["condition_evidence"]["intended_condition_observed"]
        write.call("case-#{index + 1}.json", results.last)
        store.close
        store = nil
        gate.with_window { observer.call }
        sample_gpu.call
        puts "#{score['passed'] ? 'PASS' : 'BEHAVIOR_FAIL'} #{current_case}: #{event['reason']}, calls=#{broker.calls}, #{score['reasons']}"
        break if event["state"] == "blocked_for_human_review" || event["reason"] == "context_budget_exceeded"
      end
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
  write.call("summary.json", { "finished_at" => Time.now.utc.iso8601, "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    "calibration_only" => calibration_only, "calibration_valid" => calibration_valid,
    "generation_calls" => generation_count, "results" => results, "failure" => failure, "idle_verified_at_end" => idle,
    "idle_verified_immediately" => idle_immediately, "idle_settle_seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - settle_started,
    "idle_settle_errors" => settle_errors, "admission_contention" => admission_events,
    "gpu_samples" => gpu_samples, "recorded_cases" => results.length,
    "scored_cases" => results.count { |entry| entry.key?("receipt") }, "passed_cases" => results.count { |entry| entry["passed"] },
    "qualified_comparisons" => results.count { |entry| entry["qualified_comparison"] },
    "attempted_cases" => attempted, "returned_worker_receipts" => returned,
    "unmet_prerequisites" => results.count { |entry| entry["status"] == "unmet_prerequisite" },
    "not_started_cases" => cases.length - attempted.length - results.count { |entry| !entry.key?("receipt") },
    "unscored_cases" => attempted - results.map { |entry| entry["id"] } })
  puts(calibration_only ? "Finished calibration: valid=#{failure.nil? && phase == 'calibration_complete'}, generations=#{generation_count}; idle=#{idle}" : "Finished: #{results.count { |entry| entry['passed'] }}/#{results.length} recorded cases passed; idle=#{idle}")
end
exit(failure || !idle || (!calibration_only && (results.length != cases.length || results.any? { |entry| !entry["qualified_comparison"] })) ? 1 : 0)
