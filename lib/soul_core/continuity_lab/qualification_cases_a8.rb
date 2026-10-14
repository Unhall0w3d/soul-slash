# frozen_string_literal: true

require_relative "qualification_cases_a6"
require_relative "token_context"

module SoulCore
  module ContinuityLab
    # Fictional observations replace A6's low-entropy filler, not its task rules.
    module QualificationCasesA8
      VERSION = "meaningful_passage_comparison_a8_v1"
      LENGTH = QualificationCasesA6::LENGTH
      PASSAGES = [
        "At 06:15, the fictional Cedar outpost opened its river survey. Gauge R-17 read 1.42 m, compared with 1.38 m at 05:45; air temperature was 8.6 C and pressure was 1008.2 hPa. Mara logged three empty sample jars, labels C-101, C-102, and C-103, in the blue case. A north wind of 4.2 m/s moved mist toward the footbridge. The first boat departed at 06:28 with two observers and 12.5 L of fuel. Its route ran from pier 2 to buoy 7, then west to the reed bed. A spare battery showed 12.7 V without a load and 12.3 V during the lamp check. Rain from the previous night measured 6.4 mm. The crew expected muddy banks but found no floating debris. This entry covers conditions before sampling, not the later laboratory findings.",
        "By 07:05, the boat had reached station C-12, where water was 9.1 C and current speed was 0.38 m/s. Jar C-101 held a 250 mL surface sample; C-102 held 250 mL from 0.8 m below the surface. The third jar stayed sealed as a control. Mara noted 14 reeds in the first square, 11 in the second, and 9 in the third. A loose marker at buoy 7 had shifted 0.6 m downstream. The crew fixed its position in the paper log rather than moving the buoy. At 07:22, clouds covered about 70 percent of the sky. Visibility remained 2.4 km along the channel. The motor used 1.8 L of fuel before the return leg. A kingfisher crossed the bow twice. Both sample lids were dry, their seals were intact, and the blue case remained under the rear bench.",
        "The field laboratory received the case at 08:10. Balance B-04 showed 0.000 g with the tray empty, 50.002 g with the check mass, and 50.001 g on a second reading. Sample C-101 had pH 7.24, conductivity 412 uS/cm, and turbidity 8.6 NTU. Sample C-102 had pH 7.19, conductivity 419 uS/cm, and turbidity 9.3 NTU. The sealed control showed no leakage. Technician Ivo stored two 40 mL portions at 4.0 C and kept a 10 mL portion at 20.5 C for an afternoon comparison. The receipt listed 3 jars, 2 paper sheets, and 1 spare lid. A small scratch on the case did not extend through its wall. The laboratory clock was 11 seconds ahead of the pier clock. All values here belong to the morning samples rather than a seasonal average.",
        "At 14:35, Ivo compared the stored portions. The cool pair measured pH 7.22 and 7.18; the room-temperature portion measured pH 7.20. Conductivity differed by less than 3 uS/cm from the morning readings. A duplicate turbidity test gave 8.7 NTU for C-101 and 9.2 NTU for C-102. The afternoon report used the pier clock, corrected by 11 seconds. Mara signed page 4 and placed the record in drawer 6, behind the spring survey. The boat returned with 8.9 L of fuel, two dry life jackets, and a damp rope. A faded label on the spare lid was replaced; the sample labels were left intact. No jar was missing, and no result was assigned to the sealed control. The report ended after the inventory check.",
        "Marker OPAL-19. The fictional Larch observatory began a lens comparison at 21:05. Room A held 18.4 C, room B held 18.1 C, and outside air measured 7.8 C. Lens L-03 had a 60 mm aperture and a 240 mm focal length; lens L-08 had a 75 mm aperture and a 300 mm focal length. Neri counted 16 reference points on chart 2 and 12 on chart 3. A red lamp used 0.42 A at 5.1 V. The first exposure lasted 2.5 s, the second 3.0 s, and the third 3.5 s. Each image had a distinct paper label and a matching time in the log. One cardboard spacer was 0.8 mm thick; its replacement was 1.0 mm. Neither spacer touched the glass. At 21:12, humidity was 68%, pressure 1012.3 hPa, and clock offset +0.4 s; bench airflow was 0.12 m/s.",
        "At 22:10, lens L-03 resolved 14 of 16 reference points, while L-08 resolved 15. The chart distance was 18.0 m for both instruments. Focus positions were 24.2 mm and 25.6 mm from the marked stops. Neri repeated the comparison after 12 minutes: L-03 again resolved 14 points, and L-08 again resolved 15. Room A cooled to 18.0 C and room B to 17.9 C. A brief vibration from the dome motor affected image 6 but not images 5 or 7. The observer circled that entry without altering the recorded exposure. The red lamp stayed at 5.1 V, and the camera battery fell from 82 percent to 79 percent. A spare chart remained rolled in its tube. At 22:24, shutter delay was 0.08 s; test frames used ISO 400, f/4, 3.0 s, and a 2.0 s cooling pause.",
        "The final weather check occurred at 23:40. Cloud cover rose from 20 percent to 55 percent in 30 minutes; wind shifted from 270 degrees to 285 degrees at 3.6 m/s. Outside temperature was 6.9 C, with humidity at 81 percent and pressure at 1011.4 hPa. The dome shutters closed at 23:47. Neri returned lenses L-03 and L-08 to padded slots 1 and 2, then counted 4 spacers, 3 charts, and 2 lens caps. Image 6 retained its vibration note. The battery was disconnected at 76 percent, and the lamp cable was coiled beside the case. Morning staff received the signed log at 07:15. Storage was 18.2 C and 45% humidity at 07:20. Slots 1 and 2 measured 18.1 C; the dry case weighed 3.42 kg. Rain performance remained untested.",
      ].freeze
      raise ValidationError, "passage size" unless PASSAGES.all? { |p| p.length.between?(680, LENGTH - 21) }
      CORPUS = [
        { "id" => "long", "content" => PASSAGES.first(3).map { |p| p.ljust(LENGTH) }.join +
          PASSAGES[3].ljust(LENGTH - " Final marker TEAL-42.".length) + " Final marker TEAL-42." },
        { "id" => "rollover", "content" => PASSAGES.last(3).map { |p| p.ljust(LENGTH) }.join }
      ].freeze

      def self.cases
        QualificationCasesA6.cases.map do |spec|
          steps = spec.fetch("contract").fetch("steps").map do |step|
            args = step.fetch("action").fetch("arguments")
            source = CORPUS.find { |doc| doc.fetch("id") == args.fetch("id") }.fetch("content")
            QualificationCasesA4.read_step("corpus", args.fetch("id"), 1, source, args.fetch("start"), LENGTH)
          end
          spec.merge("contract" => spec.fetch("contract").merge("steps" => steps))
        end
      end

      def self.config(spec) = Config.qwen_v5_qualification(rollover: spec.fetch("condition") == "rollover")

      def self.expected_state(spec, lineage, call_index)
        state = QualificationCasesA6.expected_state(spec, lineage, call_index)
        state["corpus_digest"] = ContinuityLab.digest(CORPUS)
        state
      end

      def self.condition_evidence(event, spec) = QualificationCasesA6.condition_evidence(event, spec)

      # Sizing margin is a pre-generation guard, not evidence of model behavior.
      def self.calibration_evidence(spec, selected)
        budget = TokenContext.budget(config(spec))
        boundary = spec.fetch("pair") == "reread" ? 3 : 4
        raise ValidationError, "incomplete calibration" unless selected.length == 5 && selected.map { |row| row.fetch("call_index") } == (0..4).to_a
        visible = spec.fetch("condition") == "visible"
        margin = visible ? budget - selected.map { |row| row.fetch("input_tokens") }.max : selected.fetch(boundary).fetch("full_input_tokens") - budget
        retained = selected.fetch(boundary).fetch("included_groups")
        # The control is group-zero omission, not exactly one omitted group.
        # Packing must retain a nonempty contiguous suffix including the newest.
        condition = if visible
          selected.all? { |row| row.fetch("included_groups") == (0...row.fetch("call_index")).to_a }
        else
          retained.is_a?(Array) && retained.first.is_a?(Integer) &&
            retained.first.between?(1, boundary - 1) && retained == (retained.first...boundary).to_a
        end
        { "valid" => margin >= 64 && condition, "input_budget" => budget,
          "boundary_margin_tokens" => margin, "required_margin_tokens" => 64 }
      end
    end
  end
end
