#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "support/continuity_protocol_a25"

Protocol = ContinuityProtocolA25
Cases = ContinuityCasesA25
checks = 0
check = lambda do |label, condition = nil, &block|
  condition = block.call if block
  raise "FAIL: #{label}" unless condition
  checks += 1
  puts "PASS: #{label}"
end
raises = lambda do |&block|
  block.call
  false
rescue ArgumentError
  true
end

cases = Cases.cases
item = cases.first
check.call("fixture source remains valid") { Cases.validate! && cases.length == 6 }

payloads = [false, true].product(%w[strict relaxed]).to_h do |thinking, contract|
  [[thinking, contract], Protocol.payload(item: item, thinking: thinking, contract: contract, seed: Protocol::SEEDS.first)]
end
check.call("native chat toggles, separate reasoning channel, and output contracts") do
  payloads.all? do |(thinking, contract), request|
    request["chat_template_kwargs"] == { "enable_thinking" => thinking } &&
      request["reasoning_format"] == "deepseek" &&
      request.dig("response_format", "type") == (contract == "strict" ? "json_schema" : "text") &&
      request["stream"] == false && request["cache_prompt"] == false && request["verbose"] == true
  end
end
check.call("strict schema binds all and only requested final fields") do
  schema = payloads.fetch([true, "strict"]).dig("response_format", "json_schema", "schema")
  schema == Cases.schema(item) && schema["additionalProperties"] == false &&
    schema["required"] == item["answer_fields"]
end
check.call("pinned common sampler, seed and ordinary cap") do
  payloads.values.all? do |request|
    request.slice("temperature", "top_p", "top_k", "min_p", "presence_penalty", "repeat_penalty", "seed", "max_tokens") ==
      { "temperature" => 0.6, "top_p" => 0.95, "top_k" => 20, "min_p" => 0.0,
        "presence_penalty" => 0.5, "repeat_penalty" => 1.05, "seed" => Protocol::SEEDS.first,
        "max_tokens" => 768 }
  end
end
check.call("model-visible payload excludes labels, oracles and other samples") do
  payloads.values.all? do |request|
    public_task = JSON.parse(request.fetch("messages").last.fetch("content"))
    public_task == Cases.public_case(item) &&
      (public_task.keys & %w[id family difficulty expected oracle previous_final_answer]).empty? &&
      !(request.keys & %w[model expected oracle family difficulty]).any?
  end
end

prior = JSON.generate(item.fetch("expected"))
revision = Protocol.payload(item: item, thinking: true, contract: "strict", seed: Protocol::SEEDS.first, previous: prior)
check.call("reconsideration receives only its prior final and unchanged public task") do
  task = JSON.parse(revision.fetch("messages").last.fetch("content"))
  task.fetch("previous_final_answer") == prior && task.fetch("instruction") == Protocol::RECONSIDER_INSTRUCTION &&
    task.reject { |key, _| %w[previous_final_answer instruction].include?(key) } == Cases.public_case(item) &&
    revision["messages"].length == 2 && !JSON.generate(revision).include?("reasoning_content")
end
check.call("invalid prior finals and tampered fixtures are refused") do
  raises.call { Protocol.payload(item: item, thinking: false, contract: "strict", seed: Protocol::SEEDS.first, previous: "<think>secret</think>") } &&
    raises.call { Protocol.payload(item: item, thinking: false, contract: "strict", seed: Protocol::SEEDS.first, previous: " ") } &&
    raises.call { Protocol.payload(item: item.merge("question" => "tampered"), thinking: false, contract: "strict", seed: Protocol::SEEDS.first) } &&
    raises.call { Protocol.payload(item: item, thinking: "yes", contract: "strict", seed: Protocol::SEEDS.first) } &&
    raises.call { Protocol.payload(item: item, thinking: false, contract: "other", seed: Protocol::SEEDS.first) } &&
    raises.call { Protocol.payload(item: item, thinking: false, contract: "strict", seed: 7) }
end

hard = cases.find { |row| row["difficulty"] == "hard" }
extended = Protocol.payload(item: hard, thinking: true, contract: "relaxed", seed: Protocol::SEEDS.last, extended: true)
check.call("extended budget is restricted to hard direct ON relaxed cells") do
  extended["max_tokens"] == 1536 &&
    raises.call { Protocol.payload(item: item, thinking: true, contract: "relaxed", seed: Protocol::SEEDS.last, extended: true) } &&
    raises.call { Protocol.payload(item: hard, thinking: false, contract: "relaxed", seed: Protocol::SEEDS.last, extended: true) } &&
    raises.call { Protocol.payload(item: hard, thinking: true, contract: "strict", seed: Protocol::SEEDS.last, extended: true) } &&
    raises.call { Protocol.payload(item: hard, thinking: true, contract: "relaxed", seed: Protocol::SEEDS.last, previous: "x", extended: true) }
