#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "timeout"
require_relative "../lib/soul_core/continuity_lab/verified_selection"

Lab = SoulCore::ContinuityLab
Selection = Lab::VerifiedSelection
RUBY = "/home/bhones/.rbenv/versions/4.0.7/bin/ruby"
raise "pinned Ruby unavailable" unless File.executable?(RUBY)
raise "wrong pinned Ruby" unless RbConfig.ruby == RUBY

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end

lineage = "a" * 32
source_id = "a21-catalog"
catalog_text = <<~TEXT
  Kitchen catalog.
  Option Cedar: 4 shelves, 120 crowns, 2 hours, in stock, setup 10 minutes.
  Option Birch: 6 shelves, 150 crowns, 120 minutes, out of stock, setup 0.25 hours.
  Option Maple: 5 shelves, 150 crowns, 2 hours, in stock, setup 15 minutes.
TEXT
source = lambda do |text = catalog_text, id = source_id, revision: 1, span: nil, digest: nil, lineage_id: lineage|
  { "lineage_id" => lineage_id, "collection" => "corpus", "id" => id, "revision" => revision,
    "content_digest" => digest || Digest::SHA256.hexdigest(text),
    "provenance" => "operator_selected_source_not_authority", "span" => span || [0, text.length], "text" => text }
end
source_ref = ->(doc = source.call) { %w[lineage_id id revision content_digest].to_h { |field| [field, doc.fetch(field)] } }
request = lambda do |doc = source.call, constraints = [], objective = { "field" => "price", "direction" => "min" }, totals = nil|
  value = { "version" => "selection_request_v1", "source_ref" => source_ref.call(doc),
    "constraints" => constraints, "objective" => objective }
  value["totals"] = totals unless totals.nil?
  value
end
constraint = ->(field, op, value, unit) { { "field" => field, "op" => op, "value" => value, "unit" => unit } }
copy = ->(value) { Marshal.load(Marshal.dump(value)) }
complete = ->(result) { result.is_a?(Hash) && result["state"] == "complete" }
refusal = ->(result) { result.is_a?(Hash) && result["state"] == "awaiting_input" && result["reason"].is_a?(String) && !result.key?("winners") }

base_request = request.call
base_result = Selection.evaluate(source: source.call, request: base_request)
check.call("lower, upper, equality and combined constraints evaluate every catalog row") do
  cases = [
    [[constraint.call("shelves", "gte", "5", "count")], ["Option Birch", "Option Maple"]],
    [[constraint.call("price", "lte", "120", "crowns")], ["Option Cedar"]],
    [[constraint.call("shelves", "eq", "4", "count")], ["Option Cedar"]],
    [[constraint.call("shelves", "gte", "5", "count"), constraint.call("price", "lte", "150", "crowns")], ["Option Birch", "Option Maple"]]
  ]
  cases.all? do |constraints, expected|
    result = Selection.evaluate(source: source.call, request: request.call(source.call, constraints))
    complete.call(result) && result.fetch("options").map { |row| row.fetch("option") }.sort == ["Option Birch", "Option Cedar", "Option Maple"] &&
      result.fetch("options").select { |row| row.fetch("eligible") }.map { |row| row.fetch("option") }.sort == expected
  end
end

check.call("min, max, ties and explicit no-eligible outcomes are exact") do
  min = base_result
  max = Selection.evaluate(source: source.call, request: request.call(source.call, [], { "field" => "shelves", "direction" => "max" }))
  tie_request = request.call(source.call, [constraint.call("stock", "eq", true, "boolean")],
    { "field" => "runtime", "direction" => "min" })
  tie = Selection.evaluate(source: source.call, request: tie_request)
  none = Selection.evaluate(source: source.call, request: request.call(source.call, [constraint.call("shelves", "gte", "99", "count")]))
  complete.call(min) && min["reason"] == "selected" && min["winners"] == ["Option Cedar"] &&
    complete.call(max) && max["reason"] == "selected" && max["winners"] == ["Option Birch"] &&
    complete.call(tie) && tie["reason"] == "tie" && tie["winners"].sort == ["Option Cedar", "Option Maple"] &&
    complete.call(none) && none["reason"] == "none_eligible" && none["winners"].empty?
end

