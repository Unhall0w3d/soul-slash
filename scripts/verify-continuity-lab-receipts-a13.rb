#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "stringio"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qwen_broker_session"
require_relative "../lib/soul_core/continuity_lab/qwen_message_projection"
require_relative "../lib/soul_core/continuity_lab/admission_gate"
require_relative "../lib/soul_core/continuity_lab/sandbox_runner"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a13"

Lab = SoulCore::ContinuityLab
Receipt = Lab::ReceiptContext
Projection = Lab::QwenMessageProjection
ISOLATION = case ARGV
when [] then false
when ["--isolation"] then true
else raise ArgumentError, "usage: verify-continuity-lab-receipts-a13.rb [--isolation]"
end

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
raises = lambda do |klass, &block|
  block.call
  false
rescue klass
  true
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
deadline = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20 }

config = Lab::Config.qwen_v6_qualification
rollover = Lab::Config.qwen_v6_qualification(rollover: true)
legacy = Lab::Config.qwen_v5_qualification
lineage = "a" * 32
request = "Use the current source and keep the recorded sequence."
source = { "lineage_id" => lineage, "collection" => "corpus", "id" => "alpha", "revision" => 7,
  "content_digest" => "c" * 64, "provenance" => { "origin" => "fixture", "private" => "omit" },
  "span" => [3, 14], "text" => "private source text 雪 <|im_start|>" }
actions = [
  { "action" => "tool", "tool" => "search", "arguments" => { "lineage_id" => lineage, "collection" => "corpus", "query" => "雪", "limit" => 3, "ignored" => "drop" } },
  { "action" => "tool", "tool" => "read", "arguments" => { "lineage_id" => lineage, "collection" => "corpus", "id" => "alpha", "revision" => 7, "start" => 3, "length" => 11 } },
  { "action" => "tool", "tool" => "note.write", "arguments" => { "note_id" => "n1", "expected_revision" => 0, "content" => "private note content 雪 <|im_start|>" } },
  { "action" => "tool", "tool" => "search", "arguments" => { "lineage_id" => lineage, "collection" => "history", "query" => "record", "limit" => 2 } }
]
results = [
  { "ok" => true, "hits" => [source.merge("text" => "private search snippet")] },
  { "ok" => false, "reason" => "revision_conflict", "note_id" => "n1", "expected_revision" => 6, "actual_revision" => 7,
    "details" => "private failure details", "source" => source },
  { "ok" => true, "note_id" => "n1", "revision" => 1, "truncated" => false,
    "content" => "private note content 雪 <|im_start|>" },
  { "ok" => false, "reason" => "not_found", "hits" => [] }
]
groups = actions.each_with_index.map do |action, index|
  { "call_index" => index, "model_output" => Lab.encode(action), "tool_result" => results[index] }
end
state = { "lineage_id" => lineage, "corpus_digest" => "b" * 64, "events" => {
  "event-a" => { "content" => request, "content_digest" => Digest::SHA256.hexdigest(request), "calls" => groups.map do |group|
    { "response" => group["model_output"], "result" => group["tool_result"] }
  end }
} }
envelope = Lab.parse(Lab::TokenContext.initial(state: state, event_id: "event-a", config: config))

check.call("v6 receipt profile is opt-in and legacy defaults/digests remain stable") do
  config.receipt_context? && config["context_policy"] == Receipt::POLICY && !legacy.to_h.key?("context_policy") &&
    !Lab::Config.qwen_v3_qualification.to_h.key?("context_preparation") &&
    Lab::Config.qwen_v5_qualification.digest == legacy.digest &&
    Lab::TokenContext.budget(config) == 3072 && Lab::TokenContext.budget(rollover) == 2048 &&
    raises.call(Lab::ValidationError) { Lab::Config.new("context_policy" => Receipt::POLICY) } &&
    raises.call(Lab::ValidationError) { Lab::ContextBuilder.build(state: state, event_id: "event-a", config: config) }
end

