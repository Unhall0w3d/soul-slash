#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/continuity_lab/runtime"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a20"

Lab = SoulCore::ContinuityLab
Cases = Lab::QualificationCasesA20

checks = 0
check = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }
abort "A20 requires the existing Qwen v9 qualification config" unless Lab::Config.respond_to?(:qwen_v9_qualification)
config = Lab::Config.qwen_v9_qualification

# Oracle rules intentionally live apart from the case definitions. Catalog
# values come only from parsing the pack's source documents below.
ORACLE_RULES = {
  "lower_capacity" => { "field" => "shelves", "lower" => 28, "objective" => "min_price",
    "request" => /at least (\d+) shelves/i },
  "upper_power" => { "field" => "watts", "upper" => 18, "objective" => "min_price",
    "request" => /no more than (\d+) watts/i },
  "combined_air" => { "field" => "airflow", "lower" => 240, "upper_field" => "noise", "upper" => 38,
    "objective" => "min_price", "request" => /at least (\d+) cubic meters per hour and producing no more than (\d+) decibels/i },
  "stock_lantern" => { "field" => "hours", "lower" => 9, "require_stock" => true, "objective" => "min_price",
    "request" => /in stock runs for at least (\d+) hours/i },
  "budget_battery" => { "field" => "capacity", "price_upper" => 650, "objective" => "max_field",
    "request" => /budget of at most (\d+) crowns/i },
  "height_range" => { "field" => "height", "lower" => 140, "upper" => 180, "objective" => "min_price",
    "request" => /from (\d+) through (\d+) centimeters high, inclusive/i },
  "no_eligible_printer" => { "field" => "speed", "lower" => 85, "objective" => "min_price",
    "request" => /reach at least (\d+) pages per minute/i },
  "setup_time_nas" => { "field" => "bays", "lower" => 4, "price_upper" => 500, "objective" => "min_field",
    "request" => /at least (\d+) drive bays and a price no higher than (\d+) crowns/i }
}.freeze

def parse_catalog(batch, text)
  rows = case batch
         when "lower_capacity"
           text.scan(/\b([A-Za-z]+) rack: (\d+) shelves, (\d+) crowns\b/).map do |name, shelves, price|
             { "name" => name, "shelves" => Integer(shelves), "price" => Integer(price) }
           end
         when "upper_power"
           text.scan(/\b([A-Za-z]+) router: (\d+) watts, (\d+) crowns\b/).map do |name, watts, price|
             { "name" => name, "watts" => Integer(watts), "price" => Integer(price) }
           end
         when "combined_air"
           text.scan(/\b([A-Za-z]+) purifier: (\d+) cubic meters per hour, (\d+) decibels, (\d+) crowns\b/).map do |name, airflow, noise, price|
             { "name" => name, "airflow" => Integer(airflow), "noise" => Integer(noise), "price" => Integer(price) }
           end
         when "stock_lantern"
           text.scan(/\b([A-Za-z]+) lantern: (\d+) hours, (in stock|out of stock), (\d+) crowns\b/).map do |name, hours, stock, price|
             { "name" => name, "hours" => Integer(hours), "stock" => stock == "in stock", "price" => Integer(price) }
           end
         when "budget_battery"
           text.scan(/\b([A-Za-z]+) battery: (\d+) kilowatt-hours, (\d+) crowns\b/).map do |name, capacity, price|
             { "name" => name, "capacity" => Integer(capacity), "price" => Integer(price) }
           end
         when "height_range"
           text.scan(/\b([A-Za-z]+) shelf: height (\d+) centimeters, (\d+) crowns\b/).map do |name, height, price|
             { "name" => name, "height" => Integer(height), "price" => Integer(price) }
           end
         when "no_eligible_printer"
           text.scan(/\b([A-Za-z]+) printer: (\d+) pages per minute, (\d+) crowns\b/).map do |name, speed, price|
             { "name" => name, "speed" => Integer(speed), "price" => Integer(price) }
           end
         when "setup_time_nas"
           text.scan(/\b([A-Za-z]+) NAS: (\d+) drive bays, setup (\d+) minutes, (\d+) crowns\b/).map do |name, bays, setup, price|
             { "name" => name, "bays" => Integer(bays), "setup" => Integer(setup), "price" => Integer(price) }
           end
         else
           raise "unknown A20 batch: #{batch}"
         end
  raise "catalog parse produced no options for #{batch}" if rows.empty?
  raise "catalog has duplicate options for #{batch}" unless rows.map { |row| row.fetch("name") }.uniq.length == rows.length
  rows
