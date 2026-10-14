# frozen_string_literal: true

require_relative "qualification_cases_a16"
require_relative "usability_assessment_a17"

module SoulCore
  module ContinuityLab
    # A17 freezes a distinct multi-document transfer batch. Older batches and
    # their scoring contract remain owned by A15/A16.
    module QualificationCasesA17
      VERSION = "foreground_usability_a17_v1"
      DISTRACTORS = "Eastmere lighting catalog. Flint: 6 hours, 21 credits. Harbor: 10 hours, 38 credits. Lark: 9 hours, 41 credits. Warranty duration is not specified."
      NEAR_DISTRACTOR = "Westmere lighting comparison. Flint: 9 hours, 29 credits. Harbor: 12 hours, 47 credits. Lark: 11 hours, 52 credits. Separate project figures."
      UNRELATED = "Rivermill lunch menu. Lentil soup costs 7 credits. The courtyard closes at 6 pm."

      UNKNOWN_FACT = "not (?:recorded|provided|specified|confirmed|available)|no .*?(?:warranty|information|duration|terms)|unknown|unspecified|haven't|hasn't|don't (?:have|know)|cannot (?:confirm|determine)|can't (?:confirm|determine)|does not specify|doesn't specify"

      def self.corpus(batch)
        return QualificationCasesA16.corpus(batch) unless batch == "distractors"

        [
          { "id" => "eastmere-lighting", "content" => DISTRACTORS },
          { "id" => "westmere-lighting", "content" => NEAR_DISTRACTOR },
          { "id" => "rivermill-menu", "content" => UNRELATED }
        ]
      end

      def self.cases(batch)
        return QualificationCasesA16.cases(batch) unless batch == "distractors"

        [
          row("a17-plan", "For the Eastmere makerspace, which lighting kit is the least expensive option that can run for at least nine hours on battery, and what is its price?",
            facts: ['\\bHarbor\\b', '\\b38\\b'], support: [["corpus", "Eastmere", "Harbor", "10", "38"]], lookup: "eastmere|lighting|battery"),
          row("a17-change", "Let's change the Eastmere plan to three Lark kits. How many battery hours would those provide altogether, and what would the total price be?",
            facts: ['\\bLark\\b', '\\b(?:27|twenty-seven)\\b', '\\b123\\b'], support: [["corpus", "Eastmere", "Lark", "9", "41"]], lookup: "eastmere|lighting|lark"),
          row("a17-callback", "Could you remind me which kit I changed the plan to, how many we chose, and the combined price?",
            facts: ['\\bLark\\b', '\\b(?:3|three)\\b', '\\b123\\b'], support: [["prior", "Lark", "(?:3|three)", "123"]], requires: ["a17-change"]),
          row("a17-absent", "What warranty duration does the Eastmere lighting catalog specify?",
            facts: [UNKNOWN_FACT], support: [["corpus", "Eastmere", "Warranty duration is not specified"]], lookup: "eastmere|lighting|warranty")
        ].map { |spec| spec.merge("group" => batch) }
      end

      def self.row(id, content, facts: [], support: [], requires: [], **extra)
        QualificationCasesA16.row(id, content, facts: facts, support: support, requires: requires, **extra)
      end

      def self.matches?(pattern, text)
        Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE).match?(text)
      end

      # This API deliberately mirrors A16. Assessment is mechanical eligibility
      # only; natural-language correctness and social quality still need review.
      def self.evaluate(event:, config:, spec:, before:, after:)
        QualificationUsabilityAssessmentA17.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      end
    end
  end
end