check.call("exact decimal comparison and canonical fractional conversion avoid floats") do
  decimal_text = "Power catalog.\nOption Near: 0.100001 watts, 1 crowns.\nOption Exact: 0.1 watts, 2 crowns.\n"
  decimal_source = source.call(decimal_text, "decimal")
  decimal_request = request.call(decimal_source, [constraint.call("power", "lte", "0.1", "W")])
  result = Selection.evaluate(source: decimal_source, request: decimal_request)
  conversion_text = "Runtime catalog.\nOption Ten: 10 minutes, 1 crowns.\nOption Twenty: 20 minutes, 2 crowns.\n"
  conversion_source = source.call(conversion_text, "conversion")
  conversion_request = request.call(conversion_source, [], { "field" => "runtime", "direction" => "min" })
  converted = Selection.evaluate(source: conversion_source, request: conversion_request)
  energy_height_text = "Conversion catalog.\nOption Mixed: height 1.25 meters, 1500 watt-hours, 1 crowns.\n"
  energy_height_source = source.call(energy_height_text, "energy-height")
  energy_height = Selection.evaluate(source: energy_height_source,
    request: request.call(energy_height_source, [], { "field" => "capacity", "direction" => "max" }))
  complete.call(result) && result["winners"] == ["Option Exact"] &&
    result.dig("options", 0, "values", "power", "value") == "0.100001" &&
    complete.call(converted) && converted.dig("options", 0, "values", "runtime", "value") == "1/6" &&
    converted.dig("objective", "value") == "1/6" &&
    complete.call(energy_height) && energy_height.dig("options", 0, "values", "height", "value") == "125" &&
    energy_height.dig("options", 0, "values", "capacity", "value") == "1.5"
end

check.call("unit aliases normalize and supported dimensions stay attached to source values") do
  text = "Equipment catalog.\nOption A: height 100 centimeters, 60 pages per minute, 2 drive bays, 1 kilowatt-hours, 1 crowns.\n"
  doc = source.call(text, "units")
  result = Selection.evaluate(source: doc, request: request.call(doc, [], { "field" => "height", "direction" => "min" }))
  complete.call(result) && result.dig("options", 0, "values", "height", "value") == "100" &&
    result.dig("options", 0, "values", "height", "unit") == "cm" &&
    result.dig("options", 0, "values", "speed", "unit") == "pages/min" &&
    result.dig("options", 0, "values", "bays", "unit") == "count" &&
    result.dig("options", 0, "values", "capacity", "unit") == "kWh"
end

check.call("scalar totals multiply the requested quantity per eligible option") do
  totals = { "quantity" => 3, "fields" => %w[price runtime] }
  result = Selection.evaluate(source: source.call, request: request.call(source.call,
    [constraint.call("shelves", "eq", "4", "count")], base_request.fetch("objective"), totals))
  complete.call(result) && result.fetch("totals").length == 1 &&
    result.fetch("totals").first.fetch("option") == "Option Cedar" &&
    result.fetch("totals").first.fetch("values").fetch("price").fetch("value") == "360" &&
    result.fetch("totals").first.fetch("values").fetch("runtime").fetch("value") == "6"
end

check.call("source value evidence retains exact quoted field spans and full source coverage") do
  result = Selection.evaluate(source: source.call, request: base_request)
  row = result.fetch("options").find { |option| option.fetch("option") == "Option Cedar" }
  expected_quotes = { "shelves" => "4 shelves", "price" => "120 crowns", "runtime" => "2 hours",
    "stock" => "in stock", "setup" => "setup 10 minutes" }
  complete.call(result) && result.dig("source_ref", "content_digest") == Digest::SHA256.hexdigest(catalog_text) &&
    source.call.fetch("span") == [0, catalog_text.length] && expected_quotes.all? do |field, quote|
      evidence = row.dig("values", field, "evidence")
      span = evidence.fetch("span")
      evidence.fetch("quote") == quote && span == [catalog_text.index(quote), catalog_text.index(quote) + quote.length] &&
        catalog_text[span[0]...span[1]] == quote
    end
end