end

def parse_requested_constraints(rule, prompt)
  captures = rule.fetch("request").match(prompt)&.captures
  raise "request constraints not recognized: #{prompt}" unless captures
  values = captures.map { |value| Integer(value) }
  values
end

def eligible_options(batch, rule, constraints, options)
  case batch
  when "lower_capacity", "no_eligible_printer"
    minimum = constraints.fetch(0)
    options.select { |option| option.fetch(rule.fetch("field")) >= minimum }
  when "upper_power"
    maximum = constraints.fetch(0)
    options.select { |option| option.fetch(rule.fetch("field")) <= maximum }
  when "combined_air"
    minimum, maximum = constraints
    options.select { |option| option.fetch("airflow") >= minimum && option.fetch("noise") <= maximum }
  when "stock_lantern"
    minimum = constraints.fetch(0)
    options.select { |option| option.fetch("stock") && option.fetch("hours") >= minimum }
  when "budget_battery"
    budget = constraints.fetch(0)
    options.select { |option| option.fetch("price") <= budget }
  when "height_range"
    minimum, maximum = constraints
    options.select { |option| option.fetch("height").between?(minimum, maximum) }
  when "setup_time_nas"
    minimum_bays, maximum_price = constraints
    options.select { |option| option.fetch("bays") >= minimum_bays && option.fetch("price") <= maximum_price }
  end
end

def choose_option(batch, rule, options)
  case rule.fetch("objective")
  when "min_price" then options.min_by { |option| option.fetch("price") }
  when "max_field" then options.max_by { |option| option.fetch(rule.fetch("field")) }
  when "min_field" then options.min_by { |option| option.fetch("setup") }
  else raise "unknown objective for #{batch}"
  end
end

def expected_answer(batch, rule, constraints, winner)
  return "No printer reaches at least #{constraints.fetch(0)} pages per minute, so none qualify." if winner.nil?

  chosen_value = winner.fetch(rule.fetch("field"))
  objective_detail = rule.fetch("objective") == "min_field" ? " and setup time #{winner.fetch('setup')} minutes" : ""
  "#{winner.fetch('name')} qualifies at #{winner.fetch('price')} crowns with #{rule.fetch('field').tr('_', ' ')} #{chosen_value}#{objective_detail}."
end

def make_backend(spec, answer, run_config)
  backend = Lab::PipeBackend.new
  backend.define_singleton_method(:prepare) do |call_index:, input:|
    measurement = Lab::TokenContext.measurement(input, "synthetic-a20-prompt", Array.new(80, 20))
    Lab::TokenContext.preparation(initial: input, formatted: input, measurements: [measurement],
      input_budget: Lab::TokenContext.budget(run_config), call_index: call_index)
  end
  backend.define_singleton_method(:call) do |call_index:, input:, preparation_digest:|
    raise "unexpected extra call for #{spec.fetch('id')}" unless call_index.zero?
    Lab.encode("action" => "reply", "content" => answer)
  end
  backend
end

inherited = Cases::INHERITED_BATCHES
check.call("all seven A19 batches retain exact cases and corpora (28 inherited cases)") do
  inherited.all? do |batch|
    Cases.cases(batch) == Lab::QualificationCasesA19.cases(batch) &&
      Cases.corpus(batch) == Lab::QualificationCasesA19.corpus(batch)
  end && inherited.sum { |batch| Cases.cases(batch).length } == 28 && Cases::BATCHES == inherited + Cases::FRESH_BATCHES
end

check.call("eight fresh batches each define one standalone request and one unique bounded source") do
  Cases::FRESH_BATCHES.length == 8 && Cases::FRESH_BATCHES.uniq.length == 8 &&
    Cases::FRESH_BATCHES.all? do |batch|
      specs = Cases.cases(batch)
      docs = Cases.corpus(batch)
      specs.length == 1 && specs.first.fetch("requires_events").empty? &&
        specs.first.fetch("group") == batch && docs.length == 1 &&
        docs.first.fetch("id") == Cases::FRESH.fetch(batch).fetch("source_id") &&
        docs.map { |doc| doc.fetch("id") }.uniq.length == docs.length &&
        Lab::Retrieval.validate_corpus!(docs)
    end
