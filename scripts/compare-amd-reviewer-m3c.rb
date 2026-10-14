#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "compare-amd-reviewer-m3b"
require_relative "support/amd_reviewer_cases_m3c"
require_relative "support/amd_reviewer_protocol_m3c"

# Detached qualification. Historical harnesses and production contracts stay frozen.
class AmdReviewerComparisonM3c < AmdReviewerComparisonM3b
  FreshCases = AmdReviewerCasesM3c
  Protocol = AmdReviewerProtocolM3c
  LIMIT = 98
  BRIEF = File.join(ROOT, "docs/soul/AMD_REVIEWER_M3C_BRIEF.md")
  INPUTS = [File.expand_path(__FILE__), BRIEF,
    File.join(__dir__, "support/amd_reviewer_cases_m3c.rb"),
    File.join(__dir__, "support/amd_reviewer_protocol_m3c.rb")].freeze

  def initialize
    super("qwen35")
    @skipped_revisions = 0
  end

  def preservation
    result = super
    result["hashes"].merge!(INPUTS.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] })
    result
  end

  def infer(model, messages, schema, label)
    raise Stop, "M3C generation budget exceeded" if @generation_count >= LIMIT
    # Use the unchanged 100-call inference body, not M3B's experiment-specific 48
    # ceiling. All dynamic sampler, template, resource and identity checks remain.
    AmdReviewerComparisonM3.instance_method(:infer).bind_call(self, model, messages, schema, label)
  end

  def self.task_messages(item, original, review: nil)
    data = { "task" => FreshCases.public_case(item), "original_answer" => original }
    if review
      data["attributed_unendorsed_review"] = review
      data["instruction"] = "Return a final answer. Correct errors only when supported by the task evidence; preserve a correct original. Review visibility does not make the review true."
    else
      data["instruction"] = "Reconsider the original answer using only the task evidence. Return a final answer; correct errors supported by evidence and preserve a correct original. No reviewer feedback is supplied."
    end
    [{ "role" => "system", "content" => ANSWER_INSTRUCTION }, { "role" => "user", "content" => JSON.generate(data) }]
  end

  def self.review_packet(item, answer, id, at: Time.now.to_i)
    packet = super
    packet["source_event_id"] = packet.fetch("source_event_id").sub(/\Am3b-/, "m3c-")
    packet["evidence"].each { |e| e["provenance"] = "synthetic-m3c-comparison" }
    packet["evidence_revision"] = Contract.digest(packet["evidence"])
    Contract.request!(packet)
  end

  def self.scored_answer(answer, item)
    { "status" => "completed", "answer" => answer, "score" => FreshCases.score(answer, item) }
  rescue ArgumentError => e
    { "status" => "invalid_answer", "answer" => answer, "error" => e.message }
  end

  def review_arm(arm, item, label)
    packet = self.class.review_packet(item, item.fetch("source_answer"), label)
    save("#{label}-packet.json", packet)
    raw = infer("amd", Protocol.messages(arm, packet, item), Protocol.schema(arm, packet, item), label)
    receipt = { "arm" => arm, "source_revision" => packet["source_revision"], "evidence_revision" => packet["evidence_revision"],
      "raw_review" => raw, "actual_key_order" => raw.is_a?(Hash) ? raw.keys : nil }
    begin
      receipt["review"] = Protocol.validate(arm, raw, packet, item)
      receipt["status"] = "completed"
    rescue Protocol::InvalidReview => e
      receipt.merge!("status" => "invalid_review", "error" => e.message)
    end
    save("#{label}-validation.json", receipt)
    receipt
  end

  def compare_cases
    @cases.each_with_index do |item, index|
      id = format("case-%02d", index + 1)
      original = item.fetch("source_answer")
      control = infer("qwen", self.class.task_messages(item, original), self.class.answer_schema(item), "#{id}-control")
      row = { "id" => item["id"], "category" => item["category"], "expected_verdict" => item["expected_verdict"],
        "expected_claims" => item["expected_claims"], "original" => original, "baseline" => FreshCases.score(original, item),
        "control" => self.class.scored_answer(control, item), "arms" => {} }
      Protocol::ARMS.rotate(index % Protocol::ARMS.size).each do |arm|
        review = review_arm(arm, item, "#{id}-#{arm}-review")
        result = { "review_result" => review }
        if review["status"] == "completed"
          output = infer("qwen", self.class.task_messages(item, original, review: review.fetch("review")),
            self.class.answer_schema(item), "#{id}-#{arm}-revision")
          result["revision"] = self.class.scored_answer(output, item)
        else
          @skipped_revisions += 1
          result["revision"] = { "status" => "skipped_invalid_review" }
        end
        row["arms"][arm] = result
      end
      @rows << row
      save("#{id}-scores.json", row)
      puts JSON.generate({ "case" => index + 1, "generations" => @generation_count,
        "control" => row.dig("control", "score", "correct"),
        "arms" => row["arms"].transform_values { |r| { "review" => r.dig("review_result", "status"),
          "verdict" => r.dig("review_result", "review", "verdict"), "answer" => r.dig("revision", "score", "correct") } } })
    end
    raise Stop, "incomplete comparison" unless @rows.length == 14 && @generation_count + @skipped_revisions == LIMIT
    save("scores.json", { "rows" => @rows, "generations" => @generation_count,
      "skipped_revisions" => @skipped_revisions, "protocol_revision" => @protocol_revision })
    save("summary.json", self.class.summarize(@rows))
  end

  def self.summarize(rows)
    semantic = rows.select { |r| r["category"] == "semantic" }
    { "cases" => rows.length, "semantic_cases" => semantic.length,
      "source_correct" => rows.count { |r| r.dig("baseline", "correct") },
      "control_correct" => rows.count { |r| r.dig("control", "score", "correct") },
      "arms" => Protocol::ARMS.to_h do |arm|
        branch = ->(row) { row.fetch("arms").fetch(arm) }
        verdict = ->(row) { branch.call(row).dig("review_result", "review", "verdict") }
        correct = ->(row) { branch.call(row).dig("revision", "score", "correct") == true }
        [arm, { "semantic_verdict_correct" => semantic.count { |r| verdict.call(r) == r["expected_verdict"] },
          "verdict_correct_all" => rows.count { |r| verdict.call(r) == r["expected_verdict"] },
          "semantic_confusion" => semantic.group_by { |r| r["expected_verdict"] }.transform_values { |group| group.map { |r| verdict.call(r) || "invalid_review" }.tally },
          "supported_false_verdict" => semantic.count { |r| r["expected_verdict"] == "supported" && verdict.call(r) && verdict.call(r) != "supported" },
          "supported_nonempty_findings" => arm == "claim-checks" ? nil : semantic.count { |r| r["expected_verdict"] == "supported" && !branch.call(r).dig("review_result", "review", "findings").to_a.empty? },
          "invalid_reviews" => rows.count { |r| branch.call(r).dig("review_result", "status") == "invalid_review" },
          "revised_correct" => rows.count { |r| correct.call(r) },
          "corrected_source" => rows.count { |r| !r.dig("baseline", "correct") && correct.call(r) },
          "spoiled_source" => rows.count { |r| r.dig("baseline", "correct") && branch.call(r).dig("revision", "status") == "completed" && !correct.call(r) },
          "wins_over_control" => rows.count { |r| r.dig("control", "score", "correct") == false && correct.call(r) },
          "unique_corrections_over_control" => rows.count { |r| !r.dig("baseline", "correct") && r.dig("control", "score", "correct") == false && correct.call(r) },
          "losses_to_control" => rows.count { |r| r.dig("control", "score", "correct") == true && !correct.call(r) },
          "format_correct" => rows.count { |r| r["category"] == "format_only" && correct.call(r) },
          "revision_statuses" => rows.map { |r| branch.call(r).dig("revision", "status") }.tally }]
      end }
  end

  def run(*argv, timeout_seconds:, **options)
    raise Stop, "unexpected M3C gate invocation" unless argv == ["fixed-m3c-comparison"] && timeout_seconds == MAX_SECONDS
    super("fixed-m3b-v2-comparison", timeout_seconds: timeout_seconds, **options)
  end

  def execute
    File.umask(0o077)
    FreshCases.validate!
    @cases = FreshCases.cases
    parent = File.join(ROOT, "Soul/runtime/qualification")
    raise Stop, "unsafe evidence parent" unless File.realpath(parent) == parent && File.stat(parent).uid == Process.uid
    @output = Dir.mktmpdir("amd-reviewer-m3c-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-", parent)
    puts "EVIDENCE #{@output}"
    @before = preservation
    @initial = snapshot
    core = Lab.parse(File.read(File.join(ROOT, "Soul/runtime/model_runtime/core_selection.json"))).fetch("active_core_id")
    raise Stop, "unsuitable Core" unless %w[amd-free dev music].include?(core)
    pid = @before.fetch("qwen")[/^MainPID=(\d+)$/, 1] or raise Stop, "Qwen PID missing"
    @observer = Continuity::QwenHostObserver.new(root: ROOT, client: @qwen, expected_pid: Integer(pid), expected_core: core)
    raise Stop, "unsupported page size" unless command("getconf", "PAGESIZE").strip == "4096"
    self.class.check_resources!(@initial, @initial)
    path = @asset.fetch("path")
    stat = File.lstat(path)
    raise Stop, "unsafe model path" unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.uid == Process.uid && File.realpath(path) == path
    raise Stop, "model hash mismatch" unless stat.size == @asset["size"] && Digest::SHA256.file(path).hexdigest == @asset["sha256"]
    qwen_hash = Digest::SHA256.file(Continuity::QwenHostObserver::MODEL).hexdigest
    raise Stop, "Qwen weights changed" unless qwen_hash == "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785"
    libs = Dir.glob("/usr/lib/ollama/*.so*").select { |p| File.file?(p) && !File.symlink?(p) } + [SERVER, PLUGIN, Continuity::QwenHostObserver::SERVER]
    @runtime_hashes = libs.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
    @api_key = SecureRandom.hex(32)
    @key_path = File.join(@output, "local-api-key")
    File.open(@key_path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) { |f| f.puts(@api_key) }
    protocol = { "schema" => "soul.reviewer.comparison.m3c.v1", "candidate" => @candidate_id, "asset" => @asset,
      "cases" => @cases, "qwen_model_sha256" => qwen_hash, "runtime_hashes" => @runtime_hashes,
      "preservation" => @before, "max_generations" => LIMIT, "max_seconds" => MAX_SECONDS, "initial" => @initial,
      "arms" => Protocol::ARMS, "arm_order" => "rotated_by_case_index", "source_answers" => "synthetic_seeds_not_sampled_qwen",
      "sampler" => self.class.sampler(nil), "scoring" => "exact_fields_casefold_trim_only",
      "thermal_abort_celsius" => THERMAL_ABORT, "monitor_interval_seconds" => MONITOR_SECONDS,
      "cooldown" => { "minimum_seconds" => 3, "edge_max" => 55, "junction_max" => 70, "timeout_seconds" => 30 },
      "primary_task_contract" => "unchanged", "visibility" => "detached_not_available_to_soul" }
    @protocol_revision = Contract.digest(protocol)
    save("protocol.json", protocol.merge("protocol_revision" => @protocol_revision))
    guard = GuardedComparisonLeases.new(store: SoulCore::ModelRuntimeLeaseStore.new(root: ROOT), pilot: self)
    result = SoulCore::ExternalAmdWorkloadGate.new(root: ROOT, runner: self, leases: guard).run(
      command: ["fixed-m3c-comparison"], timeout_seconds: MAX_SECONDS, min_free_bytes: 11 * GIB)
    save("gate-result.json", result)
    puts JSON.generate(result)
    result["ok"]
  rescue StandardError, SignalException => e
    save("failure.json", { "error" => e.class.name, "message" => e.message, "completed_cases" => @rows.length,
      "generations" => @generation_count, "unsettled" => unsettled? }) if @output
    warn "FAILED #{e.class}: #{e.message}"
    false
  ensure
    stop_server
    if @output && @before
      after = preservation
      runtime_unchanged = !@runtime_hashes || @runtime_hashes.all? { |p, sha| Digest::SHA256.file(p).hexdigest == sha }
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
      retained = leases.with_control_lock { leases.leases_for_quiescent_admission_unlocked }
      gone = retained.none? { |l| l["pid"] == Process.pid && l["provider_id"] == "external.codex.amd" }
      save("preservation.json", { "unchanged" => @before == after, "before" => @before, "after" => after,
        "runtime_unchanged" => runtime_unchanged, "own_lease_gone" => gone, "qwen_request_unsettled" => @qwen_inflight,
        "endpoint_closed" => port_closed?, "final_snapshot" => snapshot })
      raise Stop, "baseline/runtime/lease closeout failed" unless @before == after && runtime_unchanged && gone && !@qwen_inflight && port_closed?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Use --approved-m3c-comparison" unless ARGV == ["--approved-m3c-comparison"]
  $stdout.sync = true
  Signal.trap("TERM") { raise Interrupt, "termination requested" }
  exit(AmdReviewerComparisonM3c.new.execute ? 0 : 1)
end