a13_cases = Lab::QualificationCasesA13.cases
a8_cases = Lab::QualificationCasesA8.cases
a12_by_pair = Lab::QualificationCasesA12.cases.to_h { |spec| [spec.fetch("pair"), spec.fetch("content")] }
check.call("four A13 cases retain A8 ordering, contracts and corpus with paired A12 clarifications") do
  a13_cases.map { |spec| [spec.fetch("pair"), spec.fetch("condition")] } ==
      a8_cases.map { |spec| [spec.fetch("pair"), spec.fetch("condition")] } &&
    Lab::QualificationCasesA13::CORPUS == Lab::QualificationCasesA8::CORPUS &&
    a13_cases.zip(a8_cases).all? do |current, baseline|
      current.fetch("contract") == baseline.fetch("contract") &&
        current.fetch("content") == a12_by_pair.fetch(current.fetch("pair")) &&
        !current.fetch("content").include?(current.dig("contract", "reply"))
    end
end

condition_fixture = lambda do |spec|
  boundary = spec.fetch("pair") == "reread" ? 3 : 4
  calls = (0..4).map do |index|
    prior = (0...index).to_a
    receipt_indices = spec.fetch("condition") == "rollover" && index >= boundary ? [0] : []
    full_indices = receipt_indices.empty? ? prior : prior.drop(1)
    omitted = receipt_indices.map { |call_index| { "call_index" => call_index } }
    { "context" => { "manifest" => { "context_policy" => Receipt::POLICY, "input_tokens" => 1000,
      "retained_receipts" => receipt_indices.map { |call_index| { "call_index" => call_index } },
      "included_groups" => full_indices, "omitted_groups" => omitted } } }
  end
  { "calls" => calls }
end
check.call("A13 condition evidence accepts matched visible and group-zero rollover coverage") do
  a13_cases.all? do |spec|
    evidence = Lab::QualificationCasesA13.condition_evidence(condition_fixture.call(spec), spec)
    evidence["intended_condition_observed"] && evidence["receipt_coverage"]
  end
end
check.call("A13 condition evidence rejects missing receipt coverage despite observed group-zero omission") do
  spec = a13_cases.find { |candidate| candidate.fetch("condition") == "rollover" }
  event = condition_fixture.call(spec)
  boundary = spec.fetch("pair") == "reread" ? 3 : 4
  event.dig("calls", boundary, "context", "manifest").fetch("retained_receipts").clear
  evidence = Lab::QualificationCasesA13.condition_evidence(event, spec)
  evidence["group_zero_omitted_at_boundary"] && !evidence["receipt_coverage"] && !evidence["intended_condition_observed"]
end

expected_receipts = groups.first(2).map { |group| Receipt.receipt(group) }
check.call("receipt is an exact allowlisted record of action, failure and source provenance") do
  expected_receipts[0] == { "call_index" => 0, "action" => actions[0].slice("action", "tool").merge("arguments" => actions[0]["arguments"].slice(*Receipt::ARGUMENT_FIELDS)),
    "tool_result" => { "ok" => true, "hits" => [source.slice(*Receipt::SOURCE_FIELDS)] } } &&
    expected_receipts[1].dig("tool_result", "reason") == "revision_conflict" &&
    expected_receipts[1].dig("tool_result", "source") == source.slice(*Receipt::SOURCE_FIELDS) &&
    !expected_receipts.to_s.include?("private source text") && !expected_receipts.to_s.include?("private search snippet") &&
    !expected_receipts.to_s.include?("private failure details")
end
check.call("note receipt keeps revision/outcome while omitting note contents and source text") do
  note_receipt = Receipt.receipt(groups[2])
  note_receipt == { "call_index" => 2, "action" => { "action" => "tool", "tool" => "note.write",
      "arguments" => { "note_id" => "n1", "expected_revision" => 0 } },
    "tool_result" => { "ok" => true, "note_id" => "n1", "revision" => 1, "truncated" => false } } &&
    !note_receipt.to_s.include?("private note content")
end
invalid_group = { "call_index" => 4, "model_output" => '{"action":"tool","tool":"read","arguments":broken}',
  "tool_result" => { "ok" => false, "reason" => "invalid_action" } }
check.call("invalid response preserves rejection and raw response digest without invented action") do
  invalid = Receipt.receipt(invalid_group)
  invalid == { "call_index" => 4, "tool_result" => { "ok" => false, "reason" => "invalid_action" },
    "invalid_response_sha256" => Digest::SHA256.hexdigest(invalid_group["model_output"]) } && !invalid.key?("action")
