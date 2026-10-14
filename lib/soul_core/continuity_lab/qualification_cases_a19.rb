# frozen_string_literal: true

require_relative "qualification_cases_a18"

module SoulCore
  module ContinuityLab
    # A19 adds a held-out chronological correction chain while keeping A18's
    # six established batches and assessment contract unchanged.
    module QualificationCasesA19
      VERSION = "chronological_corrections_a19_v1"
      CATALOG = "Tarnvale sensor catalog. Tavren pack: 26 sensors, 71 crowns. Uldara pack: 34 sensors, 89 crowns. Merith pack: 32 sensors, 101 crowns. Qorven pack: 39 sensors, 103 crowns."
      DISTRACTOR = "Duskfen instrument catalog, separate project: Orvail has 44 sensors for 127 crowns."
      UNRELATED = "Pellwick depot note: the north entrance opens at sunrise; deliveries pause during the bell hour."

      def self.corpus(batch)
        return QualificationCasesA18.corpus(batch) unless batch == "chronology"

        [
          { "id" => "tarnvale-sensors", "content" => CATALOG },
          { "id" => "duskfen-instruments", "content" => DISTRACTOR },
          { "id" => "pellwick-depot", "content" => UNRELATED }
        ]
      end

      def self.cases(batch)
        return QualificationCasesA18.cases(batch) unless batch == "chronology"

        [
          row("a19-plan", "For Tarnvale, which pack is the least expensive one containing at least thirty-two sensors, and what is its price?",
            facts: ['\\bUldara\\b', '\\b89\\b'], support: [["corpus", "Tarnvale", "Uldara", "34", "89"]]),
          row("a19-first-correction", "Actually, change the order to fifteen Merith packs. How many sensors would those packs contain altogether, and what would the total price be?",
            facts: ['\\bMerith\\b', '\\b(?:480|four hundred eighty)\\b', '\\b1515\\b'],
            support: [["corpus", "Tarnvale", "Merith", "32", "101"]], requires: ["a19-plan"]),
          row("a19-second-correction", "Correction: make that twenty Tavren packs instead. How many sensors do those packs contain, and what is the total price now?",
            facts: ['\\bTavren\\b', '\\b(?:520|five hundred twenty)\\b', '\\b1420\\b'],
            support: [["corpus", "Tarnvale", "Tavren", "26", "71"]], requires: ["a19-first-correction"]),
          row("a19-callback", "After my corrections, remind me which pack I chose, how many packs, and the total price.",
            facts: ['\\bTavren\\b', '\\b(?:20|twenty)\\b', '\\b1420\\b'],
            support: [["recent_dialogue", "Tavren", "20", "1420"]], requires: ["a19-second-correction"])
        ].map { |spec| spec.merge("group" => batch) }
      end

      def self.row(id, content, facts: [], support: [], requires: [], **extra)
        QualificationCasesA18.row(id, content, facts: facts, support: support, requires: requires, **extra)
      end

      def self.matches?(pattern, text)
        QualificationCasesA18.matches?(pattern, text)
      end

      def self.evaluate(event:, config:, spec:, before:, after:)
        QualificationUsabilityAssessmentA18.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      end
    end
  end
end
