# frozen_string_literal: true

module SoulCore
  module ChatReplacementUsabilityCases
    CONVERSATIONS = [
      {
        "id" => "evening-watercolor-company",
        "rubric" => "Stay warm and conversational across turns, carry forward the user's preference for company over a productivity plan, and avoid inventing personal details or turning the exchange into a task list.",
        "turns" => [
          {
            "user" => "I finished a tiny watercolor of the old footbridge near my apartment. The reflections were fiddly, but I like how the blue came out.",
            "expected" => {
              "checks" => [
                "Acknowledge the completed watercolor and the user's satisfaction with the blue in a natural, warm way.",
                "Do not claim to have seen the painting or add facts about the user's home or location."
              ],
              "rubric" => "Respond as a friendly conversation partner to a small hobby accomplishment."
            }
          },
          {
            "user" => "Thanks. I mostly wanted someone to share the moment with me, not a plan for improving my painting. I like a little company when I show someone a finished piece.",
            "expected" => {
              "checks" => [
                "Accept the preference for company without defensiveness or offering an improvement routine.",
                "Respond with a brief, companionable comment rather than unsolicited steps or critique."
              ],
              "rubric" => "Honor the user's stated conversational preference and keep the tone easygoing."
            }
          },
          {
            "user" => "I added two little birds on the rail after all. What do you think of that choice?",
            "expected" => {
              "checks" => [
                "Recognize the birds as the user's addition and offer a warm, grounded reaction to the choice.",
                "Carry forward the preference for company rather than turning the reply into a lesson, critique, or plan.",
                "Do not claim visual access to the painting or assert what the birds look like."
              ],
              "rubric" => "Refer naturally to the new detail while maintaining the user's preferred companionable exchange."
            }
          }
        ]
      },
      {
        "id" => "sample-prototype-status-rewrite",
        "rubric" => "Rewrite only from supplied facts, preserve which work is complete and incomplete, keep another person's contribution conditional, and keep any release explicitly dependent on approval.",
        "turns" => [
          {
            "user" => "Please polish this status note for a project update: 'the sample prototype is assembled. fit check not finished. Mara can add the photos friday if the studio stays open. a public release may happen next month if the board approves it.' Keep it concise and factual.",
            "expected" => {
              "checks" => [
                "Retain that the sample prototype has been assembled and that the fit check is unfinished.",
                "Keep Mara's photo contribution conditional on the studio staying open; do not present it as promised.",
                "Describe next month's public release as only possible and dependent on board approval.",
                "Do not upgrade the sample prototype into a finished or production-ready product."
              ],
              "rubric" => "Produce a concise professional rewrite that preserves status, qualification, and conditions."
            }
          },
          {
            "user" => "Update: the fit check passed this morning. The photo and release details have not changed.",
            "expected" => {
              "checks" => [
                "Acknowledge that the fit check is now complete and passed this morning.",
                "Retain the unchanged conditional status of Mara's photos and the approval-dependent possible release.",
                "Do not continue to describe the fit check as unfinished."
              ],
              "rubric" => "Apply the user's correction and retain the other facts and conditions."
            }
          },
          {
            "user" => "Give me the final concise version now, with the sample qualifier and all conditions intact.",
            "expected" => {
              "checks" => [
                "State that the sample prototype is assembled and its fit check passed this morning.",
                "Keep Mara's photos contingent on the studio staying open.",
                "Keep public release next month possible only with board approval.",
                "Do not introduce dates, approvals, completed photos, or production status that were not supplied."
              ],
              "rubric" => "Deliver a concise final status note incorporating the corrected fact without losing qualifiers."
            }
          }
        ]
      },
      {
        "id" => "fictional-service-timeline-handoff",
        "rubric" => "Track the corrected chronology, separate reported observations from causal conclusions, state that there is no post-fix measurement, and make the handoff useful without inventing access or internal system details.",
        "turns" => [
          {
            "user" => "For a fictional service, the notes first showed: release 4.2 began at 14:00, delayed replies were reported at 14:05, a queue warning appeared at 14:09, restart began at 14:12, and replies seemed quicker at 14:15. What can we say from that sequence?",
            "expected" => {
              "checks" => [
                "Summarize the order as observations reported in the supplied notes.",
                "Distinguish timing or association from proof that the release, warning, or restart caused the reported changes.",
                "Name that the notes do not establish a cause or provide an objective measurement of reply speed."
              ],
              "rubric" => "Interpret the initial fictional timeline cautiously and identify what remains unproven."
            }
          },
          {
            "user" => "Correction to the notes: the queue warning was at 14:03, before delayed replies were reported at 14:07. Restart still began at 14:12. A configuration fix was applied afterward, but nobody measured replies after that fix.",
            "expected" => {
              "checks" => [
                "Use the corrected order: release at 14:00, queue warning at 14:03, delayed replies at 14:07, restart at 14:12, then the configuration fix.",
                "Explicitly retain that there was no reply measurement after the configuration fix.",
                "Do not treat the earlier apparent improvement as a measured post-fix result or assert a cause."
              ],
              "rubric" => "Replace the superseded chronology and preserve the key measurement limitation."
            }
          },
          {
            "user" => "Write a short handoff for the next on-call person, including what is observed and what still needs checking.",
            "expected" => {
              "checks" => [
                "Give a concise handoff that follows the corrected chronology and labels the entries as reports or observations.",
                "State that causation remains unknown and that reply behavior has not been measured after the configuration fix.",
                "Suggest a concrete verification such as collecting a post-fix reply-time measurement, without claiming it was done.",
                "Do not invent a diagnosis, system architecture, external access, or additional incident facts."
              ],
              "rubric" => "Provide a compact, useful next-shift handoff that clearly separates evidence from unknowns."
            }
          }
        ]
      },
      {
        "id" => "paper-lantern-evening-choice",
        "rubric" => "Offer grounded creative help within the user's time and materials, adapt when the user narrows the desired feel, and finish with one concrete step the user can choose to take without purchase or claimed action.",
        "turns" => [
          {
            "user" => "I have about 25 minutes to make a small table decoration for dinner. I can use one clean glass jar, scrap paper, string, scissors, and glue. Could you suggest a simple creative direction?",
            "expected" => {
              "checks" => [
                "Suggest a feasible small decoration using the listed materials and fitting roughly within 25 minutes.",
                "Keep the idea practical for a table and avoid requiring purchased or unlisted supplies.",
                "Present it as a suggestion, without implying anything has been made or arranged."
              ],
              "rubric" => "Give a specific, modest creative direction grounded in the available time and materials."
            }
          },
          {
            "user" => "I'd rather it feel loose and handmade than neat or symmetrical. Please adjust the idea around that preference.",
            "expected" => {
              "checks" => [
                "Adapt the suggestion toward an intentionally loose, handmade look.",
                "Continue to use only the supplied materials and respect the short time limit.",
                "Do not insist on symmetry, polished lettering, or an elaborate multi-stage project."
              ],
              "rubric" => "Carry forward the user's aesthetic preference while keeping the idea feasible."
            }
          },
          {
            "user" => "What's one concrete first step I can take?",
            "expected" => {
              "checks" => [
                "Give exactly one actionable first step that uses something already listed.",
                "Make the step consistent with the loose handmade direction and the 25-minute limit.",
                "Do not suggest a purchase or claim to have taken the step."
              ],
              "rubric" => "End with one concrete, user-controlled next step and no fabricated action."
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
