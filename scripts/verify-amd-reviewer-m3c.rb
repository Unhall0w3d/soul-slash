#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "stringio"
require_relative "compare-amd-reviewer-m3c"

Comparison = AmdReviewerComparisonM3c
Cases = AmdReviewerCasesM3c
Protocol = AmdReviewerProtocolM3c

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  puts "- #{label}: #{condition ? 'ok' : 'FAIL'}"
  failures << label unless condition
end
raises = lambda do |klass, message = nil, &operation|
  begin
    operation.call
  rescue klass => error
    message.nil? || error.message.include?(message)
  rescue StandardError
    false
  else
    false
  end
end

def json_payloads(messages)
  messages.select { |message| message["role"] == "user" }.map { |message| JSON.parse(message.fetch("content")) }
end

def recursive_keys(value)
  case value
  when Hash then value.keys + value.values.flat_map { |child| recursive_keys(child) }
  when Array then value.flat_map { |child| recursive_keys(child) }
  else []
  end
end

def claim_check_output(item, packet)
  claims = item.fetch("answer_fields").map do |field|
    status = item.fetch("expected_claims").fetch(field)
    source_value = item.fetch("source_answer").fetch(field)
    citations = if status == "contradicted" || (status == "supported" && source_value.downcase != "unknown")
                  evidence = item.fetch("evidence").first
                  [{ "evidence_id" => evidence.fetch("id"), "quote" => evidence.fetch("text") }]
                else
                  []
                end
    { "field" => field, "source_value" => source_value, "citations" => citations,
      "rationale" => "Fixture status follows the supplied synthetic record.", "status" => status }
  end
  { "review_id" => packet.fetch("review_id"), "claims" => claims }
end

puts "AMD reviewer M3c deterministic protocol and comparison verification:"
cases = Cases.cases
check.call("fresh fixture catalog validates and contains fourteen cases", Cases.validate! && cases.length == 14)

schema_pair_valid = cases.all? do |item|
  packet = Comparison.review_packet(item, item.fetch("source_answer"), "schema-#{item.fetch('id')}", at: 1_800_000_000)
  current = Protocol.schema("current", packet, item)
  findings = Protocol.schema("findings-first", packet, item)
  current_messages = Protocol.messages("current", packet, item)
  findings_messages = Protocol.messages("findings-first", packet, item)
  current.fetch("properties") == findings.fetch("properties") &&
    current.fetch("required").sort == findings.fetch("required").sort &&
    current.fetch("properties").keys.sort == AmdReviewerPilotM2.response_schema.fetch("properties").keys.sort &&
    current.fetch("properties").keys != findings.fetch("properties").keys &&
    findings.fetch("properties").keys == %w[review_id omissions findings verdict] &&
    current_messages == findings_messages
end
check.call("A and B share identical messages and field schema, differing only in schema order", schema_pair_valid)

item = cases.find { |candidate| candidate.fetch("category") == "semantic" }
packet = Comparison.review_packet(item, item.fetch("source_answer"), "protocol-binding", at: 1_800_000_000)
valid_claims = claim_check_output(item, packet)
valid_claim_review = Protocol.validate("claim-checks", valid_claims, packet, item)
missing_claim = Marshal.load(Marshal.dump(valid_claims))
missing_claim["claims"].pop
duplicate_claim = Marshal.load(Marshal.dump(valid_claims))
duplicate_claim["claims"][-1] = Marshal.load(Marshal.dump(duplicate_claim["claims"].first))
foreign_field = Marshal.load(Marshal.dump(valid_claims))
foreign_field["claims"][0]["field"] = "not_a_requested_field"
tampered_value = Marshal.load(Marshal.dump(valid_claims))
tampered_value["claims"][0]["source_value"] = "altered-source"
wrong_identity = Marshal.load(Marshal.dump(valid_claims))
wrong_identity["review_id"] = "another-review"
check.call("claim-check output binds exact source values and review identity with complete unique field coverage", valid_claim_review.fetch("review_id") == packet.fetch("review_id") &&
  valid_claim_review.fetch("claims").length == item.fetch("answer_fields").length &&
  raises.call(Protocol::InvalidReview, "incomplete claim coverage") { Protocol.validate("claim-checks", missing_claim, packet, item) } &&
  raises.call(Protocol::InvalidReview, "duplicate or missing claim field") { Protocol.validate("claim-checks", duplicate_claim, packet, item) } &&
  raises.call(Protocol::InvalidReview, "claim does not bind source field/value") { Protocol.validate("claim-checks", foreign_field, packet, item) } &&
  raises.call(Protocol::InvalidReview, "claim does not bind source field/value") { Protocol.validate("claim-checks", tampered_value, packet, item) } &&
  raises.call(Protocol::InvalidReview, "wrong review identity") { Protocol.validate("claim-checks", wrong_identity, packet, item) } &&
  raises.call(Protocol::InvalidReview, "unknown arm") { Protocol.validate("unknown-arm", valid_claims, packet, item) })

