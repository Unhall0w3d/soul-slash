# frozen_string_literal: true

module SoulCore
  module ChatReplacementEntailmentCases
    module_function
    def cases
      [
        ["excluded-time", "The valve was replaced strictly after 16:10 and strictly before 16:30. The technician was Dara.",
         "Dara was the technician.", "Replacement happened between 16:10 and 16:30, excluding both endpoints.",
         "Replacement happened at exactly 16:10.", "contradicted", "The source explicitly excludes that endpoint."],
        ["unknown-time", "The switch was reset strictly after 11:00 and strictly before 11:40. The exact reset time was not recorded. The operator was Eli.",
         "Eli was the operator.", "The reset happened during the open interval from 11:00 to 11:40.",
         "The switch was reset at exactly 11:20.", "not established", "The midpoint is possible but not entailed or excluded."],
        ["unknown-condition", "Ten opaque jars arrived. Their labels were readable. Nobody inspected or tested their contents, and no information about the contents' condition is available.",
         "Ten jars arrived.", "The labels were readable; the condition of the contents is unknown.",
         "All ten jars contain spoiled material.", "not established", "Readable labels neither establish nor disprove spoiled contents."],
        ["conditional-action", "The permit was prepared. If the owner signs it, Jo may request an inspection. The owner has not yet signed. No inspection request has been made.",
         "The permit was prepared.", "Jo may request an inspection if the owner signs the permit.",
         "Jo will request an inspection next Monday.", "not established", "Conditional permission does not entail a future commitment or date."],
        ["exact-count", "Six of the twelve tested batteries passed. The other six failed. Testing ended on Friday.",
         "Testing ended on Friday.", "Half of the tested batteries passed.",
         "Nine of the twelve tested batteries passed.", "contradicted", "The exact passing count is six, not nine; the control requires valid arithmetic."],
        ["explicit-negative", "The hall is available on Wednesday. No booking has been made for Wednesday, and no deposit has been paid.",
         "The hall is available on Wednesday.", "Wednesday remains unbooked and no deposit has been paid.",
         "The hall has been booked for Wednesday and the deposit has been paid.", "contradicted", "Both actions are explicitly negated by the source."]
      ].map do |id, source, a, good, bad, label, rationale|
        { "id" => id, "source" => source, "a" => a, "faithful" => good, "distorted" => bad,
          "bad_label" => label, "rationale" => rationale }
      end
    end
  end
end
