#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "compare-amd-reviewer-m3b"

Comparison = AmdReviewerComparisonM3b
Cases = AmdReviewerCasesM3b
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

def json_payloads(messages)
  messages.select { |message| message["role"] == "user" }.map { |message| JSON.parse(message.fetch("content")) }
end

def amd_resource_sample(temperatures: { "edge" => 89.0, "junction" => 99.0, "mem" => 89.0 },
  vram_used: 14 * Comparison::GIB, available: 8 * Comparison::GIB, pswpout: 100)
  { "temperatures" => temperatures, "vram_total" => 16 * Comparison::GIB, "vram_used" => vram_used,
    "memory" => { "MemAvailable" => available }, "paging_pages" => { "pswpout" => pswpout } }
end

puts "AMD reviewer M3b deterministic comparison boundary verification:"

ids = %w[ministral14 qwen35 phi4]
assets = ids.to_h { |id| [id, Comparison.asset(id)] }
asset_selection = assets.keys.sort == ids.sort &&
  assets.fetch("ministral14").fetch("path") == AmdReviewerPilotM2::MODEL &&
  assets.fetch("qwen35").fetch("path") == File.join(Comparison::MODEL_PARENT, "Qwen_Qwen3.5-9B-Q4_K_M.gguf") &&
  assets.fetch("phi4").fetch("path") == File.join(Comparison::MODEL_PARENT, "phi-4-Q4_K_S.gguf") &&
  assets.values.all? { |asset| asset.key?("sha256") && asset.key?("size") }
check.call("asset selection resolves only the three declared candidate IDs", asset_selection &&
  raises.call(Comparison::Stop, "unknown candidate") { Comparison.asset("not-a-candidate") } &&
  raises.call(Comparison::Stop, "unknown candidate") { Comparison.asset("../qwen35") })

legacy_fixture_digest = Contract.digest(AmdReviewerComparisonM3::Cases.cases)
check.call("pinned M3 fixture digest matches the current historical fixture", legacy_fixture_digest == Comparison::CASES_DIGEST)

alias_name = "amd-reviewer-m2-m3b-verifier"
base_argv = AmdReviewerComparisonM3.argv(alias_name)
expected_argv = base_argv.dup
expected_argv[expected_argv.index("--model") + 1] = assets.fetch("qwen35").fetch("path")
check.call("candidate launch args preserve the full M3 argv except the model path", Comparison.launch_args(alias_name, assets.fetch("qwen35")) == expected_argv)

expected_sampler = AmdReviewerComparisonM3.sampler(nil).merge(
  "presence_penalty" => 0.0, "frequency_penalty" => 0.0, "dry_multiplier" => 0.0,
  "mirostat" => 0, "typical_p" => 1.0, "xtc_probability" => 0.0, "dynatemp_range" => 0.0
)
sampler = Comparison.sampler({ "type" => "object" })
check.call("M3 sampler is extended with all explicit M3b controls", sampler == expected_sampler.merge("json_schema" => { "type" => "object" }) &&
  %w[presence_penalty frequency_penalty dry_multiplier mirostat typical_p xtc_probability dynatemp_range].all? { |key| sampler.key?(key) })

thermal_initial = amd_resource_sample
thermal_safe = amd_resource_sample(temperatures: { "edge" => 89.999, "junction" => 99.999, "mem" => 89.999 })
thermal_boundary_ok = Comparison.check_resources!(thermal_safe, thermal_initial).nil?
thermal_exact_rejected = Comparison::THERMAL_ABORT.all? do |sensor, limit|
  sample = amd_resource_sample(temperatures: { "edge" => 89.0, "junction" => 99.0, "mem" => 89.0 }.merge(sensor => limit))
  raises.call(Comparison::Stop, "AMD thermal bound: #{sensor} >= #{limit} C") { Comparison.check_resources!(sample, thermal_initial) }
end
check.call("v2 thermal limits accept just-below samples and abort at each exact 90/100/90 C boundary", thermal_boundary_ok && thermal_exact_rejected &&
  Comparison::THERMAL_ABORT == { "edge" => 90, "junction" => 100, "mem" => 90 } && Comparison::MONITOR_SECONDS == 0.5)