quote_tests = false
contradiction_case = cases.find { |candidate| candidate.fetch("expected_claims").value?("contradicted") }
contradiction_packet = Comparison.review_packet(contradiction_case, contradiction_case.fetch("source_answer"), "quote-binding", at: 1_800_000_000)
contradiction_output = claim_check_output(contradiction_case, contradiction_packet)
required_claim = contradiction_output.fetch("claims").find { |claim| claim.fetch("status") == "contradicted" }
paraphrase = Marshal.load(Marshal.dump(contradiction_output))
paraphrase_claim = paraphrase.fetch("claims").find { |claim| claim.fetch("status") == "contradicted" }
paraphrase_claim.fetch("citations").first["quote"] = "A paraphrase of the record"
unknown_evidence_id = Marshal.load(Marshal.dump(contradiction_output))
unknown_evidence_id.fetch("claims").find { |claim| claim.fetch("status") == "contradicted" }.fetch("citations").first["evidence_id"] = "not-supplied"
empty_positive_citation = Marshal.load(Marshal.dump(contradiction_output))
empty_positive_citation.fetch("claims").find { |claim| claim.fetch("status") == "contradicted" }["citations"] = []
unsupported_case = cases.find { |candidate| candidate.fetch("expected_verdict") == "insufficient_evidence" }
unsupported_packet = Comparison.review_packet(unsupported_case, unsupported_case.fetch("source_answer"), "unknown-citation", at: 1_800_000_000)
unsupported_output = claim_check_output(unsupported_case, unsupported_packet)
unknown_supported_case = cases.find do |candidate|
  candidate.fetch("expected_claims").any? { |field, status| status == "supported" && candidate.fetch("source_answer").fetch(field).downcase == "unknown" }
end
unknown_supported_packet = Comparison.review_packet(unknown_supported_case, unknown_supported_case.fetch("source_answer"), "explicit-unknown", at: 1_800_000_000)
unknown_supported_output = claim_check_output(unknown_supported_case, unknown_supported_packet)
quote_tests = required_claim && Protocol.validate("claim-checks", contradiction_output, contradiction_packet, contradiction_case) &&
  raises.call(Protocol::InvalidReview, "quote does not match supplied source") { Protocol.validate("claim-checks", paraphrase, contradiction_packet, contradiction_case) } &&
  raises.call(Protocol::InvalidReview, "quote does not match supplied source") { Protocol.validate("claim-checks", unknown_evidence_id, contradiction_packet, contradiction_case) } &&
  raises.call(Protocol::InvalidReview, "positive judgment lacks citation") { Protocol.validate("claim-checks", empty_positive_citation, contradiction_packet, contradiction_case) } &&
  Protocol.validate("claim-checks", unsupported_output, unsupported_packet, unsupported_case) &&
  Protocol.validate("claim-checks", unknown_supported_output, unknown_supported_packet, unknown_supported_case)
check.call("citations require exact supplied quotes and known IDs; empty citations are limited to non-positive claims", quote_tests)

all_statuses = Protocol::STATUS.repeated_permutation(1).to_a + Protocol::STATUS.repeated_permutation(2).to_a + Protocol::STATUS.repeated_permutation(3).to_a
aggregate_ok = all_statuses.all? do |statuses|
  expected = if statuses.include?("contradicted") && statuses.include?("insufficient_evidence")
               "mixed"
             elsif statuses.include?("contradicted")
               "contradicted"
             elsif statuses.include?("insufficient_evidence")
               "insufficient_evidence"
             else
               "supported"
             end
  Protocol.aggregate(statuses) == expected
end
check.call("aggregate covers every one-, two-, and three-field status combination", aggregate_ok &&
  raises.call(Protocol::InvalidReview, "invalid or empty statuses") { Protocol.aggregate([]) } &&
  raises.call(Protocol::InvalidReview, "invalid or empty statuses") { Protocol.aggregate(["unknown-status"]) })

