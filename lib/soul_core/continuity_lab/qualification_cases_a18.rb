# frozen_string_literal: true

require_relative "qualification_cases_a17"
require_relative "usability_assessment_a18"

module SoulCore
  module ContinuityLab
    # A18 adds a frozen held-out direct-evidence transfer batch. Historical
    # batches remain delegated to A17 byte-for-byte.
    module QualificationCasesA18
      VERSION = "foreground_usability_a18_v1"
      HELDOUT = "Silverfen repair-parts sheet. Ash crate: 5 seals, 16 credits. Maple crate: 14 seals, 33 credits. Cedar crate: 13 seals, 37 credits. Birch crate: 17 seals, 43 credits. Each crate is in stock. Warranty period is not listed."
      NEAR_DISTRACTOR = "Bracken repair ledger, separate project: Finch units contain 19 seals and cost 46 credits. Alder units contain 22 seals and cost 53 credits. Warranty coverage lasts 3 months."
      UNRELATED = "Mallow workshop schedule: doors open in the morning; lunch begins at noon."
      UNKNOWN_FACT = "#{QualificationCasesA17::UNKNOWN_FACT}|not listed"

      def self.corpus(batch)
        return QualificationCasesA17.corpus(batch) unless batch == "heldout"

        [
          { "id" => "silverfen-parts", "content" => HELDOUT },
          { "id" => "bracken-ledger", "content" => NEAR_DISTRACTOR },
          { "id" => "mallow-schedule", "content" => UNRELATED }
        ]
      end

      def self.cases(batch)
        return QualificationCasesA17.cases(batch) unless batch == "heldout"

        [
          row("a18-plan", "For the Silverfen repair kit, which crate is the least expensive option that includes at least fifteen seals, and what is its price?",
            facts: ['\\bBirch\\b', '\\b43\\b'], support: [["corpus", "Silverfen", "Birch", "17", "43"]]),
          row("a18-change", "Actually, switch the plan to four Maple crates. How many seals would that give us altogether, and what would the total cost be?",
            facts: ['\\bMaple\\b', '\\b(?:56|fifty-six)\\b', '\\b132\\b'], support: [["corpus", "Silverfen", "Maple", "14", "33"]]),
          row("a18-callback", "Can you remind me which crate we switched to, how many, and the combined cost?",
            facts: ['\\bMaple\\b', '\\b(?:4|four)\\b', '\\b132\\b'], support: [["prior", "Maple", "(?:4|four)", "132"]], requires: ["a18-change"]),
          row("a18-absent", "What warranty period does the Silverfen parts sheet promise?",
            facts: [UNKNOWN_FACT], support: [["corpus", "Silverfen", "warranty", "not listed"]])
        ].map { |spec| spec.merge("group" => batch) }
      end

      def self.row(id, content, facts: [], support: [], requires: [], **extra)
        QualificationCasesA17.row(id, content, facts: facts, support: support, requires: requires, **extra)
      end

      def self.matches?(pattern, text)
        Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE).match?(text)
      end

      def self.evaluate(event:, config:, spec:, before:, after:)
        QualificationUsabilityAssessmentA18.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      end
    end
  end
end