end

trim = Lab.parse(Lab::TokenContext.initial(state: state, event_id: "event-a", config: config))
trim["tool_groups"] = copy.call(groups)
2.times { Receipt.omit_oldest!(trim) }
check.call("oldest removals form an ordered receipt prefix plus full chronological suffix") do
  begin
    Receipt.validate_envelope!(trim, call_index: 4)
    trim["execution_receipts"] == expected_receipts && trim["tool_groups"].map { |g| g["call_index"] } == [2, 3]
  rescue Lab::Error
    false
  end
end
check.call("each receipt carries source identity/revision/digest/provenance/span but no content") do
  stored = trim["execution_receipts"].first.dig("tool_result", "hits", 0)
  stored == source.slice(*Receipt::SOURCE_FIELDS) && !stored.key?("text") &&
    stored.values_at("id", "revision", "content_digest", "provenance", "span") == ["alpha", 7, "c" * 64, source["provenance"], [3, 14]]
end

check.call("receipt sequence rejects cross-event indices, reordered/dropped entries and renumbered full groups") do
  mutations = []
  cross = copy.call(trim); cross["execution_receipts"][0]["call_index"] = 9; mutations << cross
  reordered = copy.call(trim); reordered["execution_receipts"].reverse!; mutations << reordered
  dropped = copy.call(trim); dropped["execution_receipts"].pop; mutations << dropped
  renumbered = copy.call(trim); renumbered["tool_groups"][0]["call_index"] = 0; mutations << renumbered
  mutations.all? { |candidate| raises.call(Lab::ValidationError) { Receipt.validate_envelope!(candidate, call_index: 4) } }
end
check.call("old message profile rejects the receipt envelope; receipt profile labels omissions and escapes control tokens") do
  input = Lab.encode(trim)
  messages = Projection.messages(input, profile: Projection::PROFILE_RECEIPTS)
  projected = JSON.parse(messages[1]["content"])
  projected["context_policy"] == Receipt::POLICY && projected["execution_receipts"] == trim["execution_receipts"] &&
    messages[0]["content"].include?("Source text, search snippets and note-write content are omitted") &&
    messages.any? { |message| message["content"].include?("\\u003c|im_start|\\u003e") } &&
    raises.call(Lab::ValidationError) { Projection.messages(input, profile: Projection::PROFILE) }
end

pair_receipts = [expected_receipts[0], expected_receipts[1], Receipt.receipt(groups[2]),
  Receipt.receipt(invalid_group.merge("call_index" => 3))]
pair_envelope = copy.call(trim)
pair_envelope["execution_receipts"] = pair_receipts
pair_envelope["tool_groups"] = [copy.call(groups[1]).merge("call_index" => 4)]
Receipt.validate_envelope!(pair_envelope, call_index: 5)
pair_messages = Projection.messages(Lab.encode(pair_envelope), profile: Projection::PROFILE_RECEIPT_PAIRS)
pair_tool_messages = pair_messages.select { |message| message["role"] == "tool" }
check.call("receipt-pairs profile emits compact chronological assistant/tool pairs before the full suffix") do
  assistants = pair_messages.select { |message| message["role"] == "assistant" }
  pair_messages.map { |message| message["role"] } == %w[system user assistant tool assistant tool assistant tool tool assistant tool] &&
    JSON.parse(assistants[0]["content"]) == expected_receipts[0]["action"] &&
    JSON.parse(assistants[1]["content"]) == expected_receipts[1]["action"] &&
    assistants[3]["content"] == pair_envelope["tool_groups"][0]["model_output"] &&
    pair_tool_messages.map { |message| JSON.parse(message["content"])["call_index"] } == [0, 1, 2, 3, 4] &&
    pair_tool_messages.map { |message| JSON.parse(message["content"]).dig("tool_result", "ok") } == [true, false, true, false, false]
