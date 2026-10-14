#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "compare-amd-reviewer-m3"

Comparison = AmdReviewerComparisonM3
Cases = Comparison::Cases
Contract = Comparison::Contract
Lab = Comparison::Lab

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

class FakeQwen
  attr_accessor :slots, :final, :request_log, :completion_payload, :rendered_prompt, :tokens

  def initialize
    @slots = [{ "is_processing" => false, "n_ctx" => 4096 }]
    @final = { "stop" => true, "truncated" => false, "stop_type" => "eos",
               "tokens_evaluated" => 2, "content" => '{"field":"fixture"}' }
    @request_log = []
    @rendered_prompt = "synthetic rendered prompt"
    @tokens = [11, 12]
  end

  def request(method, path, body = nil, deadline:)
    @request_log << [method, path, body, deadline]
    return @slots if path == "/slots"
    return { "prompt" => @rendered_prompt } if path == "/apply-template"
    return { "tokens" => @tokens } if path == "/tokenize"
    raise "unexpected fake Qwen route #{path}"
  end

  def stream_completion(payload, deadline:, on_progress:)
    @completion_payload = payload
    on_progress.call({ "fragment" => { "content" => "{" } })
    @final
  end
end

class ComparisonHarness < Comparison
  attr_reader :calls, :saved, :originals, :revision_sources, :branch_review_order, :messages_seen

  def initialize
    super
    @calls = []
    @saved = {}
    @originals = {}
    @revision_sources = []
    @branch_review_order = Hash.new { |hash, key| hash[key] = [] }
    @messages_seen = []
  end

  def answer(model, item, label, original: nil, review: nil)
    @calls << [:answer, model, item.fetch("id"), label]
    messages = self.class.answer_messages(item, original: original, review: review)
    @messages_seen.concat(messages.map { |message| message.fetch("content") })
    if label.end_with?("-original")
      result = item.fetch("answer_fields").to_h { |field| [field, "fixture original"] }
      @originals[item.fetch("id")] = result
      return result
    end
    if label.end_with?("-independent")
      raise "evidence-first answer received source answer" if original || review
      return item.fetch("answer_fields").to_h { |field| [field, "fixture independent"] }
    end
    if original
      @revision_sources << [item.fetch("id"), label, original]
      raise "revision did not receive shared original" unless original.equal?(@originals.fetch(item.fetch("id")))
    end
    item.fetch("answer_fields").to_h { |field| [field, "fixture revision"] }
  end

  def review(model, item, original, label, independent: nil)
    @calls << [:review, model, item.fetch("id"), label]
    @messages_seen.concat(self.class.review_messages(self.class.review_packet(item, original, label, at: 1_800_000_000), independent: independent).map { |message| message.fetch("content") })
    branch = label[/\Acase-\d+-(self|amd|evidence-first)-review\z/, 1]
    @branch_review_order[item.fetch("id")] << branch if branch
    packet = self.class.review_packet(item, original, label, at: 1_800_000_000)
    { "review_id" => packet.fetch("review_id"), "verdict" => "supported", "findings" => [], "omissions" => [] }
  end

  def save(name, value)
    @saved[name] = value
  end

  def qwen_observe!
    true
  end

  def now
    @clock || 0.0
  end

  def sleep(seconds)
    @clock = now + seconds
  end
end

class InferenceHarness < ComparisonHarness
  def initialize
    super
    @qwen = FakeQwen.new
    @protocol_revision = "fixture-protocol"
  end

  def qwen_observe!
    true
  end
end

class CooldownHarness < ComparisonHarness
  attr_reader :observed_samples

  def initialize(samples:, fallback:)
    super()
    @clock = 0.0
    @cooldown_samples = samples.dup
    @fallback_sample = fallback
    @observed_samples = []
    @initial = self.class.resource_sample(edge: 54, junction: 69)
  end

  def self.resource_sample(edge:, junction:)
    { "temperatures" => { "edge" => edge, "junction" => junction },
      "vram_total" => 16 * Comparison::GIB, "vram_used" => 8 * Comparison::GIB,
      "memory" => { "MemAvailable" => 16 * Comparison::GIB },
      "paging_pages" => { "pswpout" => 100 } }
  end

  def snapshot
    sample = @cooldown_samples.shift || @fallback_sample
    @observed_samples << sample
    sample
  end
end

def json_payloads(messages)
  messages.select { |message| message["role"] == "user" }.map { |message| JSON.parse(message.fetch("content")) }
end

puts "AMD reviewer M3 deterministic comparison boundary verification:"

