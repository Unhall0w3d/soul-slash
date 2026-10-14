#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "support/continuity_cases_a25"

Cases = ContinuityCasesA25
checks = 0
check = lambda do |label, condition = nil, &block|
  condition = block.call if block
  raise "FAIL: #{label}" unless condition
  checks += 1
  puts "PASS: #{label}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }

cases = Cases.cases
expected = {
  "a25-filter-easy" => { "vendor" => "Hearthline Supply", "total_price" => "352 credits" },
  "a25-filter-hard" => { "vendor" => "Pave Industrial", "total_cost" => "449 credits" },
  "a25-arithmetic-easy" => { "total_volume" => "168 litres", "remaining_volume" => "105 litres" },
  "a25-arithmetic-hard" => { "work_duration" => "330 minutes", "finish_time" => "13:15" },
  "a25-join-easy" => { "lubricant_code" => "Vela-4", "inspection_status" => "conditional",
    "warranty_expiry" => "not stated in supplied records" },
  "a25-join-hard" => { "service_interval_days" => "60 days", "disposition" => "review required",
    "warranty_end" => "not stated in supplied records" }
}.freeze

check.call("six unique fresh fixtures form three easy/hard family pairs within the input-word bound") do
  Cases.validate! && cases.length == 6 && cases.map { |item| item.fetch("id") }.uniq.length == 6 &&
    cases.map { |item| item.fetch("family") }.tally == Cases::FAMILY_COUNTS &&
    cases.map { |item| item.fetch("difficulty") }.tally == Cases::DIFFICULTY_COUNTS &&
    cases.group_by { |item| item.fetch("family") }.values.all? { |pair| pair.map { |item| item.fetch("difficulty") }.sort == %w[easy hard] } &&
    cases.all? { |item| item.fetch("evidence").map { |entry| entry.fetch("id") }.uniq.length == item.fetch("evidence").length } &&
    cases.all? { |item| ([item.fetch("question")] + item.fetch("evidence").map { |entry| entry.fetch("text") }).join(" ").split.length <= 350 }
end

check.call("each oracle matches independently declared expected values for all six tasks") do
  cases.all? { |item| item.fetch("expected") == expected.fetch(item.fetch("id")) && item.fetch("oracle") == expected.fetch(item.fetch("id")) }
end

check.call("filter fixtures require all listed constraints and minimize complete cost") do
  easy = cases.find { |item| item.fetch("id") == "a25-filter-easy" }
  hard = cases.find { |item| item.fetch("id") == "a25-filter-hard" }
  easy.fetch("evidence").first.fetch("text").include?("stock=42 cartridges; delivery=2 days") &&
    easy.fetch("evidence").first.fetch("text").include?("stock=70 cartridges; delivery=5 days") &&
    hard.fetch("evidence").first.fetch("text").include?("delivery=6 days") &&
    hard.fetch("evidence").first.fetch("text").include?("rating=110 C") &&
    hard.fetch("expected").fetch("total_cost") == "449 credits"
end

check.call("arithmetic oracles preserve explicit volume, duration, and clock units") do
  cases.select { |item| item.fetch("family") == "multi_step_arithmetic" }.all? do |item|
    item.fetch("expected").values.all? { |value| value.match?(/\A\d+(?: litres| minutes|:\d{2})\z/) }
  end && Cases::UNIT_POLICY.include?("Units are required")
end

check.call("revision joins select one linked current record and keep missing warranty as unknown, not false") do
  joins = cases.select { |item| item.fetch("family") == "revision_join_unknown" }
  joins.all? do |item|
    item.fetch("evidence").any? { |entry| entry.fetch("text").include?("current_revision=") } &&
      item.fetch("expected").values.include?(Cases::UNKNOWN_ANSWER) &&
      !item.fetch("expected").values.include?("false") &&
      item.fetch("question").match?(/absence is not evidence|do not infer that coverage is false/i)
  end
end

public_ok = cases.all? do |item|
  public_data = Cases.public_case(item)
  public_data.keys.sort == %w[answer_fields evidence question] &&
    public_data == { "question" => item.fetch("question"), "evidence" => item.fetch("evidence"),
      "answer_fields" => item.fetch("answer_fields") } &&
    (public_data.keys & %w[id family difficulty expected oracle]).empty? &&
    JSON.generate(public_data) !~ /"(?:expected|oracle|difficulty|family|a25-(?:filter|arithmetic|join)-(?:easy|hard))"/