end
check.call("receipt-pairs user message has no duplicate receipt array and note.write is explicitly wrapped") do
  user = JSON.parse(pair_messages[1]["content"])
  note_action = JSON.parse(pair_messages[6]["content"])
  user["context_policy"] == Receipt::POLICY && !user.key?("execution_receipts") &&
    note_action == { "recorded_action" => actions[2].slice("action", "tool").merge("arguments" => { "note_id" => "n1", "expected_revision" => 0 }),
      "omitted_action_fields" => ["arguments.content"] } &&
    !pair_messages[1..].any? { |message| message["content"].include?("private note content") }
end
check.call("invalid receipt-pair has only its rejection digest and no invented assistant action") do
  invalid_result = JSON.parse(pair_messages[8]["content"])
  invalid_result == { "tool_result" => { "ok" => false, "reason" => "invalid_action" },
    "invalid_response_sha256" => Digest::SHA256.hexdigest(invalid_group["model_output"]),
    "execution_receipt" => true, "call_index" => 3 } &&
    !pair_messages[2...8].any? { |message| message["role"] == "assistant" && message["content"].include?("invalid_response_sha256") }
end
check.call("receipt-pairs projection escapes control-token-like text and rejects profile mismatches") do
  raw = pair_messages.map { |message| message["content"] }.join
  legacy_envelope = Lab::ContextBuilder.envelope(state: state, event_id: "event-a", config: legacy)
  raw.include?("\\u003c|im_start|\\u003e") && !raw.include?("<|im_start|>") &&
    raises.call(Lab::ValidationError) { Projection.messages(Lab.encode(pair_envelope), profile: Projection::PROFILE) } &&
    raises.call(Lab::ValidationError) { Projection.messages(Lab.encode(legacy_envelope), profile: Projection::PROFILE_RECEIPT_PAIRS) }
end

check.call("request remains current and no prior-event material enters the receipt projection") do
  other = copy.call(state)
  other["events"]["older-event"] = { "content" => "DO NOT LEAK old request", "content_digest" => "d" * 64, "calls" => [
    { "response" => Lab.encode({ "action" => "tool", "tool" => "read", "arguments" => {} }),
      "result" => { "ok" => true, "text" => "DO NOT LEPLAY old result" } }
  ] }
  current = Lab.parse(Lab::TokenContext.initial(state: other, event_id: "event-a", config: config))
  current["tool_groups"] = copy.call(groups)
  Receipt.omit_oldest!(current)
  text = Lab.encode(current)
  current.dig("user", "content") == request && !text.include?("DO NOT LEAK") && !text.include?("DO NOT LEPLAY")
end

byte_large = copy.call(state)
byte_large["events"]["event-a"]["calls"].each_with_index do |call, index|
  call["result"]["source"] ||= {}
  call["result"]["source"]["text"] = "雪" * (index == 3 ? 100 : (index == 2 ? 5000 : 3000))
end
byte_input = Lab::TokenContext.initial(state: byte_large, event_id: "event-a", config: config)
check.call("byte trimming uses receipts, preserves newest complete result, and stays under 12,288 bytes") do
  byte_input.bytesize <= Lab::TokenContext::MAX_BYTES &&
    Lab.parse(byte_input)["tool_groups"].last["call_index"] == 3 &&
    Lab.parse(byte_input)["execution_receipts"].map { |r| r["call_index"] } == [0, 1, 2]
end

class A13FixtureClient
  attr_reader :requests, :generations
  def initialize(token_count: 100, response: '{"action":"wait"}')
    @token_count, @response, @requests, @generations = token_count, response, [], []
  end
  def request(_method, route, payload = nil, deadline:)
    @requests << [route, payload]
    case route
    when "/apply-template"
      @messages = payload.fetch("messages")
      { "prompt" => JSON.generate(payload) + "<think>\n\n</think>\n\n" }
    when "/tokenize"
      count = @token_count.respond_to?(:call) ? @token_count.call(@messages) : @token_count
      { "tokens" => Array.new(count, 17) }
    when "/completion"
      @generations << payload
      { "content" => @response, "tokens_evaluated" => payload.fetch("prompt").length, "tokens_predicted" => 4, "truncated" => false }
    else raise "unexpected fixture route #{route}"
    end
  end
  def stream_completion(payload, deadline:, on_progress:)
    @generations << payload
    { "content" => @response, "tokens_evaluated" => payload.fetch("prompt").length, "tokens_predicted" => 4, "truncated" => false }
  end