argv_name = "amd-reviewer-m2-m3-cooldown-test"
base_argv = AmdReviewerPilotM2.argv(argv_name)
expected_argv = base_argv.dup
expected_argv[expected_argv.index("--batch-size") + 1] = "128"
expected_argv[expected_argv.index("--ubatch-size") + 1] = "32"
actual_argv = Comparison.argv(argv_name)
check.call("lower-load argv changes only batch 128 and ubatch 32", actual_argv == expected_argv &&
  actual_argv[actual_argv.index("--batch-size") + 1] == "128" &&
  actual_argv[actual_argv.index("--ubatch-size") + 1] == "32")

frozen_case_digest = "sha256:803e86da034c6e75ef8b20432aa1faa06c1e8bc781ce707c4c48481f9d7bda98"
frozen_cases = Cases.cases
seeded_scores = frozen_cases.map { |case_data| Cases.score(case_data.fetch("seeded_answer"), case_data).fetch("correct") }
check.call("frozen case and exact scoring protocol digest remains unchanged", Cases.validate! &&
  Contract.digest(frozen_cases) == frozen_case_digest && seeded_scores.count(true) == 5 && seeded_scores.count(false) == 5 &&
  Cases.score({ "total_mass" => "17.5 kg" }, frozen_cases.find { |case_data| case_data.fetch("id") == "kiln-batch-total" }).fetch("correct") &&
  !Cases.score({ "total_mass" => "17.50 kg" }, frozen_cases.find { |case_data| case_data.fetch("id") == "kiln-batch-total" }).fetch("correct"))

public_isolation = Cases.cases.all? do |item|
  answer = { "field" => "fixture original" }
  packet = Comparison.review_packet(item, answer, "isolation-#{item.fetch('id')}", at: 1_800_000_000)
  independent = { "field" => "fixture independent" }
  packets = [
    *json_payloads(Comparison.answer_messages(item)),
    *json_payloads(Comparison.answer_messages(item, original: answer, review: { "verdict" => "supported" })),
    *json_payloads(Comparison.review_messages(packet)),
    *json_payloads(Comparison.review_messages(packet, independent: independent))
  ]
  packets.all? do |payload|
    json = JSON.generate(payload)
    (json + JSON.generate(payload.keys)). !~ /(?:oracle|seeded_answer|seeded_verdict)/
  end
end
check.call("oracle and seed structures are absent from all public answer/review message variants", public_isolation)

item = Cases.cases.first
answer = { "retention_period" => "fixture value", "revision" => "fixture revision" }
packet = Comparison.review_packet(item, answer, "binding-check", at: 1_800_000_000)
valid_packet = Contract.request!(packet)
tampered_source = Contract.copy(packet).merge("source_answer" => '{"revision":"changed"}')
tampered_evidence = Contract.copy(packet)
tampered_evidence["evidence"][0]["text"] = "changed evidence"
check.call("review packet binds source and evidence digests and rejects tampering",
           packet["source_revision"] == Contract.text_digest(packet["source_answer"]) &&
             packet["evidence_revision"] == Contract.digest(packet["evidence"]) &&
             valid_packet == packet &&
             raises.call(Lab::ValidationError, "revision mismatch") { Contract.request!(tampered_source) } &&
             raises.call(Lab::ValidationError, "evidence text digest mismatch") { Contract.request!(tampered_evidence) })

sampler = Comparison.sampler({ "type" => "object" })
fixed_sampler = sampler == { "stream" => true, "n_predict" => 768, "temperature" => 0.05,
  "top_p" => 1.0, "top_k" => 0, "min_p" => 0.0, "seed" => 4242,
  "repeat_penalty" => 1.0, "cache_prompt" => false, "json_schema" => { "type" => "object" } }
check.call("sampler and generation ceilings remain fixed", fixed_sampler && Comparison::MAX_GENERATIONS == 100 && Comparison::MAX_SECONDS == 1800)

window = [{ "pid" => 77, "provider_id" => "external.codex.amd", "resource_group" => "amd-vulkan-generation" }]
check.call("AMD admission accepts only this exact retained lease window",
           Comparison.allowed_window!(window, 77).nil? &&
             raises.call(Comparison::Stop, "missing own AMD lease") { Comparison.allowed_window!([], 77) } &&
             raises.call(Comparison::Stop, "retained foreign") { Comparison.allowed_window!(window + [{ "pid" => 78 }], 77) } &&
             raises.call(Comparison::Stop, "missing own AMD lease") { Comparison.allowed_window!(window, 78) } &&
             raises.call(Comparison::Stop, "retained foreign") { Comparison.allowed_window!([window.first.merge("provider_id" => "other")], 77) })

lease_store = Class.new do
  attr_reader :released
  def release(id) = (@released = id)