missing_sensor = amd_resource_sample
missing_sensor.fetch("temperatures").delete("mem")
nonfinite_samples = {
  "edge" => Float::NAN,
  "junction" => Float::INFINITY,
  "mem" => -Float::INFINITY
}.map do |sensor, value|
  sample = amd_resource_sample(temperatures: { "edge" => 89.0, "junction" => 99.0, "mem" => 89.0 }.merge(sensor => value))
  raises.call(Comparison::Stop, "invalid AMD thermal sample: #{sensor}") { Comparison.check_resources!(sample, thermal_initial) }
end
check.call("missing and non-finite temperature sensors fail closed", raises.call(KeyError) { Comparison.check_resources!(missing_sensor, thermal_initial) } && nonfinite_samples.all?)

resource_at_limits = amd_resource_sample(vram_used: 14 * Comparison::GIB, available: 8 * Comparison::GIB, pswpout: 65_636)
resource_under_vram = amd_resource_sample(vram_used: (14 * Comparison::GIB) + 1)
resource_under_ram = amd_resource_sample(available: (8 * Comparison::GIB) - 1)
resource_over_swap = amd_resource_sample(pswpout: 65_637)
check.call("VRAM, RAM, and swap limits preserve exact minimum headroom and maximum page delta", Comparison.check_resources!(resource_at_limits, thermal_initial).nil? &&
  raises.call(Comparison::Stop, "AMD headroom bound") { Comparison.check_resources!(resource_under_vram, thermal_initial) } &&
  raises.call(Comparison::Stop, "RAM headroom bound") { Comparison.check_resources!(resource_under_ram, thermal_initial) } &&
  raises.call(Comparison::Stop, "swap-out bound") { Comparison.check_resources!(resource_over_swap, thermal_initial) })

thermal_limit_fixture_ok = Dir.mktmpdir("m3b-thermal-limits-") do |hw|
  names = (1..3).flat_map { |index| %w[crit emergency].map { |kind| "temp#{index}_#{kind}" } }
  values = names.each_with_index.to_h { |name, index| [name, (index + 1) * 10_000] }
  values.each { |name, value| File.write(File.join(hw, name), "#{value}\n") }
  complete = Comparison.thermal_limits(hw) == values
  missing_name = names.last
  File.unlink(File.join(hw, missing_name))
  missing_fails = raises.call(Errno::ENOENT) { Comparison.thermal_limits(hw) }
  File.write(File.join(hw, missing_name), "invalid\n")
  invalid_fails = raises.call(ArgumentError) { Comparison.thermal_limits(hw) }
  File.write(File.join(hw, missing_name), "0\n")
  zero_fails = raises.call(Comparison::Stop, "invalid driver thermal limit: #{missing_name}") { Comparison.thermal_limits(hw) }
  File.write(File.join(hw, missing_name), "-1\n")
  negative_fails = raises.call(Comparison::Stop, "invalid driver thermal limit: #{missing_name}") { Comparison.thermal_limits(hw) }
  complete && missing_fails && invalid_fails && zero_fails && negative_fails
end
check.call("driver thermal attestation requires all six positive integer crit/emergency readings", thermal_limit_fixture_ok)

tokens = [1, 2, 3]
settings = Comparison.sampler(nil).reject { |key, _| %w[stream cache_prompt json_schema].include?(key) }
settings["samplers"] = %w[penalties dry top_n_sigma top_k typ_p top_p min_p xtc temperature]
settings["lora"] = []
valid_completion = { "stop" => true, "truncated" => false, "stop_type" => "eos",
  "tokens_evaluated" => tokens.length, "content" => '{"field":"fixture"}', "generation_settings" => settings }
drifted_temperature = Marshal.load(Marshal.dump(valid_completion))
drifted_temperature.fetch("generation_settings")["temperature"] = 0.06
missing_sampler = Marshal.load(Marshal.dump(valid_completion))
missing_sampler.fetch("generation_settings").delete("top_p")
wrong_pipeline = Marshal.load(Marshal.dump(valid_completion))
wrong_pipeline.fetch("generation_settings")["samplers"] = %w[temperature top_p]
unexpected_adapter = Marshal.load(Marshal.dump(valid_completion))
unexpected_adapter.fetch("generation_settings")["lora"] = ["adapter"]
check.call("completion validation accepts pinned actual settings and rejects settings drift", Comparison.validate_completion!(valid_completion, tokens) == { "field" => "fixture" } &&
  raises.call(Comparison::Stop, "effective sampler mismatch: temperature") { Comparison.validate_completion!(drifted_temperature, tokens) } &&
  raises.call(KeyError) { Comparison.validate_completion!(missing_sampler, tokens) } &&
  raises.call(Comparison::Stop, "unexpected sampler pipeline") { Comparison.validate_completion!(wrong_pipeline, tokens) } &&
  raises.call(Comparison::Stop, "unexpected adapter") { Comparison.validate_completion!(unexpected_adapter, tokens) })