end

client = A13FixtureClient.new(token_count: ->(messages) { messages.count { |message| message["role"] == "tool" } > 1 ? 4096 : 2800 })
broker = Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(_row) {}, before_generation: -> {},
  protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
  execution_profile: Lab::Config::STREAM_PROFILE, message_profile: Projection::PROFILE_RECEIPTS)
broker.instance_variable_set(:@calls, 4)
prep = broker.dispatch({ "operation" => "prepare_context", "call_index" => 4, "input" => Lab.encode(trim) }, deadline: deadline.call)
token_prep = prep.fetch("preparation")
check.call("token pass repeats receipt-aware trimming until actual token budget fits") do
  token_prep["measurements"].length > 1 && token_prep["formatted"].include?("execution_receipts") &&
    JSON.parse(token_prep["formatted"])["tool_groups"].last["call_index"] == 3 && client.generations.empty?
end

# Build replayable host preparations from a synthetic tokenizer count sequence.
make_preparation = lambda do |source_state, event_id, selected_config, counts, rejected = false|
  initial = Lab::TokenContext.initial(state: source_state, event_id: event_id, config: selected_config)
  envelope = Lab.parse(initial)
  measurements = counts.map do |count|
    current = Lab.encode(envelope)
    row = Lab::TokenContext.measurement(current, "fixture-prompt", Array.new(count, 17))
    Receipt.omit_oldest!(envelope) if count > Lab::TokenContext.budget(selected_config) && envelope["tool_groups"].length > 1
    row
  end
  Lab::TokenContext.preparation(initial: initial, formatted: Lab.encode(envelope), measurements: measurements,
    input_budget: Lab::TokenContext.budget(selected_config), call_index: source_state.fetch("events").fetch(event_id).fetch("calls").length,
    status: rejected ? "rejected" : "ready")
end

multi_state = copy.call(state)
prep_ok = make_preparation.call(multi_state, "event-a", config, [4096, 4096, 2800])
finalized = Lab::TokenContext.finalize(state: multi_state, event_id: "event-a", config: config, preparation: prep_ok)
bad_finalizations = []
%w[altered cross_event reordered dropped].each do |kind|
  bad = copy.call(prep_ok)
  candidate = Lab.parse(bad["formatted"])
  case kind
  when "altered" then candidate["execution_receipts"][0]["tool_result"]["reason"] = "made_up"
  when "cross_event" then candidate["execution_receipts"][0]["call_index"] = 8
  when "reordered" then candidate["execution_receipts"].reverse!
  when "dropped" then candidate["execution_receipts"].pop
  end
  bad["formatted"] = Lab.encode(candidate)
  bad_finalizations << raises.call(Lab::ValidationError) { Lab::TokenContext.finalize(state: multi_state, event_id: "event-a", config: config, preparation: bad) }
end
check.call("finalize binds exact committed receipt projection and ordered omission history") do
  finalized.dig("manifest", "context_policy") == Receipt::POLICY &&
    finalized.dig("manifest", "retained_receipts").map { |r| r["receipt_digest"] } ==
      Lab.parse(prep_ok["formatted"])["execution_receipts"].map { |r| Lab.digest(r) } && bad_finalizations.all?
end

