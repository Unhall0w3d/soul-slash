# frozen_string_literal: true

module SoulCore
  module ChatReplacementAdaptationCases
    CONVERSATIONS = [
      {
        "id" => "atrium-signage-work-update",
        "family" => "rewrite",
        "turns" => [
          {
            "user" => "Please clean up this note for the facilities update: 'I started checking the atrium signs; the east entrance is checked, the west one is not. I can ask for a ladder if the storage room is unlocked. We may finish Thursday if the replacement labels arrive.' Keep it clear and brief.",
            "expected" => {
              "checks" => [
                "State that the atrium sign check has started and only the east entrance is checked; the west entrance remains unchecked.",
                "Keep the ability to ask for a ladder conditional on the storage room being unlocked, without turning it into a promised request or a supplied ladder.",
                "Keep Thursday completion possible and dependent on the replacement labels arriving.",
                "Do not imply that the check or label replacement is complete."
              ],
              "rubric" => "Equivalent wording is fine; treating the west entrance as checked or dropping either condition is a material error. Minor style differences are not errors."
            }
          },
          {
            "user" => "Correction: I only began checking the east entrance; it is not finished yet. The west entrance is still untouched. Please give the final note with that correction. The ladder and label details are unchanged.",
            "expected" => {
              "checks" => [
                "Replace the earlier east-entrance completion claim with that check having started but not finished, and say the west entrance is untouched.",
                "Retain the ability to request a ladder if the storage room is unlocked, without promising the request, and retain the possible Thursday finish if labels arrive.",
                "Do not describe any check as completed or the labels as received."
              ],
              "rubric" => "Equivalent wording is fine; missing the correction or either unchanged condition is material, while minor phrasing differences are not."
            }
          }
        ]
      },
      {
        "id" => "archive-upload-status",
        "family" => "rewrite",
        "turns" => [
          {
            "user" => "Make this note easier to read for the archive team: 'The map scans are ready. I began uploading them this morning; two folders are still in progress. We can request a review slot if the catalog index is approved today. The public catalog may open next week, subject to the review.' Keep it concise.",
            "expected" => {
              "checks" => [
                "Say the map scans are ready, uploading began this morning, and two folders remain in progress.",
                "Keep the ability to request a review slot conditional on approval of the catalog index today; do not turn ability into a promised request or booked review.",
                "Describe opening the public catalog next week as possible and dependent on the review.",
                "Do not say the upload, index approval, review, or opening is complete."
              ],
              "rubric" => "Equivalent wording is fine; changing a work status or dropping a condition is material. Minor stylistic differences are not errors."
            }
          },
          {
            "user" => "One correction: only one folder is still uploading; the other folder finished after my note. Please give me the final concise update. The index, review, and opening conditions have not changed.",
            "expected" => {
              "checks" => [
                "Update the upload status to one folder complete and one folder still uploading, with uploading having begun this morning.",
                "Retain the ability to request a review slot if the index is approved today, without promising or booking it, and the possible next-week catalog opening subject to review.",
                "Do not imply that the remaining folder, index approval, review, or catalog opening is complete."
              ],
              "rubric" => "Equivalent wording is fine; omitting the folder correction is material, and losing a carried-forward qualification is a meaningful omission. The total number of map folders was not supplied; one remains unfinished. Minor style differences are not errors."
            }
          }
        ]
      },
      {
        "id" => "gallery-climate-observations",
        "family" => "incident",
        "turns" => [
          {
            "user" => "For a fictional gallery log: at 10:05 the east room felt warm; at 10:11 the wall display showed a humidity alert; at 10:16 staff opened the inner door; at 10:24 the alert was still showing. What does this sequence tell us?",
            "expected" => {
              "checks" => [
                "Summarize the observations in their stated order, distinguishing staff's report that the room felt warm from the display alert.",
                "Avoid asserting that warmth, the door, or another event caused the humidity alert.",
                "Make clear that the alert was still showing at 10:24 and no cause or resolution is established."
              ],
              "rubric" => "Equivalent wording is fine; reversing the observations or asserting a cause is material. A small stylistic difference is not, and no extra diagnosis is expected."
            }
          },
          {
            "user" => "Correction: the alert first appeared at 10:02, before the room felt warm at 10:05. Staff closed the inner door at 10:16 rather than opening it. After the 10:24 entry, a technician adjusted the display sensor, but no one checked or recorded the reading afterward. Please give the final handoff.",
            "expected" => {
              "checks" => [
                "Use the corrected sequence: alert at 10:02, room felt warm at 10:05, door closed at 10:16, alert still showing at 10:24, then the later sensor adjustment.",
                "State that no reading was checked or recorded after the sensor adjustment.",
                "Leave the cause and post-adjustment result unresolved; do not claim the adjustment cleared the alert."
              ],
              "rubric" => "Equivalent wording is fine; retaining superseded facts or claiming a post-adjustment result is material. Omitting the missing reading is a meaningful omission; style alone is not."
            }
          }
        ]
      },
      {
        "id" => "workshop-press-observations",
        "family" => "incident",
        "turns" => [
          {
            "user" => "A fictional print workshop noted this: the label press paused at 15:20, a paper-feed warning appeared at 15:24, and the operator cleared a scrap at 15:29. At 15:35 the warning light was off, but no further labels were run. Can you summarize this for the next shift?",
            "expected" => {
              "checks" => [
                "Report the pause, warning, scrap removal, and warning light being off in the supplied order.",
                "Do not claim the scrap caused the pause or warning, or that production returned to normal.",
                "Note that no labels were run after the warning light went off, so later operating behavior is unmeasured."
              ],
              "rubric" => "Equivalent wording is fine; changing the order or claiming normal production is material. Mentioning that no later labels were run is important; stylistic variation is not an error."
            }
          },
          {
            "user" => "Correction: the paper-feed warning appeared at 15:18, two minutes before the press paused. The scrap was cleared at 15:29 as noted, then a feed guide was adjusted. Nobody ran a label afterward to see whether feeding worked. Please write the final shift summary.",
            "expected" => {
              "checks" => [
                "Use the corrected order: warning at 15:18, press paused at 15:20, scrap cleared at 15:29, then the feed guide was adjusted.",
                "Say that no label was run after the guide adjustment, so its outcome is unknown.",
                "Do not infer that the scrap caused the pause or that the adjustment fixed the feed issue."
              ],
              "rubric" => "Equivalent wording is fine; using the old order or claiming the adjustment worked is material. Omitting the absent post-adjustment run is meaningful; style alone is not."
            }
          }
        ]
      },
      {
        "id" => "rainy-day-crossword-company",
        "family" => "conversation",
        "turns" => [
          {
            "user" => "I got stuck on a crossword clue for ages, then finally solved it while waiting for the kettle. It was a satisfying little win.",
            "expected" => {
              "checks" => [
                "Respond warmly to the small satisfaction of solving the clue.",
                "Do not invent the clue, answer, or claim to know what the crossword looked like."
              ],
              "rubric" => "A natural paraphrase is fine; inventing the clue or claiming visual access is material. Small tone differences are acceptable."
            }
          },
          {
            "user" => "It was more fun once I stopped trying to rush. I like just chatting about these little moments, no tips needed.",
            "expected" => {
              "checks" => [
                "Acknowledge that taking it slowly made the solve more enjoyable.",
                "Honor the preference for casual company without offering solving advice or a routine.",
                "Keep the exchange friendly and grounded in what the user shared."
              ],
              "rubric" => "Equivalent conversational wording is fine; unsolicited tips miss the stated preference. Minor differences in warmth or phrasing are stylistic, not factual errors."
            }
          }
        ]
      },
      {
        "id" => "scrap-paper-bookmark",
        "family" => "creative",
        "turns" => [
          {
            "user" => "I have ten minutes, a cereal-box panel, a pencil, and two colored pencils. Suggest a quick handmade bookmark I can make with those.",
            "expected" => {
              "checks" => [
                "Offer a simple bookmark idea that can reasonably be made in about ten minutes with the listed materials.",
                "Do not require supplies the user did not list."
              ],
              "rubric" => "Many ideas can satisfy the request; requiring unavailable materials or an impractical amount of work is material. Stylistic choices in the suggestion are flexible."
            }
          },
          {
            "user" => "Could it feel more playful and less polished? I like a bit of wonkiness in handmade things.",
            "expected" => {
              "checks" => [
                "Adapt the idea toward a playful, intentionally imperfect look.",
                "Keep it feasible with the same materials and short time window.",
                "Avoid treating neatness or precise symmetry as a requirement."
              ],
              "rubric" => "Several playful, imperfect approaches are acceptable; ignoring the preference or adding unlisted supplies is material. Differences in creative style are not errors."
            }
          }
        ]
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

    deep_freeze(CONVERSATIONS)

    def self.conversations
      CONVERSATIONS
    end
  end
end