item = Cases.cases.first
original = item.fetch("answer_fields").to_h { |field| [field, "source-only-#{field}"] }
control_messages = Comparison.control_messages(item, original)
control_payload = json_payloads(control_messages).fetch(0)
control_task = Cases.public_case(item).reject { |key, _| key == "id" }
check.call("no-review control binds the original and public evidence without feedback fields", control_payload.keys.sort == %w[instruction original_answer task].sort &&
  control_payload.fetch("original_answer") == original && control_payload.fetch("task") == control_task &&
  !control_payload.key?("attributed_unendorsed_review"))

packet = Comparison.review_packet(item, original, "m3b-binding-check", at: 1_800_000_000)
tampered_source = Contract.copy(packet).merge("source_answer" => '{"changed":"source"}')
tampered_evidence = Contract.copy(packet)
tampered_evidence.fetch("evidence").first["text"] = "changed synthetic evidence"
check.call("review request immutably binds both source answer and evidence", Contract.request!(packet) == packet &&
  packet.fetch("source_revision") == Contract.text_digest(packet.fetch("source_answer")) &&
  packet.fetch("evidence_revision") == Contract.digest(packet.fetch("evidence")) &&
  packet.fetch("source_event_id").start_with?("m3b-") &&
  packet.fetch("evidence").all? { |fact| fact.fetch("provenance") == "synthetic-m3b-comparison" } &&
  raises.call(Lab::ValidationError, "revision mismatch") { Contract.request!(tampered_source) } &&
  raises.call(Lab::ValidationError, "evidence text digest mismatch") { Contract.request!(tampered_evidence) })

ceiling = Comparison.allocate
ceiling.instance_variable_set(:@generation_count, Comparison::LIMIT)
transport_called = false
ceiling.define_singleton_method(:http) { |*| transport_called = true; raise "transport must not be reached" }
ceiling_call = raises.call(Comparison::Stop, "M3B generation budget exceeded") do
  ceiling.infer("qwen", [], {}, "at-ceiling")
end
check.call("48-call ceiling rejects before transport", ceiling_call && !transport_called && ceiling.instance_variable_get(:@generation_count) == Comparison::LIMIT)

# Replace only the inherited HTTP implementation with a fixture; no socket or
# runtime service is contacted while the optional native-template branch runs.
fake_http = Module.new do
  def http(path, payload = nil, **options, &block)
    @fake_http_calls ||= []
    @fake_http_calls << [path, payload, options]
    { "prompt" => @fake_prompt || "synthetic prompt</think>" }
  end
end
AmdReviewerComparisonM3.prepend(fake_http)
template_false = Comparison.allocate
template_false.instance_variable_set(:@asset, { "thinking" => false })
template_false.instance_variable_set(:@fake_prompt, "synthetic prompt</think>")
template_false.http("/apply-template", { "messages" => [] })
false_payload = template_false.instance_variable_get(:@fake_http_calls).fetch(0).fetch(1)
template_true = Comparison.allocate
template_true.instance_variable_set(:@asset, { "thinking" => true })
template_true.http("/apply-template", { "messages" => [] })
true_payload = template_true.instance_variable_get(:@fake_http_calls).fetch(0).fetch(1)
template_bad = Comparison.allocate
template_bad.instance_variable_set(:@asset, { "thinking" => false })
template_bad.instance_variable_set(:@fake_prompt, "missing native marker")
check.call("template HTTP branch uses fake transport and attests non-thinking output", false_payload.dig("chat_template_kwargs", "enable_thinking") == false &&
  !true_payload.key?("chat_template_kwargs") &&
  raises.call(Comparison::Stop, "non-thinking native template not attested") { template_bad.http("/apply-template", {}) })