end.new
lease_pilot = ComparisonHarness.new
guard = Comparison::GuardedComparisonLeases.new(store: lease_store, pilot: lease_pilot)
lease_pilot.instance_variable_set(:@child, 42)
child_blocked = raises.call(Comparison::Stop, "request or child unconfirmed") { guard.release("fixture-lease") }
lease_pilot.instance_variable_set(:@child, nil)
lease_pilot.instance_variable_set(:@qwen_inflight, true)
request_blocked = raises.call(Comparison::Stop, "request or child unconfirmed") { guard.release("fixture-lease") }
lease_pilot.instance_variable_set(:@qwen_inflight, false)
released = guard.release("fixture-lease")
check.call("guarded lease release blocks while an owned child remains", child_blocked)
check.call("guarded lease release blocks while a Qwen request remains inflight", request_blocked)
check.call("guarded lease release succeeds after both activities settle", released == "fixture-lease" && lease_store.released == "fixture-lease")

idle_runner = ComparisonHarness.new
idle_runner.instance_variable_set(:@qwen, FakeQwen.new)
idle_runner.instance_variable_set(:@qwen_inflight, true)
idle = idle_runner.qwen_quiescent!
busy_runner = ComparisonHarness.new
busy_client = FakeQwen.new
busy_client.slots = [{ "is_processing" => true, "n_ctx" => 4096 }]
busy_runner.instance_variable_set(:@qwen, busy_client)
busy_runner.instance_variable_set(:@qwen_inflight, true)
busy_timeout = raises.call(Comparison::Stop, "not confirmed idle") { busy_runner.qwen_quiescent! }
identity_runner = ComparisonHarness.new
identity_runner.instance_variable_set(:@qwen, FakeQwen.new)
identity_runner.instance_variable_set(:@qwen_inflight, true)
def identity_runner.qwen_observe! = raise(AmdReviewerPilotM2::Stop, "synthetic identity mismatch")
identity_mismatch = raises.call(AmdReviewerPilotM2::Stop, "identity mismatch") { identity_runner.qwen_quiescent! }
check.call("quiescence requires idle shape and observer identity; mismatch retains inflight state",
           idle == true && idle_runner.instance_variable_get(:@qwen_inflight) == false && busy_timeout &&
             busy_runner.instance_variable_get(:@qwen_inflight) == true && busy_client.request_log.length <= 61 &&
             identity_mismatch && identity_runner.instance_variable_get(:@qwen_inflight) == true)

valid_tokens = [11, 12]
valid_final = { "stop" => true, "truncated" => false, "stop_type" => "eos",
                "tokens_evaluated" => valid_tokens.length, "content" => '{"field":"ok"}' }
invalid_finals = [
  valid_final.merge("stop" => false),
  valid_final.merge("truncated" => true),
  valid_final.merge("stop_type" => "limit"),
  valid_final.merge("tokens_evaluated" => 1)
]
check.call("completion validation accepts complete output and rejects truncation or token mismatch",
           Comparison.validate_completion!(valid_final, valid_tokens) == { "field" => "ok" } &&
             invalid_finals.all? { |final| raises.call(Comparison::Stop, "truncated or mismatched completion") { Comparison.validate_completion!(final, valid_tokens) } })

runner = InferenceHarness.new
runner.instance_variable_set(:@qwen_inflight, false)
inferred = runner.infer("qwen", [{ "role" => "user", "content" => "fixture" }], { "type" => "object" }, "sampler")
payload = runner.instance_variable_get(:@qwen).completion_payload
bound_capture = payload && payload.reject { |key, _| %w[json_schema prompt].include?(key) } == Comparison.sampler(nil).reject { |key, _| key == "json_schema" } &&
  runner.saved.key?("sampler-request.json") && runner.saved.key?("sampler-response.json") && inferred == { "field" => "fixture" }
check.call("infer sends the fixed sampler through a fake transport and records a valid bounded completion", bound_capture)

ceiling_runner = InferenceHarness.new
ceiling_runner.instance_variable_set(:@generation_count, Comparison::MAX_GENERATIONS)
generation_bound = raises.call(Comparison::Stop, "generation count exceeded") do
  ceiling_runner.infer("qwen", [], {}, "over-ceiling")
end
prompt_runner = InferenceHarness.new
prompt_runner.instance_variable_get(:@qwen).rendered_prompt = "p" * 65_537
prompt_bound = raises.call(Comparison::Stop, "prompt byte bound") do
  prompt_runner.infer("qwen", [], {}, "oversized-prompt")
end
tokens_runner = InferenceHarness.new
tokens_runner.instance_variable_get(:@qwen).tokens = Array.new(3073, 1)
token_bound = raises.call(Comparison::Stop, "input token bound") do
  tokens_runner.infer("qwen", [], {}, "oversized-tokens")
end
check.call("generation, rendered-prompt, and input-token ceilings reject over-bound fake requests",
           generation_bound && prompt_bound && token_bound)

