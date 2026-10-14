# frozen_string_literal: true

require_relative "qualification_cases_a4"
require_relative "qualification_scorer"

module SoulCore
  module ContinuityLab
    # Synthetic paired diagnostic; no fixture response is injected into live work.
    module QualificationCasesA6
      VERSION = "visible_history_comparison_a6_v1"
      LENGTH = 768
      CORPUS = [
        { "id" => "long", "content" => ("x" * LENGTH) + ("y" * LENGTH) + ("z" * LENGTH) + ("w" * (LENGTH - " Final marker TEAL-42.".length)) + " Final marker TEAL-42." },
        { "id" => "rollover", "content" => "Marker OPAL-19.".ljust(LENGTH, "x") + ("y" * LENGTH) + ("z" * LENGTH) }
      ].freeze

      def self.cases
        tasks = {
          "four-reads" => { "id" => "long", "offsets" => [0, 768, 1536, 2304], "reply" => "TEAL-42",
            "content" => "Read corpus id long revision 1 using current lineage_id. Perform four reads IN ORDER: start 0 length 768, start 768 length 768, start 1536 length 768, start 2304 length 768. Do not skip a read even if the marker is found early. Then reply only with the final marker." },
          "reread" => { "id" => "rollover", "offsets" => [0, 768, 1536, 0], "reply" => "OPAL-19",
            "content" => "Read corpus id rollover revision 1 using current lineage_id. Perform four reads IN ORDER: start 0 length 768, start 768 length 768, start 1536 length 768, then start 0 length 768 AGAIN. The second read of start 0 is required. Then reply only with the marker in that final read." }
        }
        # Counterbalance pair order, without claiming randomization or replication.
        [["four-reads", "visible"], ["reread", "rollover"], ["four-reads", "rollover"], ["reread", "visible"]].map do |task, condition|
          row = tasks.fetch(task)
          source = CORPUS.find { |item| item["id"] == row["id"] }.fetch("content")
          { "id" => "#{task}-#{condition}", "pair" => task, "condition" => condition, "content" => row["content"],
            "contract" => { "steps" => row["offsets"].map { |start| QualificationCasesA4.read_step("corpus", row["id"], 1, source, start, LENGTH) },
                            "reply" => row["reply"] } }
        end
      end

      def self.config(spec) = Config.qwen_v4_qualification(rollover: spec.fetch("condition") == "rollover")

      # In-memory expected prefix only: never write it into the worker's journal.
      def self.expected_state(spec, lineage, call_index)
        raise ValidationError, "invalid expected prefix" unless call_index.is_a?(Integer) && (0..4).cover?(call_index)
        steps = spec.fetch("contract").fetch("steps").map do |step|
          { "action" => step["action"].merge("arguments" => step["action"]["arguments"].merge("lineage_id" => lineage)),
            "result" => step["result"].merge("source" => step["result"]["source"].merge("lineage_id" => lineage)) }
        end
        calls = steps.first(call_index).map { |step| { "response" => ContinuityLab.encode(step.fetch("action")), "result" => step.fetch("result") } }
        { "lineage_id" => lineage, "corpus_digest" => ContinuityLab.digest(CORPUS), "events" => {
          "comparison" => { "content" => spec.fetch("content"), "content_digest" => Digest::SHA256.hexdigest(spec.fetch("content")), "calls" => calls }
        } }
      end

      def self.condition_evidence(event, spec)
        calls = event.fetch("calls", [])
        rows = calls.each_with_index.map do |call, index|
          manifest = call.dig("context", "manifest")
          { "call_index" => index, "input_tokens" => manifest&.fetch("input_tokens", nil),
            "included_groups" => manifest&.fetch("included_groups", nil),
            "omitted_groups" => manifest&.fetch("omitted_groups", nil)&.map { |g| g.fetch("call_index") } }
        end
        planned = rows.first(5)
        complete_manifests = planned.length == 5 && planned.all? { |r| r["input_tokens"].is_a?(Integer) && r["included_groups"].is_a?(Array) && r["omitted_groups"].is_a?(Array) }
        all_visible = complete_manifests && planned.all? { |r| r["omitted_groups"].empty? && r["included_groups"] == (0...r["call_index"]).to_a }
        boundary = spec.fetch("pair") == "reread" ? 3 : 4
        decision = rows[boundary]
        omitted = decision && decision["omitted_groups"].is_a?(Array) && decision["included_groups"].is_a?(Array) &&
          decision["omitted_groups"].include?(0) && !decision["included_groups"].include?(0)
        { "planned_five_calls_observed" => complete_manifests, "planned_path_all_visible" => !!all_visible,
          "group_zero_omitted_at_boundary" => !!omitted, "boundary_call_index" => boundary,
          "intended_condition_observed" => spec.fetch("condition") == "visible" ? !!all_visible : !!omitted,
          "calls" => rows }
      end
    end
  end
end
