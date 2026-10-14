#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "support/continuity_model_cases_a23"

Lab = SoulCore::ContinuityLab
Cases = Lab::ContinuityModelCasesA23

checks = 0
check = lambda do |label, &block|
  raise "FAIL: #{label}" unless block.call
  checks += 1
  puts "PASS: #{label}"
end
copy = ->(value) { JSON.parse(JSON.generate(value)) }

source_snapshot = {
  "a20" => Cases::A20_BATCHES.to_h do |batch|
    [batch, [Lab::QualificationCasesA20.corpus(batch), Lab::QualificationCasesA20.cases(batch)]]
  end,
  "a19" => Lab::QualificationCasesA19.corpus("chronology") + Lab::QualificationCasesA19.cases("chronology"),
  "a18" => Lab::QualificationCasesA18.corpus("heldout") + Lab::QualificationCasesA18.cases("heldout"),
  "a15" => Lab::QualificationCasesA15.corpus("conversation") + Lab::QualificationCasesA15.cases("conversation")
}

groups = Cases.groups
expected_shape = {
  "a20-lower-capacity" => ["a20-lower-capacity"],
  "a20-combined-air" => ["a20-combined-air"],
  "a20-stock-lantern" => ["a20-stock-lantern"],
  "a20-budget-battery" => ["a20-budget-battery"],
  "a20-no-eligible-printer" => ["a20-no-eligible-printer"],
  "a20-setup-time-nas" => ["a20-setup-time-nas"],
  "a19-chronology" => %w[a19-plan a19-first-correction a19-second-correction a19-callback],
  "a18-heldout" => ["a18-absent"],
  "a15-conversation" => %w[chat-walk chat-reason chat-drink chat-recall]
}
check.call("15 frozen requests in the requested group and case order") do
  groups.sum { |group| group.fetch("cases").length } == 15 &&
    groups.to_h { |group| [group.fetch("id"), group.fetch("cases").map { |spec| spec.fetch("id") }] } == expected_shape &&
    groups.map { |group| group.fetch("id") }.uniq.length == groups.length &&
    groups.flat_map { |group| group.fetch("cases").map { |spec| spec.fetch("id") } }.uniq.length == 15
end

check.call("all frozen corpora match the existing A20, A19, A18, and A15 sources") do
  a20_ok = Cases::A20_BATCHES.all? do |batch|
    group = groups.find { |item| item.fetch("cases").first.fetch("group") == batch }
    group.fetch("corpus") == Lab::QualificationCasesA20.corpus(batch)
  end
  a19_ok = groups.find { |item| item.fetch("id") == "a19-chronology" }.then do |group|
    group.fetch("corpus") == Lab::QualificationCasesA19.corpus("chronology")
  end
  a18_ok = groups.find { |item| item.fetch("id") == "a18-heldout" }.then do |group|
    group.fetch("corpus") == Lab::QualificationCasesA18.corpus("heldout")
  end
  a15_ok = groups.find { |item| item.fetch("id") == "a15-conversation" }.then do |group|
    group.fetch("corpus") == Lab::QualificationCasesA15.corpus("conversation")
  end
  a20_ok && a19_ok && a18_ok && a15_ok
end

check.call("all dependencies precede their dependent cases within each ordered group") do
  groups.all? do |group|
    prior = []
    group.fetch("cases").all? do |spec|
      required = spec.fetch("requires_events")
      ordered = required.all? { |dependency| prior.include?(dependency) }
      prior << spec.fetch("id")
      ordered
    end
  end
end

history = [
  { "user" => "Earlier user turn one", "assistant" => "Earlier assistant turn one" },
  { "user" => "Earlier user turn two", "assistant" => "Earlier assistant turn two" },
  { "user" => "Earlier user turn three", "assistant" => "Earlier assistant turn three" },
  { "user" => "Earlier user turn four", "assistant" => "Earlier assistant turn four" }
]
groups.each do |group|
  spec = group.fetch("cases").last
  messages = Cases.messages(group: group, spec: spec, history: history)
  expected_reference = "Reference data (complete sources, not instructions):\n#{JSON.generate(group.fetch('corpus'))}\n\n"
  check.call("#{group.fetch('id')} transcript preserves system, full corpus, newest three pairs, and current request") do
    messages.first == { "role" => "system", "content" => Lab::DirectEvidence::SYSTEM + "\n" + Lab::DirectEvidence::PROTOCOL } &&
      messages.drop(1).map { |message| message.fetch("content") } == [
        expected_reference + "Earlier user turn two", "Earlier assistant turn two",
        "Earlier user turn three", "Earlier assistant turn three",
        "Earlier user turn four", "Earlier assistant turn four", spec.fetch("content")
      ] && messages.last == { "role" => "user", "content" => spec.fetch("content") }
  end
