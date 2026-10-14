#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "support/amd_reviewer_cases_m3"

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

puts "AMD reviewer M3 synthetic case and deterministic scoring verification:"
check.call("case catalog validates and contains ten unique cases", AmdReviewerCasesM3.validate! && AmdReviewerCasesM3.cases.length == 10 && AmdReviewerCasesM3.cases.map { |item| item.fetch("id") }.uniq.length == 10)

cases = AmdReviewerCasesM3.cases
verdict_counts = cases.group_by { |item| item.fetch("seeded_verdict") }.transform_values(&:length)
check.call("seeded control coverage is five supported, three contradicted, and two insufficient", verdict_counts == { "supported" => 5, "contradicted" => 3, "insufficient_evidence" => 2 } && cases.count { |item| AmdReviewerCasesM3.score(item.fetch("seeded_answer"), item).fetch("correct") } == 5)

first = cases.first
public_case = AmdReviewerCasesM3.public_case(first)
check.call("public projection excludes oracle and seeded audit fields", (public_case.keys & %w[oracle seeded_answer seeded_verdict]).empty? && public_case.fetch("id") == first.fetch("id"))

contradicted = cases.find { |item| item.fetch("seeded_verdict") == "contradicted" }
check.call("contradictory seeded answer is rejected by exact oracle scoring", !AmdReviewerCasesM3.score(contradicted.fetch("seeded_answer"), contradicted).fetch("correct"))

unknown = cases.find { |item| item.fetch("id") == "inspection-two-claims" }
check.call("unknown evidence answer is preserved and scores exactly", AmdReviewerCasesM3.score({ "status" => "complete", "reviewer" => "unknown" }, unknown) == { "correct" => true, "correct_fields" => 2, "total_fields" => 2 } && AmdReviewerCasesM3.score({ "status" => "complete", "reviewer" => "not recorded" }, unknown)["correct_fields"] == 1)

join = cases.find { |item| item.fetch("id") == "parcel-custodian-join" }
check.call("three-hop join retains distinct reordered evidence ids", join.fetch("evidence").length == 3 && join.fetch("evidence").map { |fact| fact.fetch("id") }.uniq.length == 3 && AmdReviewerCasesM3.score({ "person" => "Nia Vale", "room" => "212" }, join)["correct"])

selection = cases.find { |item| item.fetch("id") == "earliest-eligible-valid-record" }
check.call("six-row selection applies all three filters before choosing earliest", selection.fetch("evidence").length == 6 && AmdReviewerCasesM3.score({ "record_id" => "R-44", "date" => "2026-02-10" }, selection)["correct"] && !AmdReviewerCasesM3.score({ "record_id" => "R-17", "date" => "2026-01-11" }, selection)["correct"])

arithmetic = cases.find { |item| item.fetch("id") == "kiln-batch-total" }
check.call("word values allow only surrounding whitespace and case normalization", AmdReviewerCasesM3.score({ "total_mass" => " 17.5 KG " }, arithmetic)["correct"])
check.call("numeric and unit text remains exact after trimming", !AmdReviewerCasesM3.score({ "total_mass" => "17.50 kg" }, arithmetic)["correct"] && !AmdReviewerCasesM3.score({ "total_mass" => "17.5 g" }, arithmetic)["correct"])

two_fields = first.fetch("seeded_answer")
check.call("missing answer fields are rejected", raises.call(ArgumentError, "answer fields mismatch") { AmdReviewerCasesM3.score({ "retention_period" => two_fields.fetch("retention_period") }, first) })
check.call("extra answer fields are rejected", raises.call(ArgumentError, "answer fields mismatch") { AmdReviewerCasesM3.score(two_fields.merge("extra" => "value"), first) })
check.call("nonstring answer values are rejected", raises.call(ArgumentError, "answer values must be strings") { AmdReviewerCasesM3.score(two_fields.merge("revision" => 5), first) })

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
