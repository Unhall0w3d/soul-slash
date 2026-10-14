# frozen_string_literal: true

require_relative "qualification_cases_a8"

module SoulCore
  module ContinuityLab
    module QualificationCasesA12
      VERSION = "explicit_marker_identifier_visible_a12_v1"
      CORPUS = QualificationCasesA8::CORPUS

      def self.cases
        QualificationCasesA8.cases.select { |spec| spec["condition"] == "visible" }.map do |spec|
          spec.merge("content" => spec.fetch("content") +
            " Here marker means only the identifier made of uppercase letters, a hyphen and digits. " +
            "Reply with that identifier alone, without surrounding words, labels or sentence punctuation.")
        end
      end

      def self.expected_state(...) = QualificationCasesA8.expected_state(...)
      def self.calibration_evidence(...) = QualificationCasesA8.calibration_evidence(...)
      def self.condition_evidence(...) = QualificationCasesA8.condition_evidence(...)
    end
  end
end
