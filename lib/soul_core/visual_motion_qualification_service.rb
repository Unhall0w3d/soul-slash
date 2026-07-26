# frozen_string_literal: true

module SoulCore
  class VisualMotionQualificationService
    SUPPORTED_DURATIONS = [4, 8, 12].freeze

    def initialize(visual_studio:)
      @visual_studio = visual_studio
    end

    def snapshot
      listing = @visual_studio.list(limit: 200)
      return listing unless listing.fetch("ok")

      samples = []
      inspection_failures = []
      Array(listing.dig("data", "projects")).each do |project|
        inspected = @visual_studio.inspect(project_id: project.fetch("project_id"))
        unless inspected.fetch("ok")
          inspection_failures << {
            "project_id" => project.fetch("project_id"),
            "reason" => inspected["reason"] || inspected["message"] || "inspection failed"
          }
          next
        end

        full = inspected.dig("data", "project")
        samples.concat(Array(full["motions"]).map { |motion| summarize(full, motion) })
      end
      coverage = SUPPORTED_DURATIONS.map { |duration| duration_coverage(samples, duration) }
      reviewed = samples.count { |sample| sample["human_review"] }
      data = {
        "schema_version" => "soul.visual.motion_qualification.v1",
        "qualification_authority" => "human",
        "automatic_qualification" => false,
        "supported_durations" => SUPPORTED_DURATIONS,
        "sample_count" => samples.length,
        "reviewed_count" => reviewed,
        "unreviewed_count" => samples.length - reviewed,
        "inspection_failures" => inspection_failures,
        "coverage" => coverage,
        "samples" => samples.sort_by { |sample| sample["created_at"].to_s }.reverse,
        "evidence_state" => evidence_state(coverage, samples.length - reviewed, inspection_failures),
        "next_review" => next_review(coverage, samples.length - reviewed, inspection_failures)
      }
      outcome("complete", true, "visual motion qualification evidence inspected", data)
    rescue KeyError, ArgumentError => error
      outcome("awaiting_input", false, error.message, {})
    rescue StandardError => error
      outcome("failed", false, "visual motion qualification failed safely: #{error.class}", {})
    end

    private

    def summarize(project, motion)
      duration = motion["duration_seconds"].to_f
      elapsed = motion["elapsed_seconds"].to_f
      review = motion["review"]
      {
        "project_id" => project.fetch("project_id"),
        "project_title" => project.fetch("title"),
        "motion_candidate_id" => motion.fetch("motion_candidate_id"),
        "generation_kind" => motion.fetch("generation_kind", "image_to_video"),
        "source_motion_candidate_id" => motion["source_motion_candidate_id"],
        "profile_id" => motion["profile_id"],
        "duration_seconds" => duration.round(3),
        "delivery_fps" => motion["fps"],
        "generation_fps" => motion["generation_fps"] || motion["fps"],
        "delivery_method" => motion["delivery_method"] || "native",
        "elapsed_seconds" => elapsed.round(3),
        "runtime_per_output_second" => duration.positive? ? (elapsed / duration).round(2) : nil,
        "created_at" => motion["created_at"],
        "human_review" => review && {
          "disposition" => review["disposition"],
          "rating" => review["rating"],
          "notes" => review["notes"],
          "reviewed_at" => review["reviewed_at"]
        }
      }
    end

    def duration_coverage(samples, duration)
      matching = samples.select { |sample| (sample["duration_seconds"] - duration).abs < 0.2 }
      reviewed = matching.filter_map { |sample| sample["human_review"] }
      ratings = reviewed.filter_map do |review|
        Integer(review["rating"])
      rescue TypeError, ArgumentError
        nil
      end
      {
        "duration_seconds" => duration,
        "sample_count" => matching.length,
        "reviewed_count" => reviewed.length,
        "kept_count" => reviewed.count { |review| review["disposition"] == "keep" },
        "revise_count" => reviewed.count { |review| review["disposition"] == "revise" },
        "average_rating" => ratings.empty? ? nil : (ratings.sum.to_f / ratings.length).round(2),
        "human_evidence_present" => reviewed.any?
      }
    end

    def evidence_state(coverage, unreviewed, failures)
      return "archive_attention" if failures.any?
      return "no_samples" if coverage.sum { |item| item["sample_count"] }.zero?
      return "unreviewed_samples" if unreviewed.positive?
      return "duration_gaps" unless coverage.all? { |item| item["human_evidence_present"] }

      "ready_for_human_qualification_decision"
    end

    def next_review(coverage, unreviewed, failures)
      return "Resolve the reported project-inspection failures before qualifying the archive." if failures.any?
      return "Generate a bounded motion candidate and record a human review." if coverage.sum { |item| item["sample_count"] }.zero?
      return "Review the retained unreviewed motion candidates." if unreviewed.positive?
      missing = coverage.reject { |item| item["human_evidence_present"] }.map { |item| item["duration_seconds"] }
      return "Record human evidence for the missing supported durations: #{missing.join(', ')} seconds." if missing.any?

      "Compare fidelity, coherence, and scene adherence against runtime cost; only the Operator may qualify a profile."
    end

    def outcome(state, ok, message, data)
      {
        "lifecycle_state" => state,
        "ok" => ok,
        "message" => message,
        "data" => data,
        "mutation" => "none"
      }
    end
  end
end
