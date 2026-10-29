# frozen_string_literal: true

module SoulCore
  module ChatReplacementCalibrationCases
    CASES = [
      {
        "id" => "cal-timeline-causal-order",
        "kind" => "plain",
        "reasoning_probe" => true,
        "messages" => [
          { "role" => "user", "content" => "In a fictional workshop log, the kiln was switched on at 08:10, a temperature warning appeared at 08:18, the room fan stopped at 08:22, the kiln was switched off at 08:25, and the warning cleared at 08:31. Summarize what the sequence establishes and what it does not establish, in at most 80 words." }
        ],
        "expected" => {
          "rubric" => "Give a concise, evidence-bounded reading of the fictional timeline.",
          "checks" => [
            "Preserves the event order and times: kiln on, warning, fan stopped, kiln off, warning cleared.",
            "Says the warning followed kiln startup and cleared after shutdown, without claiming either event caused it.",
            "Notes the log does not establish why the warning appeared or cleared, or whether the fan stop was related."
          ]
        }
      },
      {
        "id" => "cal-demo-sequence-55",
        "kind" => "plain",
        "reasoning_probe" => true,
        "messages" => [
          { "role" => "user", "content" => "Plan a fictional 55-minute preparation session for a tabletop display. Include these tasks in order: choose the layout (12 minutes); arrange the sample cards (18 minutes, after choosing the layout); write the title card (15 minutes, after arranging the cards); review the display (10 minutes, after the title card). Give a short timed sequence that ends at the 55-minute target. I will carry it out; just provide the plan in at most 140 words." }
        ],
        "expected" => {
          "rubric" => "Present the supplied tasks as a feasible plan totaling exactly 55 minutes and respecting every dependency.",
          "checks" => [
            "Lists layout choice for 12 minutes, card arrangement for 18, title card for 15, and review for 10, in that order.",
            "Makes clear card arrangement follows layout choice, title writing follows arrangement, and review follows title writing.",
            "Correctly totals 12 + 18 + 15 + 10 = 55 minutes and ends at the stated target."
          ]
        }
      },
      {
        "id" => "cal-display-options-budget",
        "kind" => "plain",
        "reasoning_probe" => true,
        "messages" => [
          { "role" => "user", "content" => "For a fictional tabletop display, suggest two different combinations within a $24 budget. Each combination must include exactly one support, one lettering item, and one accent. Prices: tabletop stand $12 or display mat $7; broad marker $5 or paint pen $9; paper tabs $3 or foil stickers $8. State each combination and its total in at most 140 words." }
        ],
        "expected" => {
          "rubric" => "Offer two distinct combinations, one item from each category, each costing no more than $24, with correct totals.",
          "checks" => [
            "Each option contains exactly one support, one lettering item, and one accent from the supplied list.",
            "Every stated total is computed from the supplied prices and is at most $24.",
            "The two combinations are distinct; all feasible choices are stand + broad marker + paper tabs = $20, stand + paint pen + paper tabs = $24, mat + broad marker + paper tabs = $15, mat + broad marker + foil stickers = $20, mat + paint pen + paper tabs = $19, and mat + paint pen + foil stickers = $24."
          ]
        }
      },
      {
        "id" => "cal-print-run-allocation",
        "kind" => "plain",
        "reasoning_probe" => true,
        "messages" => [
          { "role" => "user", "content" => "A fictional card print run has 6 cartons with 24 cards in each. Exactly 20 cards are discarded for smudges. One quarter of the remaining cards are reserved for sample packs. How many cards are left for standard packs? Show the arithmetic briefly in at most 140 words." }
        ],
        "expected" => {
          "rubric" => "Calculate the standard-pack quantity from the stated fictional counts and show a brief correct calculation.",
          "checks" => [
            "Computes 6 × 24 = 144 cards initially.",
            "Computes 144 − 20 = 124 cards after discards, then one quarter of 124 as 31 reserved sample cards.",
            "Answers 124 − 31 = 93 cards left for standard packs."
          ]
        }
      },
      {
        "id" => "cal-record-date-absent",
        "kind" => "plain",
        "reasoning_probe" => false,
        "messages" => [
          { "role" => "user", "content" => "A fictional note says: 'Ceramic badge, blue glaze; accepted after inspection.' What day was the inspection? Answer in at most 140 words." }
        ],
        "expected" => {
          "rubric" => "Answer from the note only and state clearly when the requested detail is absent.",
          "checks" => [
            "Says that the inspection day is not given in the supplied note.",
            "Does not invent a date or infer one from acceptance."
          ]
        }
      },
      {
        "id" => "cal-status-uncertainty-edit",
        "kind" => "plain",
        "reasoning_probe" => false,
        "messages" => [
          { "role" => "user", "content" => "Please make this fictional update clearer while keeping its uncertainty: 'sample labels printed tuesday. color check not finished. jo might send comments friday if she has time. final version could go out next week after signoff.' Keep the rewrite concise and under 140 words." }
        ],
        "expected" => {
          "rubric" => "Rewrite the note clearly and preserve every stated fact, uncertainty, and condition.",
          "checks" => [
            "Retains that sample labels were printed Tuesday and the color check is unfinished.",
            "Retains that Jo might send comments Friday if she has time; does not turn this into a commitment.",
            "Retains that the final version could go out next week only after signoff; does not imply signoff occurred."
          ]
        }
      },
      {
        "id" => "cal-corrected-book-club-line",
        "kind" => "plain",
        "reasoning_probe" => false,
        "messages" => [
          { "role" => "user", "content" => "I need one friendly opening sentence for an imaginary neighborhood book-club email." },
          { "role" => "assistant", "content" => "Here is a detailed agenda with six discussion sections." },
          { "role" => "user", "content" => "That is more than I need. Please give me just one friendly opening sentence, under 140 words." }
        ],
        "expected" => {
          "rubric" => "Follow the user's correction with one suitable friendly opening sentence.",
          "checks" => [
            "Provides exactly one sentence suitable as an opening for the book-club email.",
            "Uses a friendly tone and does not continue the agenda or discuss the correction."
          ]
        }
      },
      {
        "id" => "cal-recipe-cards-next-step",
        "kind" => "plain",
        "reasoning_probe" => false,
        "messages" => [
          { "role" => "user", "content" => "I finally sorted my recipe cards into a little box; they had been in a drawer for ages. Respond warmly and suggest one easy optional next step, in at most two sentences." }
        ],
        "expected" => {
          "rubric" => "Respond warmly to the user's small accomplishment and offer one easy, optional next step while leaving control with them.",
          "checks" => [
            "Acknowledges the accomplishment in a natural, warm way.",
            "Suggests one simple next step as optional, without implying the assistant will act or adding multiple tasks.",
            "Does not claim any facts beyond the user's note about sorting recipe cards into a box."
          ]
        }
      }
    ].freeze

    def self.deep_freeze(value)
      case value
      when Hash
        value.each { |key, entry| deep_freeze(key); deep_freeze(entry) }
      when Array
        value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end
    private_class_method :deep_freeze

    deep_freeze(CASES)

    def self.cases
      CASES
    end
  end
end