end
check.call("public cases expose only question, evidence, and answer fields without fixture metadata or answer keys", public_ok)

schema_ok = cases.all? do |item|
  schema = Cases.schema(item)
  fields = item.fetch("answer_fields")
  schema == { "type" => "object", "properties" => fields.to_h { |field| [field, { "type" => "string" }] },
    "required" => fields, "additionalProperties" => false }
end
check.call("all response schemas require exactly the declared string-valued fields and reject extras", schema_ok)

first_snapshot = copy.call(cases.first)
cases.first.fetch("evidence").first["text"] = "tampered"
cases.first.fetch("answer_fields") << "leaked"
fresh_after_mutation = Cases.cases.first
public_projection = Cases.public_case(fresh_after_mutation)
public_projection.fetch("evidence").first["text"] = "changed projection"
independent = Cases.public_case(Cases.cases.first)
check.call("case and public projections are deep-copy independent", fresh_after_mutation == first_snapshot &&
  independent.fetch("evidence").first.fetch("text") == first_snapshot.fetch("evidence").first.fetch("text") &&
  independent.fetch("answer_fields") == first_snapshot.fetch("answer_fields"))

correct_answers_ok = Cases.cases.all? do |item|
  result = Cases.score(item.fetch("expected"), item)
  result.fetch("valid") && result.fetch("correct") &&
    result.fetch("correct_fields").sort == item.fetch("answer_fields").sort &&
    result.fetch("missing_fields").empty? && result.fetch("additional_fields").empty?
end
check.call("all six canonical oracle answers are valid and exactly correct", correct_answers_ok)

normalization_ok = Cases.cases.all? do |item|
  answer = item.fetch("expected").transform_values { |value| "  #{value.upcase.gsub(" ", "   ")}  " }
  score = Cases.score(answer, item)
  score.fetch("valid") && score.fetch("correct")
end
check.call("benign case and whitespace normalization is accepted", normalization_ok)

wrong_checks = Cases.cases.all? do |item|
  answer = copy.call(item.fetch("expected"))
  field = item.fetch("answer_fields").first
  answer[field] = "not the expected value"
  score = Cases.score(answer, item)
  score.fetch("valid") && !score.fetch("correct") && !score.fetch("correct_fields").include?(field)
end
check.call("well-shaped but wrong answers remain valid and score incorrect", wrong_checks)

sample = Cases.cases.first
missing = copy.call(sample.fetch("expected"))
missing.delete(sample.fetch("answer_fields").first)
missing_result = Cases.score(missing, sample)
additional = copy.call(sample.fetch("expected")).merge("unrequested" => "value")
additional_result = Cases.score(additional, sample)
non_string = copy.call(sample.fetch("expected"))
non_string[sample.fetch("answer_fields").first] = 42
non_string_result = Cases.score(non_string, sample)
check.call("missing, additional, and non-string fields invalidate strict response shape", !missing_result.fetch("valid") &&
  missing_result.fetch("missing_fields") == [sample.fetch("answer_fields").first] &&
  !additional_result.fetch("valid") && additional_result.fetch("additional_fields") == ["unrequested"] &&
  !non_string_result.fetch("valid"))

unit_case = Cases.cases.find { |item| item.fetch("id") == "a25-arithmetic-easy" }
unit_answer = copy.call(unit_case.fetch("expected"))
unit_answer["total_volume"] = "168"
unknown_case = Cases.cases.find { |item| item.fetch("id") == "a25-join-easy" }
unknown_answer = copy.call(unknown_case.fetch("expected"))
unknown_answer["warranty_expiry"] = "false"
check.call("required units remain exact content and source-unknown is accepted while false is not",
  Cases.score(unit_answer, unit_case).fetch("valid") && !Cases.score(unit_answer, unit_case).fetch("correct") &&
  Cases.score(unknown_case.fetch("expected"), unknown_case).fetch("correct") &&
  Cases.score(unknown_answer, unknown_case).fetch("valid") && !Cases.score(unknown_answer, unknown_case).fetch("correct"))

begin
  bad_shape = copy.call(sample)
  bad_shape.fetch("oracle").delete(sample.fetch("answer_fields").first)
  Cases.schema(bad_shape)
  schema_rejects_bad_fixture = false
rescue ArgumentError
  schema_rejects_bad_fixture = true
end
check.call("public/schema helpers reject malformed fixture answer contracts", schema_rejects_bad_fixture)

puts "PASS: #{checks} A25 synthetic fixture checks; no model inference or external access"