replay_checks = []
Dir.mktmpdir("continuity-a13-replay-") do |directory|
  replay_path = File.join(directory, "store")
  fired = false
  fault = lambda do |point, record|
    if !fired && point == :after_commit && record["kind"] == "action_result" && record.dig("payload", "call_index") == 3
      fired = true
      raise IOError, "synthetic interruption after four recorded results"
    end
  end
  replay_store = Lab::Store.create(path: replay_path, config: config,
    corpus: [{ "id" => "alpha", "content" => "fixture source for deterministic receipt replay" }], fault: fault)
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    envelope = Lab.parse(input)
    selected = envelope
    measurements = []
    loop do
      encoded = Lab.encode(selected)
      count = selected["tool_groups"].length > 1 ? 4096 : 2800
      measurements << Lab::TokenContext.measurement(encoded, "fixture-prompt", Array.new(count, 17))
      break if count <= 3072
      Lab::ReceiptContext.omit_oldest!(selected)
    end
    Lab::TokenContext.preparation(initial: input, formatted: Lab.encode(selected), measurements: measurements,
      input_budget: 3072, call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    envelope = Lab.parse(input)
    args = { "lineage_id" => envelope.fetch("lineage_id"), "collection" => "corpus", "id" => "alpha",
      "revision" => 1, "start" => 0, "length" => 20 }
    action = if call_index.even?
      { "action" => "tool", "tool" => "read", "arguments" => args }
    else
      { "action" => "tool", "tool" => "search", "arguments" => args.slice("lineage_id", "collection").merge("query" => "fixture", "limit" => 1) }
    end
    Lab.encode(action)
  end
  interrupted = raises.call(Lab::IntegrityError) do
    Lab::Runtime.new(store: replay_store, backend: backend).submit(event_id: "receipt-replay", content: "retrieve fixture")
  end
  snapshot = replay_store.snapshot
  pending_state = copy.call(snapshot)
  replay_prep = make_preparation.call(pending_state, "receipt-replay", config, [4096, 4096, 4096, 2800])
  valid_context = Lab::TokenContext.finalize(state: pending_state, event_id: "receipt-replay", config: config, preparation: replay_prep)
  forged_replays = %w[altered cross_event reordered dropped].map do |kind|
    forged_prep = copy.call(replay_prep)
    forged_envelope = Lab.parse(forged_prep["formatted"])
    case kind
    when "altered" then forged_envelope["execution_receipts"][0]["tool_result"]["ok"] = false
    when "cross_event" then forged_envelope["execution_receipts"][0]["call_index"] = 8
    when "reordered" then forged_envelope["execution_receipts"].reverse!
    when "dropped" then forged_envelope["execution_receipts"].pop
    end
    forged_prep["formatted"] = Lab.encode(forged_envelope)
    forged_context = copy.call(valid_context)
    forged_context["formatted"] = forged_prep["formatted"]
    forged_context["preparation"] = forged_prep
    raises.call(Lab::IntegrityError) do
      replay_store.synchronize do
        replay_store.append("model_intent", { "event_id" => "receipt-replay", "call_index" => 4, "context" => forged_context })
      end
    end
  end
  replay_store.synchronize do
    replay_store.append("model_intent", { "event_id" => "receipt-replay", "call_index" => 4, "context" => valid_context })
  end
  replay_store.close
  replayed = Lab::Store.open(path: replay_path, config: config)
  intact_replay = replayed.integrity["ok"] &&
    replayed.snapshot.dig("events", "receipt-replay", "calls", 4, "context") == valid_context
  replayed.close
  last_record = File.join(replay_path, format("commit-%08d.json", snapshot.fetch("transaction_count") + 1))
  journal_record = Lab.parse(File.binread(last_record))
  on_disk_envelope = Lab.parse(journal_record.dig("payload", "context", "formatted"))
  on_disk_envelope["execution_receipts"][0]["tool_result"]["ok"] = false
  journal_record.dig("payload", "context")["formatted"] = Lab.encode(on_disk_envelope)
  journal_record.dig("payload", "context", "preparation")["formatted"] = Lab.encode(on_disk_envelope)
  journal_record["digest"] = Lab.digest(journal_record.reject { |key, _| key == "digest" })
  File.binwrite(last_record, Lab.encode(journal_record) + "\n")
  tampered_reopen = begin
    tampered_store = Lab::Store.open(path: replay_path, config: config)
    begin
      raises.call(Lab::IntegrityError) { tampered_store.integrity }
    ensure
      tampered_store.close
    end
  rescue Lab::IntegrityError
    true
  end
  replay_checks = [interrupted, fired, forged_replays.all?, intact_replay, tampered_reopen]
end
check.call("Store reducer and reopen replay reject forged altered, cross-event, reordered and dropped receipts") do
  replay_checks == [true, true, true, true, true]
end

check.call("essential byte overflow fails before broker preparation or generation") do
  huge = copy.call(state); huge["events"]["event-a"]["content"] = "x" * 13_000
  local = A13FixtureClient.new
  begin
    Lab::TokenContext.initial(state: huge, event_id: "event-a", config: config)
    false
  rescue Lab::ContextBudgetExceeded
    local.requests.empty? && local.generations.empty?
  end
end
check.call("essential token overflow is rejected without any generation") do
  too_many = Lab::QwenBrokerSession.new(client: A13FixtureClient.new(token_count: 3073), observer: -> {}, on_receipt: ->(_r) {},
    before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
    execution_profile: Lab::Config::STREAM_PROFILE, message_profile: Projection::PROFILE_RECEIPTS)
  too_many.instance_variable_set(:@calls, 4)
  rejected = too_many.dispatch({ "operation" => "prepare_context", "call_index" => 4, "input" => Lab.encode(trim) }, deadline: deadline.call)
  rejected["ok"] == false && too_many.instance_variable_get(:@client).generations.empty?
end
check.call("receipt expansion past the byte cap after token trimming is rejected") do
  byte_state = copy.call(state)
  byte_state["events"]["event-a"]["calls"] = [
    { "response" => "not-json", "result" => { "ok" => false, "reason" => "invalid_action" } },
    { "response" => '{"action":"wait"}', "result" => { "ok" => true } }
  ]
  byte_state["events"]["event-a"]["content"] = "x" * 10_000
  while Lab::TokenContext.initial(state: byte_state, event_id: "event-a", config: config).bytesize < Lab::TokenContext::MAX_BYTES - 50
    byte_state["events"]["event-a"]["content"] << "x"
  end
  while Lab::TokenContext.initial(state: byte_state, event_id: "event-a", config: config).bytesize > Lab::TokenContext::MAX_BYTES
    byte_state["events"]["event-a"]["content"] = byte_state["events"]["event-a"]["content"].byteslice(0...-1)
  end
  byte_client = A13FixtureClient.new(token_count: ->(messages) { messages.count { |message| message["role"] == "tool" } > 1 ? 4000 : 100 })
  byte_broker = Lab::QwenBrokerSession.new(client: byte_client, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
    protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
    execution_profile: Lab::Config::STREAM_PROFILE, message_profile: Projection::PROFILE_RECEIPTS)
  byte_broker.instance_variable_set(:@calls, 2)
  byte_rejected = byte_broker.dispatch({ "operation" => "prepare_context", "call_index" => 2,
    "input" => Lab::TokenContext.initial(state: byte_state, event_id: "event-a", config: config) }, deadline: deadline.call)
  byte_context = Lab::TokenContext.finalize(state: byte_state, event_id: "event-a", config: config,
    preparation: byte_rejected.fetch("preparation"), rejected: true)
  byte_rejected["ok"] == false && byte_rejected.dig("preparation", "measurements").last["input_tokens"] <= 3072 &&
    byte_rejected.dig("preparation", "formatted").bytesize > Lab::TokenContext::MAX_BYTES &&
    byte_context.dig("manifest", "input_tokens") <= 3072 && byte_client.generations.empty?
end

check.call("prepared context policy is bound into manifest and old/new broker profiles cannot mismatch") do
  old_broker = Lab::QwenBrokerSession.new(client: A13FixtureClient.new, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
    protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072, execution_profile: Lab::Config::STREAM_PROFILE)
  old_broker.instance_variable_set(:@calls, 4)
  finalized.dig("manifest", "context_policy") == Receipt::POLICY &&
    raises.call(Lab::ValidationError) do
      old_broker.dispatch({ "operation" => "prepare_context", "call_index" => 4, "input" => Lab.encode(trim) }, deadline: deadline.call)
    end
end

# An interrupted intent is durable and resume must stop before another host call.
faulted = false
Dir.mktmpdir("continuity-a13-interrupt-") do |directory|
  fault = lambda do |point, row|
    if !faulted && point == :after_commit && row["kind"] == "model_intent"
      faulted = true
      raise IOError, "synthetic interruption"
    end
  end
  store = Lab::Store.create(path: File.join(directory, "store"), config: config, fault: fault)
  client = A13FixtureClient.new
  pipe = Lab::PipeBackend.new
  pipe.define_singleton_method(:prepare) do |call_index:, input:|
    preparation = Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [
      Lab::TokenContext.measurement(input, "fixture-prompt", Array.new(100, 17))
    ], input_budget: 3072, call_index: call_index)
    preparation
  end
  pipe.define_singleton_method(:call) { |**_args| client.generations << :unexpected; '{"action":"wait"}' }
  runtime = Lab::Runtime.new(store: store, backend: pipe)
  interrupted = raises.call(Lab::IntegrityError) { runtime.submit(event_id: "pending-a13", content: "pending request") }
  before = client.generations.length
  resume = Lab::Runtime.new(store: store, backend: pipe).resume(event_id: "pending-a13")
  check.call("committed model intent remains unresolved and resume performs no repeated generation") do
    interrupted && faulted && resume["reason"] == "unresolved_model_intent" && client.generations.length == before
  end
  store.close