warm_sample = CooldownHarness.resource_sample(edge: 60, junction: 75)
cool_sample = CooldownHarness.resource_sample(edge: 55, junction: 70)
cooldown_runner = CooldownHarness.new(samples: Array.new(7, warm_sample) + [cool_sample], fallback: cool_sample)
cooldown_seconds = cooldown_runner.amd_cooldown!
check.call("cooldown waits at least three seconds and continues through safe but warm samples",
           cooldown_seconds >= 3 && cooldown_runner.observed_samples.length >= 8 &&
             cooldown_runner.observed_samples.first(7).all? { |sample| sample.dig("temperatures", "edge") == 60 && sample.dig("temperatures", "junction") == 75 })

never_cools = CooldownHarness.new(samples: [], fallback: warm_sample)
cooldown_timeout = raises.call(Comparison::Stop, "did not settle within 30 seconds") { never_cools.amd_cooldown! }
edge_abort = CooldownHarness.new(samples: [CooldownHarness.resource_sample(edge: 80, junction: 50)], fallback: cool_sample)
edge_abort_error = raises.call(Comparison::Stop, "AMD thermal bound") { edge_abort.amd_cooldown! }
junction_abort = CooldownHarness.new(samples: [CooldownHarness.resource_sample(edge: 50, junction: 95)], fallback: cool_sample)
junction_abort_error = raises.call(Comparison::Stop, "AMD thermal bound") { junction_abort.amd_cooldown! }
check.call("cooldown times out at 30 seconds and propagates either resource thermal abort",
           cooldown_timeout && never_cools.now == 30 && edge_abort_error && edge_abort.now == 0 &&
             junction_abort_error && junction_abort.now == 0)

branch_result = lambda do |correct|
  { "score" => { "correct" => correct, "correct_fields" => correct ? 1 : 0, "total_fields" => 1 } }
end
seed_result = lambda do |expected, verdict, findings|
  { "expected_verdict" => expected,
    "review" => { "verdict" => verdict, "findings" => findings },
    "verdict_correct" => expected == verdict }
end
summary_rows = [
  { "baseline" => { "correct" => false, "correct_fields" => 0, "total_fields" => 1 },
    "branches" => { "self" => branch_result.call(true), "amd" => branch_result.call(false), "evidence-first" => branch_result.call(false) },
    "seed_audits" => { "qwen" => seed_result.call("supported", "contradicted", [{ "claim" => "fixture" }]),
      "amd" => seed_result.call("insufficient_evidence", "contradicted", []) } },
  { "baseline" => { "correct" => true, "correct_fields" => 1, "total_fields" => 1 },
    "branches" => { "self" => branch_result.call(false), "amd" => branch_result.call(true), "evidence-first" => branch_result.call(true) },
    "seed_audits" => { "qwen" => seed_result.call("supported", "supported", []),
      "amd" => seed_result.call("insufficient_evidence", "insufficient_evidence", []) } }
]
summary = Comparison.summarize(summary_rows)
check.call("summary separates corrected, spoiled, and net results", summary.dig("branches", "self", "corrected") == 1 &&
  summary.dig("branches", "self", "spoiled") == 1 && summary.dig("branches", "self", "net_corrections") == 0 &&
  summary.dig("branches", "amd", "corrected") == 0 && summary.dig("branches", "amd", "spoiled") == 0)
check.call("summary counts supported false verdicts/findings and unsupported false contradictions", summary.dig("seed_audits", "qwen", "supported_false_verdict") == 1 &&
  summary.dig("seed_audits", "qwen", "supported_nonempty_findings") == 1 &&
  summary.dig("seed_audits", "amd", "unsupported_called_contradicted") == 1)

comparison = ComparisonHarness.new
comparison.instance_variable_set(:@cases, Cases.cases)
comparison.compare_cases
all_calls = comparison.calls
answer_calls = all_calls.count { |call| call[0] == :answer }
review_calls = all_calls.count { |call| call[0] == :review }
all_messages_private_free = comparison.messages_seen.all? { |content| !content.match?(/(?:oracle|seeded_answer|seeded_verdict)/) }
rotations = Cases.cases.each_with_index.all? do |case_data, index|
  comparison.branch_review_order.fetch(case_data.fetch("id")) == Comparison::BRANCHES.rotate(index % 3)
end
shared_originals = comparison.revision_sources.length == 30 && comparison.revision_sources.all? do |case_id, _label, source|
  source.equal?(comparison.originals.fetch(case_id))
end
seed_reviews = all_calls.count { |call| call[0] == :review && call[3].match?(/-(?:qwen|amd)-seed\z/) }
blind_answers = all_calls.select { |call| call[0] == :answer && call[3].end_with?("-independent") }
check.call("full fake comparison makes exactly 100 calls, rotates branches, shares originals, and audits 20 seeds",
           all_calls.length == 100 && answer_calls == 50 && review_calls == 50 && all_messages_private_free &&
             rotations && shared_originals && seed_reviews == 20 && blind_answers.length == 10)

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
