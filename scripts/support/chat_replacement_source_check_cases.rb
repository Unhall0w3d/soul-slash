# frozen_string_literal: true

module SoulCore
  module ChatReplacementSourceCheckCases
    module_function

    # Fresh synthetic pairs; the model sees neither variant names nor labels.
    # Claim A is a faithful paraphrase in every pair; only B varies.
    def cases
      [
        ["permission", "The badges are printed. We can ask for a courier if Finance approves the charge tomorrow.",
         "The badges have been printed.", "A courier request is possible if Finance approves the charge tomorrow.",
         "We will request a courier tomorrow.", "not established", "Ability is not commitment; tomorrow qualifies approval, not the request."],
        ["dependency", "The drawings are ready. Publication may happen in June, subject to board review. We can request that review if the index is approved.",
         "The drawings are ready.", "Publication in June is possible, subject to board review.",
         "Board review depends on publication happening in June.", "not established", "The draft reverses the dependency."],
        ["precision", "The pump stopped at 14:12. After the 14:20 log entry, Imani replaced a gauge. No subsequent reading was recorded.",
         "The pump stopped at 14:12.", "Imani replaced a gauge after the 14:20 entry; no later reading was recorded.",
         "Imani replaced a gauge at exactly 14:20.", "contradicted", "After the entry is not at that timestamp."],
        ["causality", "The warning lit at 09:04. Debris was removed at 09:09. The warning was off at 09:15. No cause was established.",
         "The warning was off by the 09:15 observation.", "Debris removal preceded the observation that the warning was off; the cause was not established.",
         "Removing debris caused the warning to clear.", "not established", "Order does not establish cause; lack of proof does not prove the cause false."],
        ["quantity", "The source does not give the total number or sizes of the parcels. One parcel remains to be packed. Labels have been printed.",
         "The labels are printed.", "One parcel still needs packing; the overall fraction completed is unknown.",
         "Packing is 90 percent complete.", "not established", "A remaining count cannot establish a fraction without the total."],
        ["observation", "A wall display showed a high-temperature alert. The room's actual temperature was not independently measured. The door remained closed.",
         "The door stayed closed.", "The display indicated high temperature, without an independent room-temperature measurement.",
         "The room was independently confirmed to be overheating.", "contradicted", "Independent confirmation is explicitly absent; the room's true temperature remains unknown."],
        ["entity", "A shelf sensor reported low battery. Noor wrote down the report but did not inspect the sensor. The note does not name a room.",
         "Noor recorded a low-battery report.", "The sensor was not inspected by Noor.",
         "The sensor was in the ceramics storeroom.", "not established", "No location was supplied; do not infer a plausible room."],
        ["scope", "Four crates were checked. Two had damaged seals, and two had intact seals. The contents were not inspected.",
         "Four crates were checked.", "Half the checked crates had damaged seals; their contents were not inspected.",
         "All four crates had damaged contents.", "not established", "Seal condition is not content condition; allow the valid half-of-four inference in the control."]
      ].map do |id, source, a, good, bad, label, rationale|
        { "id" => id, "source" => source, "a" => a, "faithful" => good, "distorted" => bad,
          "bad_label" => label, "rationale" => rationale }
      end
    end
  end
end
