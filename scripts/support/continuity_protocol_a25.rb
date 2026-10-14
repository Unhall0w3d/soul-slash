# frozen_string_literal: true

require "json"
require_relative "continuity_cases_a25"

# Pure, detached A25 request and result protocol. The caller owns transport,
# admission, deadlines, receipts, and semantic assessment of prose.
module ContinuityProtocolA25
  Cases = ContinuityCasesA25
  SEEDS = [104_729, 130_363, 155_921].freeze
  MODELS = %w[qwen amd].freeze
  CONTRACTS = %w[strict relaxed].freeze
  ORDINARY_TOKENS = 768
  EXTENDED_TOKENS = 1536
  ORDINARY_SECONDS = 45
  EXTENDED_SECONDS = 90
  MAX_PREVIOUS_BYTES = 4096

  FEASIBILITY_ITEM = {
    "id" => "a25-feasibility-unscored", "family" => "feasibility", "difficulty" => "unscored",
    "question" => "From the calibration note, state the marker_color and marker_number.",
    "evidence" => [{ "id" => "calibration-note", "text" => "Fictional calibration note: marker_color=violet; marker_number=7." }],
    "answer_fields" => %w[marker_color marker_number],
    "expected" => { "marker_color" => "violet", "marker_number" => "7" },
    "oracle" => { "marker_color" => "violet", "marker_number" => "7" }
  }.freeze

  STRICT_INSTRUCTION = "Answer using only the supplied evidence. Return only one JSON object with exactly the requested answer_fields, each value a short string. Keep required units and stated unknowns; never infer an absent fact is false. No tools or actions are available."
  RELAXED_INSTRUCTION = "Answer using only the supplied evidence. Give a concise prose answer covering every requested answer_field by name. Keep required units and stated unknowns; never infer an absent fact is false. Do not use JSON. No tools or actions are available."
  RECONSIDER_INSTRUCTION = "Reconsider the prior final answer using only the same task evidence. Correct it only if the evidence supports a correction; otherwise preserve it. No reviewer feedback or correctness hint is supplied. Return a new final answer."

  def self.feasibility_item
    copy(FEASIBILITY_ITEM)
  end

  # Runner supplies the attested model alias. This method never addresses a host.
  def self.payload(item:, thinking:, contract:, seed:, previous: nil, extended: false)
    validate_condition!(item, thinking, contract, seed, previous, extended)
    task = Cases.public_case(item)
    task["previous_final_answer"] = previous if previous
    task["instruction"] = RECONSIDER_INSTRUCTION if previous
    system = contract == "strict" ? STRICT_INSTRUCTION : RELAXED_INSTRUCTION
    response_format = contract == "strict" ?
      { "type" => "json_schema", "json_schema" => { "schema" => Cases.schema(item) } } :
      { "type" => "text" }
    {
      "messages" => [{ "role" => "system", "content" => system },
                     { "role" => "user", "content" => JSON.generate(task) }],
      "chat_template_kwargs" => { "enable_thinking" => thinking },
      "reasoning_format" => "deepseek",
      "response_format" => response_format,
      "max_tokens" => extended ? EXTENDED_TOKENS : ORDINARY_TOKENS,
      "temperature" => 0.6, "top_p" => 0.95, "top_k" => 20, "min_p" => 0.0,
      "presence_penalty" => 0.5, "repeat_penalty" => 1.05,
      "seed" => seed, "stream" => false, "cache_prompt" => false,
      # b9851 chat responses expose __verbose.generation_settings when requested.
      # The runner must verify this on both installed builds before attesting it.
      "verbose" => true
    }
  end

  # No reasoning text escapes this projection. The runner retains the raw reply
  # separately and handles HTTP failures, request settlement and timeouts.
  def self.parse(body, item:, contract:)
    known_item!(item)
    raise ArgumentError, "unknown contract" unless CONTRACTS.include?(contract)
    data = body.is_a?(String) ? JSON.parse(body) : body
    return failure("provider_error", "invalid response envelope") unless data.is_a?(Hash)
    return failure("provider_error", "server returned error") if data.key?("error")

    choices = data["choices"]
    usage = data["usage"]
    return failure("provider_error", "invalid choices or usage") unless choices.is_a?(Array) && choices.length == 1 &&
      choices.first.is_a?(Hash) && usage.is_a?(Hash) && usage["prompt_tokens"].is_a?(Integer) &&
      usage["prompt_tokens"] >= 0 && usage["completion_tokens"].is_a?(Integer) && usage["completion_tokens"] >= 0
    choice = choices.first
    message = choice["message"]
    return failure("provider_error", "invalid assistant message") unless message.is_a?(Hash) &&
      message["role"] == "assistant"
    reasoning = message["reasoning_content"]
    return failure("provider_error", "invalid reasoning channel") unless reasoning.nil? || reasoning.is_a?(String)
    result = { "finish_reason" => choice["finish_reason"],
      "prompt_tokens" => usage["prompt_tokens"], "completion_tokens" => usage["completion_tokens"],
      "reasoning_present" => reasoning.is_a?(String) && !reasoning.empty?,
      "reasoning_chars" => reasoning&.length || 0,
      "reasoning_tokens" => nil,
      "effective_settings" => effective_settings(data) }
    return result.merge("status" => "output_limit", "final_answer" => nil) if choice["finish_reason"] == "length"
    return result.merge("status" => "provider_error", "error" => "unexpected finish reason", "final_answer" => nil) unless choice["finish_reason"] == "stop"

    content = message["content"]
    return result.merge("status" => "missing_final", "final_answer" => nil) unless content.is_a?(String) &&
      content.valid_encoding? && !content.strip.empty?
    return result.merge("status" => "invalid_contract", "final_answer" => nil) if content.include?("<think>") || content.include?("</think>")
    # The raw reply remains in the runner receipt, but a final too large for the
    # next input budget is a prerequisite limit, not a response-contract error.
    return result.merge("status" => "final_size_limit", "final_answer" => nil,
      "final_bytes" => content.bytesize) if content.bytesize > MAX_PREVIOUS_BYTES
    if contract == "strict"
      begin
        answer = JSON.parse(content)
      rescue JSON::ParserError
        return result.merge("status" => "invalid_contract", "final_answer" => content,
          "semantic_status" => "pending_identity_masked_assessment")
      end
      score = Cases.score(answer, item)
      return result.merge("status" => "invalid_contract", "final_answer" => content,
        "strict_score" => score, "semantic_status" => "pending_identity_masked_assessment") unless score["valid"]
      return result.merge("status" => "complete", "final_answer" => content, "strict_score" => score,
        "semantic_status" => "strict_exact_check_only")
    end
    begin
      structured = JSON.parse(content)
      if structured.is_a?(Hash) || structured.is_a?(Array)
        return result.merge("status" => "invalid_contract", "final_answer" => content,
          "semantic_status" => "pending_identity_masked_assessment")
      end
    rescue JSON::ParserError
      nil
    end
    result.merge("status" => "complete", "final_answer" => content,
      "semantic_status" => "pending_identity_masked_assessment")
  rescue JSON::ParserError, TypeError
    failure("provider_error", "invalid response JSON")
  end

  # When the preceding answer lacks a usable final, do not issue a new model
  # call or substitute an answer from a different condition.
  def self.final_available?(first_result)
    first_result.is_a?(Hash) && %w[complete invalid_contract].include?(first_result["status"]) &&
      first_result["final_answer"].is_a?(String) && first_result["final_answer"].valid_encoding? &&
      first_result["final_answer"].bytesize.between?(1, MAX_PREVIOUS_BYTES) &&
      !first_result["final_answer"].strip.empty? &&
      !first_result["final_answer"].include?("<think>") && !first_result["final_answer"].include?("</think>")
  end

  def self.prerequisite_skip(first_result)
    return nil if final_available?(first_result)
    { "status" => "skipped_prerequisite", "reason" => "paired initial call has no valid final answer" }
  end

  def self.feasibility_plan
    conditions = MODELS.product([false, true], CONTRACTS)
    conditions.each_with_index.map do |(model, thinking, contract), index|
      { "kind" => "feasibility", "case_id" => FEASIBILITY_ITEM.fetch("id"),
        "model" => model, "thinking" => thinking, "contract" => contract,
        "seed" => SEEDS.first, "stage" => "direct", "extended" => false,
        "budget_tokens" => ORDINARY_TOKENS, "deadline_seconds" => ORDINARY_SECONDS,
        "call_id" => "feasibility-%02d" % (index + 1) }
    end
  end

  def self.plan(seed:)
    seed_index = SEEDS.index(seed) or raise ArgumentError, "unregistered seed"
    cases = Cases.cases.rotate(seed_index * 2)
    conditions = MODELS.product([false, true], CONTRACTS)
    rows = []
    cases.each_with_index do |item, case_index|
      conditions.rotate((case_index * 3 + seed_index * 2) % conditions.length).each do |model, thinking, contract|
        pair_id = [item.fetch("id"), model, thinking ? "on" : "off", contract, seed].join("-")
        common = { "kind" => "scored", "case_id" => item.fetch("id"), "model" => model,
          "thinking" => thinking, "contract" => contract, "seed" => seed,
          "pair_id" => pair_id, "extended" => false,
          "budget_tokens" => ORDINARY_TOKENS, "deadline_seconds" => ORDINARY_SECONDS }
        rows << common.merge("call_id" => "#{pair_id}-initial", "stage" => "initial")
        rows << common.merge("call_id" => "#{pair_id}-reconsider", "stage" => "reconsider",
          "requires_call_id" => "#{pair_id}-initial")
      end
      next unless item.fetch("difficulty") == "hard"
      MODELS.rotate((case_index + seed_index) % MODELS.length).each do |model|
        pair_id = [item.fetch("id"), model, "off", "relaxed", seed].join("-")
        rows << { "kind" => "scored", "case_id" => item.fetch("id"), "model" => model,
          "thinking" => true, "contract" => "relaxed", "seed" => seed,
          "pair_id" => "#{item.fetch('id')}-#{model}-on-relaxed-#{seed}-extended",
          "call_id" => "#{item.fetch('id')}-#{model}-on-relaxed-#{seed}-extended",
          "stage" => "extended_direct", "extended" => true,
          "compares_to_pair_id" => pair_id,
          "budget_tokens" => EXTENDED_TOKENS, "deadline_seconds" => EXTENDED_SECONDS }
      end
    end
    raise "incomplete A25 seed plan" unless rows.length == 102 && rows.map { |row| row.fetch("call_id") }.uniq.length == 102
    rows
  end

  def self.known_item!(item)
    candidate = Cases.cases.find { |row| row["id"] == item["id"] } if item.is_a?(Hash)
    candidate ||= FEASIBILITY_ITEM if item.is_a?(Hash) && item["id"] == FEASIBILITY_ITEM["id"]
    raise ArgumentError, "item is not a frozen A25 fixture" unless candidate && item == candidate
    item
  end
  private_class_method :known_item!

  def self.validate_condition!(item, thinking, contract, seed, previous, extended)
    known_item!(item)
    raise ArgumentError, "thinking must be boolean" unless thinking == true || thinking == false
    raise ArgumentError, "unknown contract" unless CONTRACTS.include?(contract)
    raise ArgumentError, "unregistered seed" unless SEEDS.include?(seed)
    raise ArgumentError, "extended call requires hard/ON/relaxed/direct" if extended &&
      !(item["difficulty"] == "hard" && thinking && contract == "relaxed" && previous.nil?)
    return if previous.nil?
    raise ArgumentError, "invalid prior final answer" unless previous.is_a?(String) && previous.valid_encoding? &&
      previous.bytesize.between?(1, MAX_PREVIOUS_BYTES) && !previous.strip.empty? &&
      !previous.include?("<think>") && !previous.include?("</think>")
  end
  private_class_method :validate_condition!

  def self.effective_settings(data)
    settings = data.dig("__verbose", "generation_settings")
    return nil unless settings.is_a?(Hash)
    %w[n_predict temperature top_p top_k min_p presence_penalty repeat_penalty seed cache_prompt].to_h do |key|
      [key, settings[key]]
    end
  end
  private_class_method :effective_settings

  def self.failure(status, error)
    { "status" => status, "error" => error, "final_answer" => nil,
      "reasoning_present" => false, "reasoning_chars" => 0,
      "reasoning_tokens" => nil, "effective_settings" => nil }
  end
  private_class_method :failure

  def self.copy(value)
    JSON.parse(JSON.generate(value))
  end
  private_class_method :copy
end