end

valid_body = { "choices" => [{ "finish_reason" => "stop", "message" =>
  { "role" => "assistant", "reasoning_content" => "private internal thought", "content" => prior } }],
  "usage" => { "prompt_tokens" => 35, "completion_tokens" => 42 },
  "__verbose" => { "generation_settings" => { "n_predict" => 768, "seed" => Protocol::SEEDS.first,
    "temperature" => 0.6 } } }
result = Protocol.parse(valid_body, item: item, contract: "strict")
check.call("strict final parses and scores separately from hidden reasoning") do
  result["status"] == "complete" && result["final_answer"] == prior && result.dig("strict_score", "correct") == true &&
    result["semantic_status"] == "strict_exact_check_only" && result["reasoning_present"] == true &&
    result["reasoning_chars"] == "private internal thought".length && result["reasoning_tokens"].nil? &&
    result.dig("effective_settings", "seed") == Protocol::SEEDS.first &&
    !JSON.generate(result).include?("private internal thought")
end
incorrect_body = JSON.parse(JSON.generate(valid_body))
incorrect_body["choices"][0]["message"]["content"] = JSON.generate(item["expected"].merge("total_price" => "351 credits"))
incorrect = Protocol.parse(incorrect_body, item: item, contract: "strict")
check.call("valid but wrong strict answer stays separate from contract failure") do
  incorrect["status"] == "complete" && incorrect.dig("strict_score", "valid") == true &&
    incorrect.dig("strict_score", "correct") == false
end
relaxed_body = JSON.parse(JSON.generate(valid_body))
relaxed_body["choices"][0]["message"]["content"] = "vendor: Hearthline Supply; total_price: 352 credits"
relaxed = Protocol.parse(relaxed_body, item: item, contract: "relaxed")
check.call("relaxed prose remains pending identity-masked semantic assessment") do
  relaxed["status"] == "complete" && relaxed["semantic_status"] == "pending_identity_masked_assessment" &&
    !relaxed.key?("strict_score")
end
check.call("length exhaustion, missing final and invalid final are distinct") do
  limited = JSON.parse(JSON.generate(valid_body))
  limited["choices"][0]["finish_reason"] = "length"
  empty = JSON.parse(JSON.generate(valid_body))
  empty["choices"][0]["message"]["content"] = ""
  invalid = JSON.parse(JSON.generate(valid_body))
  invalid["choices"][0]["message"]["content"] = "not json"
  leaked = JSON.parse(JSON.generate(valid_body))
  leaked["choices"][0]["message"]["content"] = "<think>leak</think>final"
  Protocol.parse(limited, item: item, contract: "strict")["status"] == "output_limit" &&
    Protocol.parse(empty, item: item, contract: "strict")["status"] == "missing_final" &&
    Protocol.parse(invalid, item: item, contract: "strict")["status"] == "invalid_contract" &&
    Protocol.parse(leaked, item: item, contract: "relaxed")["status"] == "invalid_contract"
end
check.call("oversized completed final is a size limit, not a contract error or reconsideration input") do
  oversized = JSON.parse(JSON.generate(valid_body))
  oversized["choices"][0]["message"]["content"] = "x" * (Protocol::MAX_PREVIOUS_BYTES + 1)
  parsed = Protocol.parse(oversized, item: item, contract: "relaxed")
  parsed["status"] == "final_size_limit" && parsed["final_bytes"] == Protocol::MAX_PREVIOUS_BYTES + 1 &&
    parsed["final_answer"].nil? && !Protocol.final_available?(parsed) &&
    Protocol.prerequisite_skip(parsed)["status"] == "skipped_prerequisite"
end
check.call("contract-invalid but bounded final text remains available to its own reconsideration") do
  malformed = JSON.parse(JSON.generate(valid_body))
  malformed["choices"][0]["message"]["content"] = "vendor: Hearthline Supply; total_price: 352 credits"
  wrong_keys = JSON.parse(JSON.generate(valid_body))
  wrong_keys["choices"][0]["message"]["content"] = JSON.generate("vendor" => "Hearthline Supply")
  [malformed, wrong_keys].all? do |body|
    parsed = Protocol.parse(body, item: item, contract: "strict")
    parsed["status"] == "invalid_contract" && parsed["final_answer"] == body.dig("choices", 0, "message", "content") &&
      Protocol.final_available?(parsed) && Protocol.prerequisite_skip(parsed).nil? &&
      JSON.parse(Protocol.payload(item: item, thinking: false, contract: "strict", seed: Protocol::SEEDS.first,
        previous: parsed["final_answer"]).fetch("messages").last.fetch("content"))["previous_final_answer"] == parsed["final_answer"]
  end