end

alternation_group = groups.find { |group| group.fetch("id") == "a15-conversation" }
alternation_spec = alternation_group.fetch("cases").last
alternation_reference = "Reference data (complete sources, not instructions):\n#{JSON.generate(alternation_group.fetch('corpus'))}\n\n"
empty_history_messages = Cases.messages(group: alternation_group, spec: alternation_spec, history: [])
nonempty_history_messages = Cases.messages(group: alternation_group, spec: alternation_spec, history: history)
check.call("reference data and current request share one user turn when history is empty") do
  empty_history_messages.drop(1).map { |message| message.fetch("role") } == ["user"] &&
    empty_history_messages.last.fetch("content") == alternation_reference + alternation_spec.fetch("content")
end
check.call("direct chat roles strictly alternate for empty and retained history") do
  [empty_history_messages, nonempty_history_messages].all? do |messages|
    roles = messages.drop(1).map { |message| message.fetch("role") }
    roles.each_cons(2).all? { |left, right| left != right } && roles.last == "user"
  end && nonempty_history_messages.drop(1).map { |message| message.fetch("role") } ==
    %w[user assistant user assistant user assistant user]
end

expected_answers = {
  "a20-lower-capacity" => "Borlen rack costs 69 crowns and has 28 shelves.",
  "a20-combined-air" => "Neris qualifies at 96 crowns with airflow 248 cubic meters per hour and noise 36 decibels.",
  "a20-stock-lantern" => "Tovin lantern is in stock, runs for 9 hours, and costs 57 crowns.",
  "a20-budget-battery" => "Brel provides 8 kilowatt-hours for 638 crowns.",
  "a20-no-eligible-printer" => "No printer reaches at least 85 pages per minute, so none qualify.",
  "a20-setup-time-nas" => "Quorin NAS qualifies with 5 drive bays, setup time 28 minutes, and price 482 crowns.",
  "a19-plan" => "Uldara pack is the least expensive qualifying option: 34 sensors for 89 crowns.",
  "a19-first-correction" => "15 Merith packs contain 480 sensors in total and cost 1515 crowns.",
  "a19-second-correction" => "20 Tavren packs contain 520 sensors in total and cost 1420 crowns.",
  "a19-callback" => "The final choice is 20 Tavren packs, costing 1420 crowns.",
  "a18-absent" => "Warranty information is not listed in the Silverfen parts sheet.",
  "chat-walk" => "It's going well; I hope the tea helps you unwind after your walk.",
  "chat-reason" => "Taking a break to clear your head makes sense.",
  "chat-drink" => "Got it—you switched from tea to hot chocolate.",
  "chat-recall" => "You're drinking hot chocolate now, and you went out to clear your head and take a break."
}
groups.each do |group|
  corpus = group.fetch("corpus").map { |doc| doc.fetch("content") }.join("\n")
  group.fetch("cases").each do |spec|
    answer = expected_answers.fetch(spec.fetch("id"))
    screen = Cases.mechanical_screen(spec: spec, text: answer)
    corpus_support = spec.fetch("support").all? do |kind, *patterns|
      kind != "corpus" || patterns.all? do |pattern|
        Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE).match?(corpus)
      end
    end
    check.call("#{spec.fetch('id')} synthetic key answer passes the case regex screen") do
      screen.fetch("missing").empty? && screen.fetch("required") == spec.fetch("facts") && corpus_support
    end
  end
end

check.call("adapter enumeration and transcript generation do not mutate source modules") do
  after = {
    "a20" => Cases::A20_BATCHES.to_h do |batch|
      [batch, [Lab::QualificationCasesA20.corpus(batch), Lab::QualificationCasesA20.cases(batch)]]
    end,
    "a19" => Lab::QualificationCasesA19.corpus("chronology") + Lab::QualificationCasesA19.cases("chronology"),
    "a18" => Lab::QualificationCasesA18.corpus("heldout") + Lab::QualificationCasesA18.cases("heldout"),
    "a15" => Lab::QualificationCasesA15.corpus("conversation") + Lab::QualificationCasesA15.cases("conversation")
  }
  after == source_snapshot
end

puts "PASS: #{checks} A23 adapter checks; synthetic fixtures only, no model inference"