format_case = cases.find { |candidate| candidate.fetch("category") == "format_only" }
format_packet = Comparison.review_packet(format_case, format_case.fetch("source_answer"), "format-review", at: 1_800_000_000)
format_output = claim_check_output(format_case, format_packet)
format_result = Protocol.validate("claim-checks", format_output, format_packet, format_case)
format_only_findings = format_result.fetch("format_findings")
check.call("required-unit omissions appear as deterministic format findings without changing semantic verdict", format_result.fetch("verdict") == "supported" &&
  format_only_findings.length == 1 && format_only_findings.first.fetch("kind") == "format_only" &&
  format_only_findings.first.fetch("field") == format_case.fetch("answer_fields").first)

message_packets = cases.flat_map do |case_data|
  source = case_data.fetch("source_answer")
  task_variants = [Comparison.task_messages(case_data, source),
    Comparison.task_messages(case_data, source, review: { "verdict" => case_data.fetch("expected_verdict") })]
  packet = Comparison.review_packet(case_data, source, "leak-#{case_data.fetch('id')}", at: 1_800_000_000)
  [*task_variants, *Protocol::ARMS.map { |arm| Protocol.messages(arm, packet, case_data) }]
end
no_oracle = message_packets.all? do |messages|
  payloads = json_payloads(messages)
  recursive_keys(payloads).none? { |key| %w[oracle expected_claims expected_verdict category].include?(key) } &&
    cases.none? { |case_data| JSON.generate(messages).include?(JSON.generate(case_data.fetch("oracle"))) }
end
check.call("task and all three review arms exclude oracle and expected-label fields", no_oracle)

class FakeM3cComparison < AmdReviewerComparisonM3c
  attr_reader :calls, :saved, :raw_reviews, :model_counts

  def initialize(invalid_label: nil)
    @cases = AmdReviewerCasesM3c.cases
    @rows, @saved, @calls, @raw_reviews = [], {}, [], {}
    @model_counts = Hash.new(0)
    @generation_count = 0
    @skipped_revisions = 0
    @protocol_revision = "fake-protocol"
    @invalid_label = invalid_label
  end

  def infer(model, messages, _schema, label)
    @generation_count += 1
    @model_counts[model] += 1
    @calls << [model, label, messages]
    payload = json_payloads(messages).fetch(0)
    if label.end_with?("-control")
      task = payload.fetch("task")
      item = @cases.find { |candidate| candidate.fetch("question") == task.fetch("question") }
      raise "fake control cannot identify its case" unless item
      return item.fetch("oracle")
    end

    if label.end_with?("-review")
      packet = payload.fetch("packet")
      item = @cases.find { |candidate| candidate.fetch("question") == packet.fetch("question") }
      raise "fake reviewer cannot identify its case" unless item
      arm = label.match(/\Acase-\d+-(current|findings-first|claim-checks)-review\z/)[1]
      raw = if arm == "claim-checks"
              claim_check_output(item, packet)
            else
              { "review_id" => packet.fetch("review_id"), "verdict" => item.fetch("expected_verdict"), "findings" => [], "omissions" => [] }
            end
      raw = raw.merge("review_id" => "tampered-review-id") if label == @invalid_label
      @raw_reviews[label] = raw
      return raw
    end

    revision = label.match(/\Acase-\d+-(current|findings-first|claim-checks)-revision\z/)
    raise "unexpected fake Qwen request #{label}" unless model == "qwen" && revision
    item_payload = payload.fetch("task")
    item = @cases.find { |candidate| candidate.fetch("question") == item_payload.fetch("question") }
    raise "fake revision cannot identify its case" unless item
    item.fetch("oracle")
  end

  def save(name, value)
    @saved[name] = value
  end
end

fake = FakeM3cComparison.new
capture_output = lambda do |&operation|
  prior = $stdout
  $stdout = StringIO.new
  operation.call
ensure
  $stdout = prior
end
capture_output.call { fake.compare_cases }
score_data = fake.saved.fetch("scores.json")
rotation_ok = score_data.fetch("rows").each_with_index.all? do |row, index|
  row.fetch("arms").keys == Protocol::ARMS.rotate(index % Protocol::ARMS.length)
end
raw_binding_ok = score_data.fetch("rows").all? do |row|
  row.fetch("arms").all? do |arm, result|
    receipt = result.fetch("review_result")
    label = "case-%02d-%s-review" % [score_data.fetch("rows").index(row) + 1, arm]
    packet = fake.saved.fetch("#{label}-packet.json")
    receipt.fetch("raw_review") == fake.raw_reviews.fetch(label) &&
      receipt.fetch("source_revision") == packet.fetch("source_revision") &&
      receipt.fetch("evidence_revision") == packet.fetch("evidence_revision") && receipt.fetch("status") == "completed"
  end