end

Cases::FRESH_BATCHES.each do |batch|
  check.call("#{batch} independent parsed catalog/request oracle yields a unique answer or explicit no-eligible result") do
    spec = Cases.cases(batch).fetch(0)
    doc = Cases.corpus(batch).fetch(0)
    rule = ORACLE_RULES.fetch(batch)
    options = parse_catalog(batch, doc.fetch("content"))
    constraints = parse_requested_constraints(rule, spec.fetch("content"))
    expected_constraints = rule.select { |key, _| %w[lower upper price_upper].include?(key) }.values
    constraints == expected_constraints &&
      begin
        eligible = eligible_options(batch, rule, constraints, options)
        winner = choose_option(batch, rule, eligible)
        ties = if winner.nil? then [] else eligible.select do |option|
          option.fetch(rule.fetch("objective") == "min_field" ? "setup" : rule.fetch("objective") == "max_field" ? rule.fetch("field") : "price") ==
            winner.fetch(rule.fetch("objective") == "min_field" ? "setup" : rule.fetch("objective") == "max_field" ? rule.fetch("field") : "price")
        end end
        expected = expected_answer(batch, rule, constraints, winner)
        none_expected = batch == "no_eligible_printer"
        winner.nil? == none_expected && (winner.nil? || ties.length == 1) &&
          spec.fetch("facts").all? { |pattern| Cases.matches?(pattern, expected) } &&
          spec.fetch("support").first.first == "corpus" &&
          spec.fetch("support").flatten.drop(1).all? { |pattern| Cases.matches?(pattern, doc.fetch("content")) }
      end
  end
end

Cases::FRESH_BATCHES.each do |batch|
  spec = Cases.cases(batch).fetch(0)
  corpus = Cases.corpus(batch)
  rule = ORACLE_RULES.fetch(batch)
  options = parse_catalog(batch, corpus.fetch(0).fetch("content"))
  constraints = parse_requested_constraints(rule, spec.fetch("content"))
  eligible = eligible_options(batch, rule, constraints, options)
  winner = choose_option(batch, rule, eligible)
  answer = expected_answer(batch, rule, constraints, winner)
  Dir.mktmpdir("continuity-a20-#{batch}-") do |root|
    store = Lab::Store.create(path: File.join(root, "store"), config: config, corpus: corpus)
    before = store.snapshot
    direct = Lab::DirectEvidence.sources(before, spec.fetch("id"))
    check.call("#{batch} direct sources remain inside count and byte bounds") do
      before.fetch("events").empty? && direct.length == corpus.length &&
        direct.length <= Lab::DirectEvidence::MAX_DOCUMENTS &&
        Lab.encode(direct).bytesize <= Lab::DirectEvidence::MAX_BYTES &&
        direct.first.fetch("text") == corpus.first.fetch("content")
    end
    receipt = Lab::Runtime.new(store: store, backend: make_backend(spec, answer, config)).submit(
      event_id: spec.fetch("id"), content: spec.fetch("content"))
    after = store.snapshot
    event = after.fetch("events").fetch(spec.fetch("id"))
    score = Cases.evaluate(event: event, config: config, spec: spec, before: before, after: after)
    check.call("#{batch} derived correct synthetic answer passes the existing assessment") do
      receipt.fetch("reason") == "reply" && score.fetch("passed") && score.fetch("semantic_review_required")
    end

    wrong_option = (winner ? options.reject { |option| option == winner } : options).first
    wrong = if winner.nil?
              "#{wrong_option.fetch('name')} qualifies at #{wrong_option.fetch('price')} crowns."
            else
              "#{wrong_option.fetch('name')} is the requested choice at #{wrong_option.fetch('price')} crowns."
            end
    corrupted = copy.call(event)
    corrupted["reply"] = wrong
    corrupted.fetch("calls").last["response"] = Lab.encode("action" => "reply", "content" => wrong)
    wrong_score = Cases.evaluate(event: corrupted, config: config, spec: spec, before: before, after: after)
    check.call("#{batch} credible wrong or ineligible answer is rejected") do
      wrong_score.fetch("reasons").include?("missing_expected_fact_tokens") ||
        wrong_score.fetch("reasons").include?("missing_retrieved_support")
    end
    store.close
  end
end

puts "PASS: #{checks} A20 deterministic fixture checks; synthetic traces only, no live inference"
