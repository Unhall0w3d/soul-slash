# frozen_string_literal: true

module SoulCore
  class MusicQualificationService
    TARGET_DURATIONS = [43, 57, 71, 144, 248].freeze
    DURATION_TOLERANCE_SECONDS = 2.0

    def initialize(music_generation:)
      @music_generation = music_generation
    end

    def snapshot
      listing = @music_generation.list_projects(limit: 200)
      return listing unless listing.fetch("ok")

      projects = Array(listing.dig("data", "projects")).select do |project|
        TARGET_DURATIONS.include?(Integer(project.fetch("target_duration_seconds")))
      rescue ArgumentError, TypeError, KeyError
        false
      end
      samples = []
      inspection_failures = []
      projects.each do |project|
        inspected = @music_generation.inspect_project(project_id: project.fetch("project_id"))
        unless inspected.fetch("ok")
          inspection_failures << {
            "project_id" => project.fetch("project_id"),
            "reason" => inspected["reason"] || inspected["message"] || "inspection failed"
          }
          next
        end
        samples << summarize(inspected.dig("data", "project"), inspected.dig("data", "generations"))
      end

      coverage = TARGET_DURATIONS.map { |duration| duration_coverage(samples, duration) }
      data = {
        "schema_version" => "soul.music.qualification.v1",
        "qualification_authority" => "human",
        "automatic_qualification" => false,
        "target_durations" => TARGET_DURATIONS,
        "project_count" => samples.length,
        "candidate_count" => samples.sum { |sample| sample.fetch("candidate_count") },
        "reviewed_count" => samples.sum { |sample| sample.fetch("reviewed_count") },
        "unreviewed_count" => samples.sum { |sample| sample.fetch("unreviewed_count") },
        "inspection_failures" => inspection_failures,
        "coverage" => coverage,
        "projects" => samples.sort_by { |sample| [sample.fetch("duration_seconds"), sample.fetch("title")] },
        "evidence_state" => evidence_state(coverage, samples, inspection_failures),
        "next_review" => next_review(coverage, samples, inspection_failures)
      }
      outcome("complete", true, "music qualification evidence inspected", data)
    rescue KeyError, ArgumentError, TypeError => error
      outcome("awaiting_input", false, error.message, {})
    rescue StandardError => error
      outcome("failed", false, "music qualification failed safely: #{error.class}", {})
    end

    private

    def summarize(project, generations)
      candidates = Array(generations)
      target = Integer(project.fetch("target_duration_seconds"))
      summarized = candidates.map { |candidate| summarize_candidate(candidate, target) }
      latest = summarized.first
      {
        "project_id" => project.fetch("project_id"),
        "title" => project.fetch("title"),
        "duration_seconds" => target,
        "vocal_mode" => project.fetch("vocal_mode"),
        "candidate_count" => summarized.length,
        "reviewed_count" => summarized.count { |candidate| candidate.fetch("review") },
        "unreviewed_count" => summarized.count { |candidate| candidate["review"].nil? },
        "revision_count" => summarized.count { |candidate| candidate.fetch("generation_kind") == "revision" },
        "state" => project_state(latest),
        "latest_candidate" => latest,
        "technical_candidate_present" => summarized.any? { |candidate| candidate.fetch("technical_ready") },
        "kept_candidate_present" => summarized.any? { |candidate| candidate.dig("review", "disposition") == "keep" }
      }
    end

    def summarize_candidate(candidate, target)
      artifact = candidate.dig("artifacts", "flac") || {}
      actual = Float(artifact.fetch("duration_seconds", 0))
      review = candidate["review"]
      {
        "candidate_id" => candidate.fetch("candidate_id"),
        "created_at" => candidate.fetch("created_at"),
        "generation_kind" => candidate.fetch("generation_kind", "initial"),
        "source_candidate_id" => candidate["source_candidate_id"],
        "actual_duration_seconds" => actual.round(3),
        "duration_delta_seconds" => (actual - target).round(3),
        "generation_seconds" => numeric(candidate.dig("timings", "total_seconds")),
        "technical_ready" => actual.positive? && (actual - target).abs <= DURATION_TOLERANCE_SECONDS &&
          artifact["sample_rate"] == 48_000 && artifact["channels"] == 2 && artifact["codec"] == "flac",
        "review" => review && review.slice("disposition", "musical_quality", "prompt_adherence", "vocals", "lyrics", "overall_rating", "notes")
      }
    rescue ArgumentError, TypeError
      raise ArgumentError, "music candidate duration evidence is invalid"
    end

    def duration_coverage(samples, duration)
      matching = samples.select { |sample| sample.fetch("duration_seconds") == duration }
      {
        "duration_seconds" => duration,
        "project_count" => matching.length,
        "candidate_count" => matching.sum { |sample| sample.fetch("candidate_count") },
        "reviewed_count" => matching.sum { |sample| sample.fetch("reviewed_count") },
        "technical_evidence_present" => matching.any? { |sample| sample.fetch("technical_candidate_present") },
        "kept_evidence_present" => matching.any? { |sample| sample.fetch("kept_candidate_present") },
        "current_states" => matching.map { |sample| sample.fetch("state") }.uniq.sort
      }
    end

    def project_state(latest)
      return "no_candidate" unless latest
      return "awaiting_review" unless latest["review"]

      case latest.dig("review", "disposition")
      when "keep" then "kept"
      when "revise" then "revision_requested"
      when "reject" then "rejected"
      else "review_attention"
      end
    end

    def evidence_state(coverage, samples, failures)
      return "archive_attention" if failures.any?
      return "duration_gaps" unless coverage.all? { |item| item.fetch("technical_evidence_present") }
      return "unreviewed_candidates" if samples.any? { |sample| sample.fetch("state") == "awaiting_review" }
      return "revision_required" unless coverage.all? { |item| item.fetch("kept_evidence_present") }

      "ready_for_human_qualification_decision"
    end

    def next_review(coverage, samples, failures)
      return "Resolve the reported project-inspection failures before qualifying the music cohort." if failures.any?
      missing = coverage.reject { |item| item.fetch("technical_evidence_present") }.map { |item| item.fetch("duration_seconds") }
      return "Generate and inspect technical evidence for: #{missing.join(', ')} seconds." if missing.any?
      pending = samples.select { |sample| sample.fetch("state") == "awaiting_review" }.map { |sample| sample.fetch("title") }
      return "Review the latest retained candidate for: #{pending.join('; ')}." if pending.any?
      revisions = coverage.reject { |item| item.fetch("kept_evidence_present") }.map { |item| item.fetch("duration_seconds") }
      return "Complete revision review for: #{revisions.join(', ')} seconds." if revisions.any?

      "Compare coherence, adherence, endings, and transition utility; only the Operator may qualify the duration cohort."
    end

    def numeric(value)
      value.nil? ? nil : Float(value).round(3)
    rescue ArgumentError, TypeError
      nil
    end

    def outcome(state, ok, message, data)
      { "lifecycle_state" => state, "ok" => ok, "message" => message, "data" => data, "mutation" => "none" }
    end
  end
end