end

if ISOLATION
  Dir.mktmpdir("continuity-a13-isolation-") do |root|
    [Projection::PROFILE_RECEIPTS, Projection::PROFILE_RECEIPT_PAIRS].each_with_index do |profile, index|
      suffix = index.zero? ? "array" : "pairs"
      state_directory = File.join(root, "state-#{suffix}")
      Dir.mkdir(state_directory, 0o700)
      leases = SoulCore::ModelRuntimeLeaseStore.new(root: File.join(root, "leases-#{suffix}"))
      snapshot_provider = -> { { "captured_at" => Process.clock_gettime(Process::CLOCK_MONOTONIC), "core" => "amd-free",
        "profile_id" => "nvidia-fallback", "model_file" => "Qwen3-8B-Q4_K_M.gguf", "service_active" => true,
        "active_slots" => 0, "pending_transition" => false, "dedicated_window" => true } }
      gate = Lab::AdmissionGate.new(lease_store: leases, snapshot_provider: snapshot_provider)
      store = Lab::Store.create(path: File.join(state_directory, "store"), config: config)
      store.close
      client = A13FixtureClient.new(response: '{"action":"reply","content":"fixture only"}')
      isolated_broker = Lab::QwenBrokerSession.new(client: client, observer: -> {}, on_receipt: ->(_row) {},
        before_generation: -> {}, protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072,
        execution_profile: Lab::Config::STREAM_PROFILE, message_profile: profile)
      runner = Lab::SandboxRunner.new(state_directory: state_directory, timeout_seconds: 430, execution_profile: Lab::Config::STREAM_PROFILE)
      event_id = "isolation-a13-#{suffix}"
      result = runner.run(request: { "mode" => "qwen_v6_run", "create" => false, "event_id" => event_id,
        "content" => "Fixed synthetic reply", "corpus" => [] }, broker: isolated_broker, admission: gate)
      check.call("actual isolated v6 #{suffix} worker runs with matching profile and is reaped") do
        result.dig("result", "receipt", "reply") == "fixture only" && runner.pid && raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) }
      end
      mismatched = Lab::QwenBrokerSession.new(client: A13FixtureClient.new, observer: -> {}, on_receipt: ->(_r) {}, before_generation: -> {},
        protocol_version: Lab::QwenBrokerSession::V4_PROMPT_VERSION, input_budget: 3072, execution_profile: Lab::Config::STREAM_PROFILE)
      check.call("isolated v6 #{suffix} worker rejects a legacy broker context profile") do
        raises.call(Lab::ValidationError) { runner.run(request: { "mode" => "qwen_v6_run", "create" => false, "event_id" => "mismatch-#{suffix}",
          "content" => "synthetic", "corpus" => [] }, broker: mismatched, admission: gate) }
      end
      store = Lab::Store.open(path: File.join(state_directory, "store"), config: config)
      runner.run(request: { "mode" => "qwen_v6_resume", "event_id" => event_id }, broker: isolated_broker, admission: gate)
      check.call("isolated v6 #{suffix} terminal resume reaps child and does not generate twice") do
        client.generations.length == 1 && raises.call(Errno::ESRCH) { Process.kill(0, runner.pid) } && store.integrity["ok"]
      end
      store.close
    end
  end
  puts "PASS: #{checks} A13 deterministic and isolated-worker checks; synthetic backend only, no live inference"
else
  puts "PASS: #{checks} A13 deterministic receipt checks; no subprocess or live inference"
end
