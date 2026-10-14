#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "support/amd_reviewer_cases_m3b"

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  puts "- #{label}: #{condition ? 'ok' : 'FAIL'}"
  failures << label unless condition
end

puts "AMD reviewer M3b synthetic case verification:"
cases = AmdReviewerCasesM3b.cases
check.call("catalog validates exactly eight unique cases", AmdReviewerCasesM3b.validate! && cases.length == 8 && cases.map { |item| item.fetch("id") }.uniq.length == 8)

counts = cases.group_by { |item| item.fetch("seeded_verdict") }.transform_values(&:length)
check.call("seeded verdict coverage is exactly two per category", counts == { "supported" => 2, "contradicted" => 2, "insufficient_evidence" => 2, "mixed" => 2 })
check.call("all evidence items remain below the per-item character limit", cases.all? { |item| item.fetch("evidence").all? { |fact| fact.fetch("text").length < 1400 } })

expected = {
  "effective-permit-revision" => [{ "permit_id" => "P-18", "capacity" => "62 units" }, { "permit_id" => "P-18", "capacity" => "62 units" }, "supported"],
  "crate-route-join" => [{ "handler" => "Miro Pell", "destination" => "D-8", "priority" => "unknown" }, { "handler" => "Miro Pell", "destination" => "D-8", "priority" => "unknown" }, "supported"],
  "superseded-inspection-window" => [{ "interval" => "30 days", "revision" => "7" }, { "interval" => "45 days", "revision" => "6" }, "contradicted"],
  "misjoined-sample-owner" => [{ "owner" => "Ada Noll" }, { "owner" => "Bram Venn" }, "contradicted"],
  "unrecorded-valve-duration" => [{ "duration" => "unknown" }, { "duration" => "18 minutes" }, "insufficient_evidence"],
  "unlisted-shelf-location" => [{ "shelf_code" => "unknown" }, { "shelf_code" => "S-4" }, "insufficient_evidence"],
  "audited-transfer-claims" => [{ "limit" => "16 units", "close_date" => "unknown" }, { "limit" => "20 units", "close_date" => "2026-05-10" }, "mixed"],
  "revision-and-missing-approver" => [{ "form_code" => "F-2 revision 3", "approver" => "unknown" }, { "form_code" => "F-2 revision 1", "approver" => "Jessa Ward" }, "mixed"]
}
observed = cases.to_h { |item| [item.fetch("id"), [item.fetch("oracle"), item.fetch("seeded_answer"), item.fetch("seeded_verdict")]] }
check.call("case identifiers, expected values, and seeded verdicts match the reviewed fixture", observed == expected)

public_cases = cases.map { |item| AmdReviewerCasesM3b.public_case(item) }
check.call("public projection omits oracle and seeded audit labels", public_cases.all? { |item| (item.keys & %w[oracle seeded_answer seeded_verdict]).empty? })
check.call("public projection retains only prompt-facing case fields", public_cases.all? { |item| item.keys.sort == %w[answer_fields evidence id question].sort })

copy_a = AmdReviewerCasesM3b.cases
copy_b = AmdReviewerCasesM3b.cases
copy_a.first.fetch("evidence").first["text"] = "changed in copy A"
copy_a.first.fetch("oracle")["permit_id"] = "changed in copy A"
check.call("case calls return independent nested copies", copy_b.first.fetch("evidence").first.fetch("text") != "changed in copy A" && copy_b.first.fetch("oracle").fetch("permit_id") == "P-18" && AmdReviewerCasesM3b.cases.first.fetch("oracle").fetch("permit_id") == "P-18")

mixed = cases.select { |item| item.fetch("seeded_verdict") == "mixed" }
check.call("mixed cases keep an evidence-contradicted claim separate from an unsupported certainty", mixed.all? do |item|
  fields = item.fetch("answer_fields")
  contradicted_field = fields.find { |field| item.fetch("oracle").fetch(field) != "unknown" && item.fetch("oracle").fetch(field) != item.fetch("seeded_answer").fetch(field) }
  unsupported_field = fields.find { |field| item.fetch("oracle").fetch(field) == "unknown" && item.fetch("seeded_answer").fetch(field) != "unknown" }
  contradicted_field && unsupported_field && contradicted_field != unsupported_field
end)

unknown = cases.find { |item| item.fetch("id") == "crate-route-join" }
check.call("recorded explicit unknown remains part of a fully supported answer", unknown.fetch("oracle").fetch("priority") == "unknown" && unknown.fetch("seeded_answer").fetch("priority") == "unknown")
check.call("case questions and evidence use synthetic record-specific reasoning", cases.all? { |item| item.fetch("question").length > 20 && item.fetch("evidence").all? { |fact| fact.fetch("id").match?(/\A[a-z0-9-]+\z/) } })

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
