# frozen_string_literal: true

require_relative "qualification_cases_a12"

module SoulCore
  module ContinuityLab
    module QualificationCasesA13
      VERSION = "explicit_marker_identifier_receipts_a13_v1"
      CORPUS = QualificationCasesA12::CORPUS

      def self.cases
        clarified = QualificationCasesA12.cases.to_h { |spec| [spec.fetch("pair"), spec.fetch("content")] }
        QualificationCasesA8.cases.map { |spec| spec.merge("content" => clarified.fetch(spec.fetch("pair"))) }
      end

      def self.expected_state(...) = QualificationCasesA8.expected_state(...)
      def self.config(spec) = Config.qwen_v6_qualification(rollover: spec.fetch("condition") == "rollover")

      def self.calibration_evidence(spec, selected)
        sizing = QualificationCasesA8.calibration_evidence(spec, selected)
        coverage = selected.all? do |row|
          row.fetch("retained_receipts") + row.fetch("included_groups") == (0...row.fetch("call_index")).to_a
        end
        sizing.merge("valid" => sizing.fetch("valid") && coverage, "receipt_coverage" => coverage)
      end

      def self.condition_evidence(event, spec)
        evidence = QualificationCasesA8.condition_evidence(event, spec)
        rows = event.fetch("calls").first(5).each_with_index.map do |call, index|
          manifest = call.dig("context", "manifest") || {}
          { "call_index" => index, "context_policy" => manifest["context_policy"],
            "receipt_indices" => manifest.fetch("retained_receipts", []).map { |r| r.fetch("call_index") },
            "full_indices" => manifest["included_groups"] }
        end
        coverage = rows.length == 5 && rows.all? do |row|
          row["context_policy"] == ReceiptContext::POLICY && row["full_indices"].is_a?(Array) &&
            row["receipt_indices"] + row["full_indices"] == (0...row["call_index"]).to_a
        end
        evidence.merge("receipt_coverage" => coverage, "receipt_calls" => rows,
          "intended_condition_observed" => evidence.fetch("intended_condition_observed") && coverage)
      end
    end
  end
end