class FakeComparisonM3b < AmdReviewerComparisonM3b
  attr_reader :calls, :saved, :original_refs, :review_payloads, :answer_payloads, :model_counts

  def initialize(cases:, originals:, candidate_id: "ministral14")
    @cases, @originals = cases, originals
    @calls, @saved, @original_refs = [], {}, []
    @review_payloads, @answer_payloads = [], []
    @model_counts = Hash.new(0)
    @generation_count = 0
    @rows = []
    @candidate_id = candidate_id
  end

  def infer(model, messages, _schema, label)
    @model_counts[model] += 1
    @generation_count += 1
    payloads = json_payloads(messages)
    @answer_payloads << [label, payloads]
    task = payloads.find { |payload| payload.key?("task") }&.fetch("task")
    case_data = @cases.find { |candidate| task && task.fetch("question") == candidate.fetch("question") }
    raise "fake infer could not bind case for #{label}" unless case_data
    case_data.fetch("answer_fields").to_h { |field| [field, "fake-#{label}-#{field}"] }
  end

  def answer(model, item, label, original: nil, review: nil)
    raise "unexpected model for Qwen answer" unless model == "qwen"
    @model_counts[model] += 1
    @generation_count += 1
    @original_refs << [item.fetch("id"), label, original] if original
    @answer_payloads << [label, json_payloads(self.class.answer_messages(item, original: original, review: review))]
    item.fetch("answer_fields").to_h { |field| [field, "fake-answer-#{label}-#{field}"] }
  end

  def review(model, item, answer, label, independent: nil)
    @calls << [model, label]
    @model_counts[model] += 1
    @generation_count += 1
    packet = self.class.review_packet(item, answer, label, at: 1_800_000_000)
    messages = self.class.review_messages(packet, independent: independent)
    @review_payloads << [model, item.fetch("id"), label, json_payloads(messages)]
    { "review_id" => packet.fetch("review_id"), "verdict" => "supported", "findings" => [], "omissions" => [] }
  end

  def save(name, value)
    @saved[name] = value
  end
end

legacy_cases = AmdReviewerComparisonM3::Cases.cases
legacy_originals = legacy_cases.to_h do |case_data|
  [case_data.fetch("id"), case_data.fetch("answer_fields").to_h { |field| [field, "unchanged-original-#{case_data.fetch('id')}-#{field}"] }]
end
fake_comparison = FakeComparisonM3b.new(cases: legacy_cases, originals: legacy_originals)
fake_comparison.compare_cases
heldout_ids = Cases.cases.map { |case_data| case_data.fetch("id") }
old_case_ids = legacy_cases.map { |case_data| case_data.fetch("id") }
fresh_reviews = fake_comparison.review_payloads.select { |entry| entry.fetch(2).start_with?("heldout-") }
no_oracle_leak = fake_comparison.review_payloads.all? do |_model, _id, _label, payloads|
  JSON.generate(payloads) !~ /(?:oracle|seeded_answer|seeded_verdict)/
end && fake_comparison.answer_payloads.all? do |_label, payloads|
  JSON.generate(payloads) !~ /(?:oracle|seeded_answer|seeded_verdict)/
end
control_payloads = fake_comparison.answer_payloads.select { |label, _| label.end_with?("-control") }
revision_payloads = fake_comparison.answer_payloads.select { |label, _| label.end_with?("-amd-revision") }
control_review_isolation = control_payloads.length == 10 && control_payloads.each_with_index.all? do |(_label, payloads), index|
  payload = payloads.fetch(0)
  source = legacy_originals.fetch(old_case_ids.fetch(index))
  payload.keys.sort == %w[instruction original_answer task].sort && payload.fetch("original_answer") == source
end
revisions_independent = revision_payloads.length == 10 && revision_payloads.all? do |_label, payloads|
  payload = payloads.fetch(0)
  payload.key?("original_answer") && payload.key?("attributed_unendorsed_review")
end
same_originals = old_case_ids.all? do |id|
  source = legacy_originals.fetch(id)
  records = fake_comparison.original_refs.select { |case_id, _, _| case_id == id }
  record_reviews = fake_comparison.review_payloads.select { |_, case_id, label, _| case_id == id && label.end_with?("-amd-review") }
  records.length == 1 && records.first.fetch(2).equal?(source) && record_reviews.length == 1 &&
    record_reviews.first.fetch(3).dig(0, "packet", "source_answer") == JSON.generate(source)
end
heldout_review_only = fresh_reviews.length == 8 && fresh_reviews.all? do |model, id, label, _|
  model == "amd" && heldout_ids.include?(id) && label.start_with?("heldout-")
end && fresh_reviews.map { |entry| entry.fetch(1) }.sort == heldout_ids.sort
check.call("fake comparison uses twenty Qwen and twenty-eight AMD reviews within forty-eight calls", fake_comparison.model_counts == { "qwen" => 20, "amd" => 28 } &&
  fake_comparison.instance_variable_get(:@generation_count) == 48 && fake_comparison.calls.length == 28)
