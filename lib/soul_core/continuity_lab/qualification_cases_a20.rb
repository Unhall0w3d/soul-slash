# frozen_string_literal: true

require_relative "qualification_cases_a19"

module SoulCore
  module ContinuityLab
    # A20 freezes eight independent source-grounded selection requests. The
    # inherited A19 batches and their assessment contract remain delegated.
    module QualificationCasesA20
      VERSION = "constrained_selection_a20_v1"
      INHERITED_BATCHES = %w[planning holdout conversation transfer distractors heldout chronology].freeze
      FRESH_BATCHES = %w[lower_capacity upper_power combined_air stock_lantern budget_battery height_range no_eligible_printer setup_time_nas].freeze
      BATCHES = (INHERITED_BATCHES + FRESH_BATCHES).freeze

      FRESH = {
        "lower_capacity" => {
          "source_id" => "kestrel-rack-catalog",
          "source" => "Kestrel storage rack catalog. Ivara rack: 22 shelves, 54 crowns. Borlen rack: 28 shelves, 69 crowns. Cressa rack: 34 shelves, 77 crowns.",
          "prompt" => "For the Kestrel workshop, which rack is the least expensive option with at least 28 shelves, and what is its price?",
          "facts" => ['\\bBorlen\\b', '\\b69\\b'],
          "support" => ["Kestrel", "Borlen", "28", "69"]
        },
        "upper_power" => {
          "source_id" => "veltor-router-catalog",
          "source" => "Veltor router catalog. Aven router: 15 watts, 74 crowns. Branic router: 21 watts, 53 crowns. Corda router: 18 watts, 68 crowns. Deyra router: 12 watts, 82 crowns.",
          "prompt" => "Which Veltor router costs the least among models drawing no more than 18 watts, and what is its price?",
          "facts" => ['\\bCorda\\b', '\\b68\\b'],
          "support" => ["Veltor", "Corda", "18", "68"]
        },
        "combined_air" => {
          "source_id" => "orvale-purifier-catalog",
          "source" => "Orvale air purifier catalog. Leth purifier: 220 cubic meters per hour, 31 decibels, 91 crowns. Mavren purifier: 260 cubic meters per hour, 42 decibels, 88 crowns. Neris purifier: 248 cubic meters per hour, 36 decibels, 96 crowns. Pavor purifier: 280 cubic meters per hour, 38 decibels, 109 crowns.",
          "prompt" => "For Orvale, which purifier is least expensive while cleaning at least 240 cubic meters per hour and producing no more than 38 decibels, and what is its price?",
          "facts" => ['\\bNeris\\b', '\\b96\\b'],
          "support" => ["Orvale", "Neris", "248", "36", "96"]
        },
        "stock_lantern" => {
          "source_id" => "seldon-lantern-catalog",
          "source" => "Seldon trail lantern catalog. Ruvan lantern: 11 hours, out of stock, 42 crowns. Tovin lantern: 9 hours, in stock, 57 crowns. Wessa lantern: 13 hours, in stock, 64 crowns. Yorin lantern: 10 hours, out of stock, 39 crowns.",
          "prompt" => "Which Seldon lantern that is currently in stock runs for at least 9 hours at the lowest price, and what does it cost?",
          "facts" => ['\\bTovin\\b', '\\b57\\b'],
          "support" => ["Seldon", "Tovin", "9 hours", "in stock", "57"]
        },
        "budget_battery" => {
          "source_id" => "talven-battery-catalog",
          "source" => "Talven home battery catalog. Aster battery: 5 kilowatt-hours, 510 crowns. Brel battery: 8 kilowatt-hours, 638 crowns. Cevra battery: 9 kilowatt-hours, 704 crowns. Doran battery: 7 kilowatt-hours, 592 crowns.",
          "prompt" => "With a budget of at most 650 crowns, which Talven battery provides the greatest capacity, and how many kilowatt-hours does it provide?",
          "facts" => ['\\bBrel\\b', '\\b8\\b'],
          "support" => ["Talven", "Brel", "8 kilowatt-hours", "638"]
        },
        "height_range" => {
          "source_id" => "mirelle-shelf-catalog",
          "source" => "Mirelle display shelf catalog. Evran shelf: height 132 centimeters, 48 crowns. Falen shelf: height 145 centimeters, 61 crowns. Gireth shelf: height 172 centimeters, 67 crowns. Halen shelf: height 188 centimeters, 52 crowns.",
          "prompt" => "Which Mirelle shelf costs the least among models from 140 through 180 centimeters high, inclusive, and what is its price?",
          "facts" => ['\\bFalen\\b', '\\b61\\b'],
          "support" => ["Mirelle", "Falen", "145", "61"]
        },
        "no_eligible_printer" => {
          "source_id" => "corven-printer-catalog",
          "source" => "Corven production printer catalog. Jessa printer: 62 pages per minute, 870 crowns. Kelro printer: 74 pages per minute, 920 crowns. Luran printer: 81 pages per minute, 1010 crowns.",
          "prompt" => "Does any Corven printer reach at least 85 pages per minute? If so, name the least expensive qualifying model; if none do, say that none qualify.",
          "facts" => ['\\bnone\\b', '\\bqualif(?:y|ies)\\b'],
          "support" => ["Corven", "printer", "pages per minute"]
        },
        "setup_time_nas" => {
          "source_id" => "dunmere-nas-catalog",
          "source" => "Dunmere backup NAS catalog. Orin NAS: 4 drive bays, setup 32 minutes, 455 crowns. Pella NAS: 6 drive bays, setup 24 minutes, 525 crowns. Quorin NAS: 5 drive bays, setup 28 minutes, 482 crowns. Ressa NAS: 8 drive bays, setup 19 minutes, 610 crowns.",
          "prompt" => "Among Dunmere NAS units with at least 4 drive bays and a price no higher than 500 crowns, which has the shortest setup time, how many minutes is that, and what is its price?",
          "facts" => ['\\bQuorin\\b', '\\b28\\b', '\\b482\\b'],
          "support" => ["Dunmere", "Quorin", "5 drive bays", "28 minutes", "482"]
        }
      }.freeze

      def self.cases(batch)
        return QualificationCasesA19.cases(batch) unless FRESH.key?(batch)

        spec = FRESH.fetch(batch)
        [row("a20-#{batch.tr('_', '-')}", spec.fetch("prompt"), facts: spec.fetch("facts"),
          support: [["corpus", *spec.fetch("support")]]) .merge("group" => batch)]
      end

      def self.corpus(batch)
        return QualificationCasesA19.corpus(batch) unless FRESH.key?(batch)

        spec = FRESH.fetch(batch)
        [{ "id" => spec.fetch("source_id"), "content" => spec.fetch("source") }]
      end

      def self.row(id, content, facts: [], support: [], requires: [], **extra)
        QualificationCasesA19.row(id, content, facts: facts, support: support, requires: requires, **extra)
      end

      def self.matches?(pattern, text)
        QualificationCasesA19.matches?(pattern, text)
      end

      def self.evaluate(event:, config:, spec:, before:, after:)
        QualificationCasesA19.evaluate(event: event, config: config, spec: spec, before: before, after: after)
      end
    end
  end
end