check.call("metadata and tampering refuse digest, reference, span, encoding, size and selected-source faults") do
  bad_sources = [
    source.call(catalog_text, source_id, digest: "0" * 64),
    source.call(catalog_text, source_id, lineage_id: "b" * 32),
    source.call(catalog_text, source_id, revision: 2),
    source.call(catalog_text, source_id, span: [0, catalog_text.length - 1]),
    source.call(catalog_text, source_id).merge("unexpected" => true),
    source.call(catalog_text, source_id).merge("revision" => "1"),
    source.call(catalog_text, source_id).merge("collection" => "notes"),
    source.call(catalog_text, source_id).merge("provenance" => "verified"),
    source.call(catalog_text, source_id).merge("lineage_id" => true),
    source.call(catalog_text, source_id).merge("span" => [false, catalog_text.length]),
    source.call("x" * 8193, "large"),
    source.call("\xFF".b.force_encoding(Encoding::UTF_8), "invalid")
  ]
  outcomes = bad_sources.map { |doc| Selection.evaluate(source: doc, request: base_request) }
  mismatched_ref = request.call.merge("source_ref" => source_ref.call(source.call).merge("revision" => 2))
  changed_lineage = source.call(catalog_text, source_id, lineage_id: "b" * 32)
  changed_revision = source.call(catalog_text, source_id, revision: 2)
  outcomes.all?(&refusal) && refusal.call(Selection.evaluate(source: source.call, request: mismatched_ref)) &&
    complete.call(Selection.evaluate(source: changed_lineage, request: request.call(changed_lineage))) &&
    complete.call(Selection.evaluate(source: changed_revision, request: request.call(changed_revision)))
end

check.call("integer source spans reject numerically equal floating-point offsets") do
  doc = source.call.merge("span" => [0.0, catalog_text.length.to_f])
  result = Selection.evaluate(source: doc, request: base_request)
  refusal.call(result) && result["reason"] == "invalid_source_binding"
end

check.call("request references reject numerically equal floating-point revisions") do
  req = copy.call(base_request)
  req.fetch("source_ref")["revision"] = 1.0
  result = Selection.evaluate(source: source.call, request: req)
  refusal.call(result) && result["reason"] == "invalid_request_binding"
end

check.call("invalid UTF-8 lineage returns a refusal instead of raising in the parser") do
  doc = source.call.merge("lineage_id" => "\xFF".b.force_encoding(Encoding::UTF_8))
  result = Selection.evaluate(source: doc, request: base_request)
  refusal.call(result) && result["reason"] == "invalid_source_binding"
end

check.call("catalog syntax, bounds, duplicate labels or fields, missing rows and inconsistent fields refuse") do
  invalid_texts = [
    "Kitchen catalog.\nOption Cedar: 4 shelves, 120 crowns.\nUnparsed trailing words.\n",
    "Kitchen catalog.\nOption Cedar: 4 shelves, 120 crowns.\nOption CEDAR: 5 shelves, 130 crowns.\n",
    "Kitchen catalog.\nOption Cedar: 4 shelves, 4 shelves, 120 crowns.\n",
    "Kitchen catalog.\nOption Cedar: 4 shelves, 120 crowns.\nOption Birch: 5 shelves, 2 hours.\n",
    "Kitchen catalog.\n",
    "Kitchen catalog.\nOption Bad: -1 shelves, 2 crowns.\n",
    "Kitchen catalog.\nOption Bad: 1234567890 shelves, 2 crowns.\n",
    "Kitchen catalog.\nOption Bad: 1.0000001 shelves, 2 crowns.\n",
    "Kitchen catalog.\nOption Bad: 1.5 shelves, 2 crowns.\n",
    "Kitchen catalog.\nOption Bad: 1 shelves, 2 crowns.\nOption Other: 1 shelves, 2 credits.\n",
    "Kitchen catalog.\nOption Bad: 1 dollars, 2 euros.\n"
  ]
  invalid_texts.all? do |text|
    doc = source.call(text, "bad-catalog")
    refusal.call(Selection.evaluate(source: doc, request: request.call(doc)))
  end &&
    refusal.call(Selection.evaluate(source: source.call("Kitchen catalog.\n" + 33.times.map { |i| "Option Item#{i}: 1 shelves, 2 crowns.\n" }.join, "too-many"),
      request: request.call(source.call("Kitchen catalog.\n" + 33.times.map { |i| "Option Item#{i}: 1 shelves, 2 crowns.\n" }.join, "too-many")))) &&
    refusal.call(Selection.evaluate(source: source.call("Kitchen catalog.\nOption TooWide: " + Array.new(13, "1 shelves").join(", ") + ".\n", "too-wide"),
      request: request.call(source.call("Kitchen catalog.\nOption TooWide: " + Array.new(13, "1 shelves").join(", ") + ".\n", "too-wide"))))
