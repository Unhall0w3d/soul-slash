# frozen_string_literal: true

require_relative "qualification_cases_a15"

module SoulCore
  module ContinuityLab
    # A16 adds one held-out transfer batch while preserving the A15 baseline
    # cases and mechanical evaluator verbatim.
    module QualificationCasesA16
      VERSION = "foreground_usability_a16_v1"
      TRANSFER = "Northstar field kit catalog. Lumen pack contains 6 markers and costs 18 credits. Orbit pack contains 10 markers and costs 25 credits. Nova pack contains 8 markers and costs 24 credits. All packs are in stock. Warranty terms are not recorded."

      def self.corpus(batch)
        return [{ "id" => "field-kit-catalog", "content" => TRANSFER }] if batch == "transfer"

        QualificationCasesA15.corpus(batch)
      end

      def self.cases(batch)
        return QualificationCasesA15.cases(batch) unless batch == "transfer"

        [
          row("t-plan", "I'm putting together a Northstar field kit. Which pack is the least expensive way to get at least eight markers, and what would it cost?",
            facts: ['\\bNova\\b', '\\b24\\b'], support: [["corpus", "\\bNova\\b", "\\b8\\b", "\\b24\\b"]]),
          row("t-change", "Actually, let's switch to two Orbit packs. What would that give me altogether, and what would I spend?",
            facts: ['\\bOrbit\\b', '\\b(?:20|twenty)\\b', '\\b50\\b'], support: [["corpus", "\\bOrbit\\b", "\\b10\\b", "\\b25\\b"]]),
          row("t-callback", "Can you remind me which pack I switched to, how many, and the combined cost?",
            facts: ['\\bOrbit\\b', '\\b(?:2|two)\\b', '\\b50\\b'], support: [["prior", "\\bOrbit\\b", "\\b(?:2|two)\\b", "\\b50\\b"]], requires: ["t-change"]),
          row("t-absent", "What warranty period does the Northstar catalog promise?",
            facts: ["not (?:recorded|provided|specified|confirmed|available)|no .*?(?:warranty|information|terms)|unknown|unspecified|haven't|hasn't|don't (?:have|know)|cannot (?:confirm|determine)|can't (?:confirm|determine)"],
            lookup: "northstar|warranty|field kit")
        ].map { |spec| spec.merge("group" => batch) }
      end

      def self.row(id, content, facts: [], support: [], requires: [], **extra)
        QualificationCasesA15.row(id, content, facts: facts, support: support, requires: requires, **extra)
      end

      def self.evaluate(event:, config:, spec:, before:, after:)
        QualificationCasesA15.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      end
    end
  end
end