end
revision_binding_ok = fake.calls.select { |model, label, _| model == "qwen" && label.end_with?("-revision") }.all? do |_model, label, messages|
  payload = json_payloads(messages).fetch(0)
  case_index = label[/\Acase-(\d+)-/, 1].to_i - 1
  item = cases.fetch(case_index)
  arm = label.match(/\Acase-\d+-(current|findings-first|claim-checks)-revision\z/)[1]
  row_arm = score_data.fetch("rows").fetch(case_index).fetch("arms").fetch(arm)
  payload.fetch("original_answer") == item.fetch("source_answer") &&
    payload.fetch("attributed_unendorsed_review") == row_arm.fetch("review_result").fetch("review")
end
check.call("fake comparison uses 98 calls (42 AMD, 56 Qwen), rotates arms, and binds raw reviews plus independent source-based revisions", fake.model_counts == { "amd" => 42, "qwen" => 56 } &&
  fake.instance_variable_get(:@generation_count) == 98 && rotation_ok && raw_binding_ok && revision_binding_ok && score_data.fetch("rows").length == 14)

invalid = FakeM3cComparison.new(invalid_label: "case-01-current-review")
capture_output.call { invalid.compare_cases }
invalid_scores = invalid.saved.fetch("scores.json")
skipped = invalid_scores.fetch("rows").flat_map { |row| row.fetch("arms").map { |arm, result| [row.fetch("id"), arm, result] } }
invalid_once = skipped.count { |_id, _arm, result| result.fetch("revision").fetch("status") == "skipped_invalid_review" }
check.call("one invalid review skips only its own revision and keeps the 98 budget accounting", invalid_once == 1 &&
  invalid.instance_variable_get(:@generation_count) == 97 && invalid.instance_variable_get(:@skipped_revisions) == 1 &&
  invalid.instance_variable_get(:@generation_count) + invalid.instance_variable_get(:@skipped_revisions) == Comparison::LIMIT &&
  invalid.model_counts == { "amd" => 42, "qwen" => 55 } && invalid_scores.fetch("rows").length == 14)
invalid_summary = invalid.saved.fetch("summary.json")
control_correct_for_skipped = invalid_scores.fetch("rows").first.dig("control", "score", "correct") == true
check.call("skipped revision of a control-correct case is counted as a loss to control", control_correct_for_skipped &&
  invalid_summary.fetch("arms").fetch("current").fetch("losses_to_control") >= 1 &&
  invalid_summary.fetch("arms").fetch("current").fetch("revision_statuses").fetch("skipped_invalid_review") == 1)

ceiling = Comparison.allocate
ceiling.instance_variable_set(:@generation_count, Comparison::LIMIT)
transport_called = false
ceiling.define_singleton_method(:http) { |*| transport_called = true; raise "transport reached above ceiling" }
ceiling_rejected = raises.call(Comparison::Stop, "M3C generation budget exceeded") do
  ceiling.infer("qwen", [], {}, "at-ceiling")
end
wrong_sentinel = Comparison.allocate
wrong_sentinel_rejected = raises.call(Comparison::Stop, "unexpected M3C gate invocation") do
  wrong_sentinel.run("wrong-command", timeout_seconds: Comparison::MAX_SECONDS)
end
wrong_timeout = Comparison.allocate
wrong_timeout_rejected = raises.call(Comparison::Stop, "unexpected M3C gate invocation") do
  wrong_timeout.run("fixed-m3c-comparison", timeout_seconds: Comparison::MAX_SECONDS - 1)
end
check.call("98-call ceiling blocks before transport and run rejects wrong sentinel or timeout", ceiling_rejected && !transport_called && wrong_sentinel_rejected && wrong_timeout_rejected)

runner_source = File.read(File.expand_path("compare-amd-reviewer-m3c.rb", __dir__))
inherited_safety = Comparison.ancestors.include?(AmdReviewerComparisonM3b) &&
  Comparison.method(:check_resources!).owner == AmdReviewerComparisonM3b.singleton_class &&
  Comparison.instance_method(:start_server).owner == AmdReviewerComparisonM3b &&
  runner_source.include?("AmdReviewerComparisonM3.instance_method(:infer).bind_call(self, model, messages, schema, label)") &&
  runner_source.include?("super(\"fixed-m3b-v2-comparison\", timeout_seconds: timeout_seconds, **options)")
check.call("M3C retains inherited resource/server checks and delegates inference plus bounded v2 lifecycle", inherited_safety)

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