end

check.call("request schema, limits, contradictory constraints and exact numeric input are validated") do
  doc = source.call
  bad_requests = [
    request.call.merge("surprise" => true),
    request.call.merge("version" => "other"),
    request.call.merge("source_ref" => source_ref.call(doc).merge("unknown" => 1)),
    request.call(doc, [constraint.call("shelves", "gte", 4, "count")]),
    request.call(doc, [constraint.call("shelves", "gte", "four", "count")]),
    request.call(doc, [constraint.call("shelves", "gte", "4e0", "count")]),
    request.call(doc, [constraint.call("shelves", "gte", "4", "cm")]),
    request.call(doc, [constraint.call("price", "gte", "140", "crowns"), constraint.call("price", "lte", "100", "crowns")]),
    request.call(doc, [constraint.call("shelves", "gte", "5", "count"), constraint.call("shelves", "eq", "4", "count")]),
    request.call(doc, [constraint.call("shelves", "gte", "4", "count"), constraint.call("shelves", "gte", "5", "count")]),
    request.call(doc, [constraint.call("power", "gte", "1", "W")]),
    request.call(doc, [constraint.call("stock", "gte", true, "boolean")]),
    request.call(doc, [constraint.call("stock", "eq", "true", "boolean")]),
    request.call(doc, [constraint.call("stock", "eq", 1, "boolean")]),
    request.call(doc, [constraint.call("shelves", "eq", "4", "count").merge("extra" => nil)]),
    request.call(doc, Array.new(9) { constraint.call("shelves", "gte", "1", "count") }),
    request.call(doc, [], { "field" => "not_a_field", "direction" => "min" }),
    request.call(doc, [], base_request.fetch("objective").merge("extra" => true)),
    request.call(doc, [], { "field" => "stock", "direction" => "min" }),
    request.call(doc, [], { "field" => "price", "direction" => "sideways" }),
    request.call(doc, [], base_request.fetch("objective"), { "quantity" => 1_000_001, "fields" => ["price"] }),
    request.call(doc, [], base_request.fetch("objective"), { "quantity" => 2, "fields" => %w[price price] }),
    request.call(doc, [], base_request.fetch("objective"), { "quantity" => 2, "fields" => ["stock"] })
  ]
  bad_requests.all? { |value| refusal.call(Selection.evaluate(source: doc, request: value)) } &&
    complete.call(Selection.evaluate(source: doc, request: request.call(doc, [constraint.call("shelves", "gte", "4.0", "count")])))
end

check.call("proposals require a complete exact option-field table and reject altered or cross-associated values") do
  extracted = base_result.fetch("options")
  proposal = extracted.map do |row|
    { "option" => row.fetch("option"), "values" => row.fetch("values").transform_values { |entry| entry.slice("value", "unit") } }
  end
  variants = [
    proposal.drop(1),
    proposal + [{ "option" => "Invented", "values" => proposal.first.fetch("values") }],
    proposal.map { |row| row.fetch("option") == "Option Cedar" ? row.merge("values" => row.fetch("values").reject { |field, _| field == "price" }) : row },
    proposal.map { |row| row.fetch("option") == "Option Cedar" ? row.merge("values" => row.fetch("values").merge("price" => { "value" => "999", "unit" => "crowns" })) : row },
    proposal.map { |row| row.fetch("option") == "Option Cedar" ? row.merge("option" => "Option Birch") : row },
    proposal.map { |row| row.fetch("option") == "Option Cedar" ? row.merge("values" => row.fetch("values").merge("invented" => { "value" => "1", "unit" => "count" })) : row },
    proposal.map { |row| row.fetch("option") == "Option Cedar" ? row.merge("unexpected" => true) : row }
  ]
  swapped = proposal.map do |row|
    other_label = { "Option Cedar" => "Option Birch", "Option Birch" => "Option Cedar" }.fetch(row.fetch("option"), row.fetch("option"))
    other = proposal.find { |candidate| candidate.fetch("option") == other_label }
    row.merge("values" => other.fetch("values"))
  end
  good = Selection.evaluate(source: source.call, request: base_request, proposal: proposal)
  reordered = Selection.evaluate(source: source.call, request: base_request, proposal: proposal.reverse)
  complete.call(good) && complete.call(reordered) &&
    variants.all? { |candidate| refusal.call(Selection.evaluate(source: source.call, request: base_request, proposal: candidate)) } &&
    refusal.call(Selection.evaluate(source: source.call, request: base_request, proposal: swapped))
