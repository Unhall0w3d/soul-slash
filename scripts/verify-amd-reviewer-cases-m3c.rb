#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "support/amd_reviewer_cases_m3c"

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

puts "AMD reviewer M3c synthetic case verification:"
cases = AmdReviewerCasesM3c.cases
check.call("catalog validates exactly fourteen unique cases", AmdReviewerCasesM3c.validate! && cases.length == 14 && cases.map { |item| item.fetch("id") }.uniq.length == 14)

semantic = cases.select { |item| item.fetch("category") == "semantic" }
format_only = cases.select { |item| item.fetch("category") == "format_only" }
semantic_counts = semantic.group_by { |item| item.fetch("expected_verdict") }.transform_values(&:length)
check.call("semantic distribution is three per verdict plus two format-only supported cases", semantic_counts == {
  "supported" => 3, "contradicted" => 3, "insufficient_evidence" => 3, "mixed" => 3
} && format_only.length == 2 && format_only.all? { |item| item.fetch("expected_verdict") == "supported" })

aggregate_consistency = cases.all? do |item|
  claims = item.fetch("expected_claims").values
  aggregate = if claims.include?("contradicted") && claims.include?("insufficient_evidence")
                "mixed"
              elsif claims.include?("contradicted")
                "contradicted"
              elsif claims.include?("insufficient_evidence")
                "insufficient_evidence"
              else
                "supported"
              end
  aggregate == item.fetch("expected_verdict")
end
check.call("expected verdict aggregation follows mixed, contradicted, insufficient, supported precedence", aggregate_consistency &&
  cases.select { |item| item.fetch("expected_verdict") == "mixed" }.all? do |item|
    claims = item.fetch("expected_claims").values
    claims.include?("contradicted") && claims.include?("insufficient_evidence")
  end)

score_consistency = cases.all? do |item|
  oracle_score = AmdReviewerCasesM3c.score(item.fetch("oracle"), item)
  source_score = AmdReviewerCasesM3c.score(item.fetch("source_answer"), item)
  oracle_score == { "correct" => true, "correct_fields" => item.fetch("answer_fields").length,
    "total_fields" => item.fetch("answer_fields").length } &&
    if item.fetch("category") == "format_only"
      source_score.fetch("correct_fields").zero? && !source_score.fetch("correct")
    else
      source_score.fetch("correct_fields") == item.fetch("expected_claims").values.count("supported") &&
        source_score.fetch("total_fields") == item.fetch("answer_fields").length
    end
end
check.call("oracle scores exactly; semantic source fields match their claim labels and format-only unit omissions fail strict scoring", score_consistency)

normalization = cases.first
normalized_answer = normalization.fetch("oracle").transform_values { |value| "  #{value.upcase}  " }
check.call("scoring applies only strip and case-insensitive equality", AmdReviewerCasesM3c.score(normalized_answer, normalization).fetch("correct") &&
  !AmdReviewerCasesM3c.score({ "mass" => "4.250 kg" }, format_only.first).fetch("correct"))

public_cases = cases.map { |item| AmdReviewerCasesM3c.public_case(item) }
check.call("public projection is a strict prompt-field whitelist with no identifiers or audit metadata", public_cases.all? do |item|
  item.keys.sort == %w[question evidence answer_fields format_rules].sort &&
    (item.keys & %w[id source_answer oracle expected_claims expected_verdict category]).empty?
end)

copy_a = AmdReviewerCasesM3c.cases
copy_b = AmdReviewerCasesM3c.cases
copy_a.first.fetch("evidence").first["text"] = "changed copy"
public_a = AmdReviewerCasesM3c.public_case(copy_b.first)
public_a.fetch("evidence").first["text"] = "changed public projection"
check.call("case catalog and public projection return independent nested copies", copy_b.first.fetch("evidence").first.fetch("text") != "changed copy" &&
  AmdReviewerCasesM3c.cases.first.fetch("evidence").first.fetch("text") != "changed public projection")

bad_case_shape = normalization.reject { |key, _| key == "oracle" }
extra_case_shape = normalization.merge("seeded_answer" => normalization.fetch("source_answer"))
bad_aggregate = normalization.merge("expected_verdict" => "contradicted")
bad_claim = normalization.merge("expected_claims" => normalization.fetch("expected_claims").merge("tray_count" => "contradicted"))
bad_format = format_only.first.merge("format_rules" => { "mass" => { "unit" => "g" } })
bad_answer_missing = { "tray_count" => "12" }
bad_answer_extra = normalization.fetch("oracle").merge("extra" => "value")
bad_answer_type = normalization.fetch("oracle").merge("cultivar" => 17)
check.call("invalid case, aggregate, claim, format-rule, and answer shapes are rejected",
  raises.call(ArgumentError, "case shape mismatch") { AmdReviewerCasesM3c.public_case(bad_case_shape) } &&
  raises.call(ArgumentError, "case shape mismatch") { AmdReviewerCasesM3c.public_case(extra_case_shape) } &&
  raises.call(ArgumentError, "aggregate verdict mismatch") { AmdReviewerCasesM3c.public_case(bad_aggregate) } &&
  raises.call(ArgumentError, "claim/oracle consistency mismatch") { AmdReviewerCasesM3c.public_case(bad_claim) } &&
  raises.call(ArgumentError, "invalid format rule") { AmdReviewerCasesM3c.public_case(bad_format) } &&
  raises.call(ArgumentError, "answer fields mismatch") { AmdReviewerCasesM3c.score(bad_answer_missing, normalization) } &&
  raises.call(ArgumentError, "answer fields mismatch") { AmdReviewerCasesM3c.score(bad_answer_extra, normalization) } &&
  raises.call(ArgumentError, "answer values must be nonempty strings") { AmdReviewerCasesM3c.score(bad_answer_type, normalization) })

check.call("all cases stay within three fields and evidence remains synthetic and concise", cases.all? do |item|
  item.fetch("answer_fields").length <= 3 && item.fetch("evidence").all? { |fact| fact.fetch("text").length < 1400 }
end)

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