end
check.call("relaxed JSON violates prose contract without erasing semantic evidence") do
  structured = Protocol.parse(valid_body, item: item, contract: "relaxed")
  structured["status"] == "invalid_contract" && structured["final_answer"] == prior &&
    structured["semantic_status"] == "pending_identity_masked_assessment" &&
    Protocol.final_available?(structured) && Protocol.prerequisite_skip(structured).nil?
end
check.call("provider errors do not become model semantic failures") do
  Protocol.parse({ "error" => { "message" => "unavailable" } }, item: item, contract: "strict")["status"] == "provider_error" &&
    Protocol.parse("{not json", item: item, contract: "strict")["status"] == "provider_error" &&
    Protocol.parse({}, item: item, contract: "relaxed")["status"] == "provider_error"
end
check.call("missing initial final skips only its paired reconsideration") do
  Protocol.prerequisite_skip(result).nil? &&
    Protocol.prerequisite_skip({ "status" => "output_limit", "final_answer" => nil })["status"] == "skipped_prerequisite" &&
    Protocol.prerequisite_skip({ "status" => "complete", "final_answer" => "x" * 4097 })["status"] == "skipped_prerequisite" &&
    !Protocol.final_available?({ "status" => "invalid_contract", "final_answer" => "<think>leak</think>final" })
end

feasibility = Protocol.feasibility_plan
check.call("eight unrelated feasibility cells are distinct from scored cases") do
  feasibility.length == 8 && feasibility.all? { |row| row["kind"] == "feasibility" && row["case_id"] == Protocol.feasibility_item["id"] } &&
    feasibility.map { |row| [row["model"], row["thinking"], row["contract"]] }.uniq.length == 8 &&
    !cases.map { |row| row["id"] }.include?(Protocol.feasibility_item["id"])
end

plans = Protocol::SEEDS.to_h { |seed| [seed, Protocol.plan(seed: seed)] }
check.call("each seed has exactly 102 scored calls, 96 paired plus 6 extended") do
  plans.all? do |seed, plan|
    plan.length == 102 && plan.all? { |row| row["kind"] == "scored" && row["seed"] == seed } &&
      plan.count { |row| row["stage"] == "initial" } == 48 &&
      plan.count { |row| row["stage"] == "reconsider" } == 48 &&
      plan.count { |row| row["stage"] == "extended_direct" } == 6 &&
      plan.map { |row| row["call_id"] }.uniq.length == 102
  end
end
check.call("each reconsideration immediately follows its own initial") do
  plans.values.all? do |plan|
    plan.each_with_index.all? do |row, index|
      row["stage"] != "reconsider" || (index.positive? && plan[index - 1]["call_id"] == row["requires_call_id"] &&
        plan[index - 1]["pair_id"] == row["pair_id"])
    end
  end
end
check.call("all eight condition cells repeat once per task and seed") do
  plans.all? do |_seed, plan|
    cases.all? do |case_row|
      initials = plan.select { |row| row["case_id"] == case_row["id"] && row["stage"] == "initial" }
      initials.length == 8 && initials.map { |row| [row["model"], row["thinking"], row["contract"]] }.uniq.length == 8
    end
  end
end
check.call("extended direct calls compare to hard relaxed OFF pairs at equal aggregate allowances") do
  plans.values.all? do |plan|
    plan.select { |row| row["stage"] == "extended_direct" }.all? do |row|
      paired = plan.select { |other| other["pair_id"] == row["compares_to_pair_id"] }
      row["thinking"] == true && row["contract"] == "relaxed" && row["budget_tokens"] == 1536 &&
        row["deadline_seconds"] == 90 && paired.map { |other| other["stage"] }.sort == %w[initial reconsider] &&
        paired.all? { |other| other["thinking"] == false && other["budget_tokens"] == 768 && other["deadline_seconds"] == 45 }
    end
  end
end
check.call("three seeds counterbalance initial case/condition order without changing cells") do
  orders = plans.values.map { |plan| plan.select { |row| row["stage"] == "initial" }.map { |row| [row["case_id"], row["model"], row["thinking"], row["contract"]] } }
  orders.uniq.length == 3 && plans.values.sum(&:length) == 306
end
check.call("every planned entry is accepted by pure payload builder with its declared budget") do
  (plans.values.flatten + feasibility).all? do |row|
    case_item = row["kind"] == "feasibility" ? Protocol.feasibility_item : cases.find { |entry| entry["id"] == row["case_id"] }
    previous = row["stage"] == "reconsider" ? "prior final only" : nil
    request = Protocol.payload(item: case_item, thinking: row["thinking"], contract: row["contract"],
      seed: row["seed"], previous: previous, extended: row["extended"])
    request["max_tokens"] == row["budget_tokens"] && request["seed"] == row["seed"]
  end
end

puts "PASS: #{checks} deterministic A25 protocol checks"
