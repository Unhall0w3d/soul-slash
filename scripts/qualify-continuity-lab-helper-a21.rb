#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/continuity_lab/verified_selection"
require_relative "../lib/soul_core/continuity_lab/qualification_cases_a20"

# Explicit fixture contracts, not an automatic interpretation of natural language.
# The retained model replies remain historical observations, never new inference.
module ContinuitySelectionReplayA21
  Lab = SoulCore::ContinuityLab
  Helper = Lab::VerifiedSelection
  Cases = Lab::QualificationCasesA20
  CONTRACTS = {
    "lower_capacity" => [[%w[shelves gte 28 count]], %w[price min], ["Borlen rack"]],
    "upper_power" => [[%w[power lte 18 W]], %w[price min], ["Corda router"]],
    "combined_air" => [[%w[airflow gte 240 m3/h], %w[noise lte 38 dB]], %w[price min], ["Neris purifier"]],
    "stock_lantern" => [[["stock", "eq", true, "boolean"], %w[runtime gte 9 h]], %w[price min], ["Tovin lantern"]],
    "budget_battery" => [[%w[price lte 650 crowns]], %w[capacity max], ["Brel battery"]],
    "height_range" => [[%w[height gte 140 cm], %w[height lte 180 cm]], %w[price min], ["Falen shelf"]],
    "no_eligible_printer" => [[%w[speed gte 85 pages/min]], %w[price min], []],
    "setup_time_nas" => [[%w[bays gte 4 count], %w[price lte 500 crowns]], %w[setup min], ["Quorin NAS"]]
  }.freeze

  def self.run(history_root)
    summary = Lab.parse(File.read(File.join(history_root, "suite-summary.json")))
    assessment = Lab.parse(File.read(File.join(history_root, "primary-assessment.json")))
    raise "Not the A20 assessment" unless assessment["schema"] == "soul.continuity_lab.primary_assessment.a20"
    assessment.fetch("source_receipts").each do |file, digest|
      raise "Unknown receipt" unless %w[suite-summary.json suite-baseline.json].include?(file)
      raise "Historical receipt drift" unless Digest::SHA256.file(File.join(history_root, file)).hexdigest == digest
    end
    results = CONTRACTS.map do |batch, (constraints, objective, expected)|
      case_id = "a20-#{batch.tr('_', '-')}"
      historical = %w[chat checked].to_h do |condition|
        entry = summary.fetch("batches").find { |b| b["condition"] == condition && b["batch"] == batch }
        raise "Missing historical case" unless entry && entry.fetch("results").length == 1
        result = entry.fetch("results").first
        raise "Wrong historical case" unless result["id"] == case_id
        [condition, result]
      end
      source = historical.fetch("chat").fetch("sources").first
      expected_document = Cases.corpus(batch).first
      unless source.fetch("id") == expected_document.fetch("id") && source.fetch("text") == expected_document.fetch("content") &&
             historical.values.all? { |result| result.fetch("sources").length == 1 && result["sources"].first["text"] == source["text"] }
        raise "Source corpus changed"
      end
      request = { "version" => "selection_request_v1", "source_ref" => Helper.reference(source),
                  "constraints" => constraints.map { |row| %w[field op value unit].zip(row).to_h },
                  "objective" => %w[field direction].zip(objective).to_h }
      value = Helper.evaluate(source: source, request: request)
      raise "Helper fixture failed: #{batch}" unless value["state"] == "complete" && value["winners"] == expected
      paired = assessment.fetch("cases").find { |c| c["id"] == case_id }
      raise "Missing historical assessment" unless paired
      %w[chat checked].each do |condition|
        raise "Historical reply changed" unless paired.fetch(condition).fetch("reply") == historical.fetch(condition).fetch("reply")
      end
      { "id" => case_id, "request" => request, "verified_result" => value,
        "historical_model_only" => paired.slice("chat", "checked"),
        "presentation_example" => Helper.present(source: source, request: request,
          explanation: historical.fetch("checked").fetch("reply")) }
    end
    { "schema" => "soul.continuity_lab.retrospective_helper_replay.a21",
      "assessment" => "deterministic_fixture_replay_not_a_fresh_model_comparison",
      "request_origin" => "explicit_primary_authored_contract_not_verified_natural_language_interpretation",
      "model_calls" => 0, "cases" => results,
      "helper_correct" => results.length, "scheduled" => CONTRACTS.length,
      "historical_root" => history_root,
      "historical_receipts" => %w[suite-summary.json suite-baseline.json primary-assessment.json].to_h do |file|
        [file, Digest::SHA256.file(File.join(history_root, file)).hexdigest]
      end }
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: ruby scripts/qualify-continuity-lab-helper-a21.rb A20_EVIDENCE_DIRECTORY" unless ARGV.length == 1
  puts SoulCore::ContinuityLab.encode(ContinuitySelectionReplayA21.run(File.expand_path(ARGV.first)))
end