check.call("ten original cases use the same source answer across independent control and AMD-review branches", same_originals &&
  control_review_isolation && revisions_independent && old_case_ids.uniq.length == 10)
check.call("eight fresh cases are review-only and no prompt leaks oracle labels", heldout_review_only && no_oracle_leak &&
  fake_comparison.saved.fetch("scores.json").fetch("heldout").length == 8 && fake_comparison.saved.fetch("scores.json").fetch("rows").length == 10)

rotations = %w[qwen35 phi4].map do |candidate_id|
  offset = Comparison::MODEL_IDS.index(candidate_id)
  ordered_originals = legacy_cases.rotate(offset).map { |case_data| case_data.fetch("id") }
  ordered_heldout = Cases.cases.rotate(offset).map { |case_data| case_data.fetch("id") }
  run = FakeComparisonM3b.new(cases: legacy_cases, originals: legacy_originals, candidate_id: candidate_id)
  run.compare_cases
  score_rows = run.saved.fetch("scores.json").fetch("rows")
  heldout_rows = run.saved.fetch("scores.json").fetch("heldout")
  indexed_originals = 10.times.map { |index| run.saved.fetch(format("case-%02d-scores.json", index + 1)).fetch("id") }
  indexed_heldout = 8.times.map do |index|
    entry = run.review_payloads.find { |row| row.fetch(2) == format("heldout-%02d", index + 1) }
    entry&.fetch(1)
  end
  { "candidate" => candidate_id,
    "ok" => score_rows.map { |row| row.fetch("id") } == ordered_originals &&
      heldout_rows.map { |row| row.fetch("id") } == ordered_heldout &&
      indexed_originals == old_case_ids && indexed_heldout == heldout_ids &&
      score_rows.first.fetch("id") == old_case_ids.fetch(offset) &&
      heldout_rows.first.fetch("id") == heldout_ids.fetch(offset) &&
      score_rows.map { |row| row.fetch("id") }.uniq.length == 10 &&
      heldout_rows.map { |row| row.fetch("id") }.uniq.length == 8 &&
      run.model_counts == { "qwen" => 20, "amd" => 28 } }
end
check.call("qwen35 and phi4 rotate both datasets while preserving stable unique case indices", rotations.all? { |rotation| rotation.fetch("ok") })

class FakeV2LeaseStore
  def with_control_lock
    yield
  end

  def leases_for_quiescent_admission_unlocked
    [{ "pid" => Process.pid, "provider_id" => "external.codex.amd", "resource_group" => "amd-vulkan-generation" }]
  end
end

class MonitorFailureHarness < AmdReviewerComparisonM3b
  attr_reader :saved, :stop_count, :monitor_sample_count, :monitor_thread

  def initialize
    @samples, @saved = [], {}
    @initial = amd_resource_sample
    @qwen_inflight = false
    @child = nil
    @log = nil
    @monitor_events = Queue.new
    @monitor_sample_count = 0
    @stop_count = 0
  end

  def qwen_observe! = true
  def start_server(_label) = (@child = 321)
  def stop_server = (@stop_count += 1; @child = nil)
  def wait_release(_mode) = true

  def snapshot
    @monitor_thread = Thread.current
    @monitor_sample_count += 1
    @monitor_events << true
    raise Comparison::Stop, "fixture monitor failure"
  end

  def compare_cases
    @monitor_events.pop
    Kernel.sleep(0.05)
  end

  def save(name, value)
    @saved[name] = value
  end
end

store_class = SoulCore::ModelRuntimeLeaseStore
original_store_new = store_class.method(:new)
store_class.define_singleton_method(:new) do |root:|
  raise "unexpected store root" unless root == Comparison::ROOT
  FakeV2LeaseStore.new
end
runner = MonitorFailureHarness.new
monitor_failure = begin
  raises.call(Comparison::Stop, "fixture monitor failure") do
    runner.run("fixed-m3b-v2-comparison", timeout_seconds: Comparison::MAX_SECONDS)
  end
ensure
  store_class.define_singleton_method(:new, original_store_new)
end
check.call("v2 monitor failure stops and joins the monitor, tears down the server, and saves samples", monitor_failure &&
  runner.monitor_sample_count == 1 && runner.stop_count >= 2 && runner.saved.key?("resource-samples.json") &&
  runner.monitor_thread && !runner.monitor_thread.alive? && runner.monitor_thread.join == runner.monitor_thread)

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