end

check.call("explanation stays isolated from deterministic result and caller inputs are not mutated") do
  doc = source.call
  req = request.call
  proposal = nil
  before = [copy.call(doc), copy.call(req), copy.call(proposal)]
  presented = Selection.present(source: doc, request: req, proposal: proposal, explanation: "Cedar wins because the moon says so.")
  explanation = presented.fetch("generated_explanation")
  presented.fetch("verified_result") == Selection.evaluate(source: doc, request: req) &&
    explanation == { "status" => "unverified_model_text", "text" => "Cedar wins because the moon says so." } &&
    [doc, req, proposal] == before &&
    Selection.present(source: doc, request: req).fetch("generated_explanation").nil? &&
    Selection.present(source: doc, request: req, explanation: "x" * 4097).dig("verified_result", "reason") == "invalid_explanation" &&
    Selection.present(source: doc, request: req, explanation: "\xFF".b.force_encoding(Encoding::UTF_8)).dig("verified_result", "reason") == "invalid_explanation"
end

check.call("CLI prints complete and none-eligible results with success exit codes, and invalid requests exit 2") do
  input = JSON.generate("source" => source.call, "request" => base_request)
  ok_out, ok_err, ok_status = Open3.capture3(RUBY, "scripts/continuity-lab-select.rb", stdin_data: input)
  none_request = request.call(source.call, [constraint.call("shelves", "gte", "99", "count")])
  none_out, none_err, none_status = Open3.capture3(RUBY, "scripts/continuity-lab-select.rb", stdin_data: JSON.generate("source" => source.call, "request" => none_request))
  invalid_request = request.call(source.call, [constraint.call("shelves", "gte", "99", "count").merge("unit" => "cm")])
  bad_out, bad_err, bad_status = Open3.capture3(RUBY, "scripts/continuity-lab-select.rb", stdin_data: JSON.generate("source" => source.call, "request" => invalid_request))
  parsed_ok = JSON.parse(ok_out)
  parsed_none = JSON.parse(none_out)
  parsed_bad = JSON.parse(bad_out)
  ok_status.exitstatus == 0 && ok_err.empty? && parsed_ok.dig("verified_result", "state") == "complete" &&
    none_status.exitstatus == 0 && none_err.empty? && parsed_none.dig("verified_result", "reason") == "none_eligible" &&
    bad_status.exitstatus == 2 && bad_err.empty? && parsed_bad.dig("verified_result", "state") == "awaiting_input"
end

check.call("CLI rejects duplicate keys, unknown keys, oversized, invalid UTF-8 and excessive nesting") do
  inputs = [
    '{"source":{},"source":{},"request":{}}',
    JSON.generate("source" => source.call, "request" => base_request, "extra" => true),
    " " * (32 * 1024 + 1),
    "\xFF".b,
    "[" * 140 + "0" + "]" * 140
  ]
  inputs.all? do |input|
    _out, _err, status = Open3.capture3(RUBY, "scripts/continuity-lab-select.rb", stdin_data: input)
    status.exitstatus == 2
  end
end

check.call("CLI returns from stalled stdin within its five-second bound") do
  reader, writer = IO.pipe
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn(RUBY, "scripts/continuity-lab-select.rb", in: reader, out: File::NULL, err: File::NULL)
  reader.close
  status = Timeout.timeout(7) { Process.wait2(pid).last }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  writer.close
  status.exitstatus == 2 && elapsed < 7
rescue Timeout::Error
  Process.kill("TERM", pid) rescue nil
  Process.wait(pid) rescue nil
  false
end

puts "PASS: #{checks} A21 verified-selection contract groups; synthetic fixtures only"
