# frozen_string_literal: true

require_relative "music_project_store"

module SoulCore
  class MusicVocalDiagnosticService
    SCHEMA_VERSION = "soul.music.vocal_diagnostic.v1"
    STRUCTURAL_TAGS = %w[intro verse pre-chorus prechorus chorus hook bridge outro build drop breakdown instrumental solo interlude refrain].freeze
    VOCAL_MODIFIERS = ["whispered", "whisper", "raspy vocal", "falsetto", "powerful belting", "spoken word", "harmonies", "call and response", "ad-lib", "ad lib"].freeze
    MASKING_TERMS = ["almost inaudible", "inaudible", "broken transmission", "distant voice", "impossible distance", "chopped whisper", "trapped inside", "buried vocal"].freeze

    def initialize(music_generation:, analysis_service:)
      @music_generation = music_generation
      @analysis_service = analysis_service
    end

    def inspect(project_id:)
      result = @music_generation.inspect_project(project_id: project_id)
      return result unless result.fetch("ok", false)

      data = result.fetch("data")
      project = data.fetch("project")
      candidates = data.fetch("generations")
      payload = diagnostic(project, candidates)
      outcome("complete", true, payload.fetch("summary"), data: payload)
    rescue MusicProjectStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicProjectStore::IntegrityError, KeyError => error
      outcome("blocked_for_human_review", false, "retained vocal evidence is incomplete: #{error.message}")
    end

    private

    def diagnostic(project, candidates)
      instrumental = project.fetch("vocal_mode") == "instrumental"
      preflight = instrumental ? instrumental_preflight : vocal_preflight(project)
      attempts = attempt_evidence(project.fetch("project_id"), candidates)
      state = if instrumental
                "not_applicable"
              elsif attempts.fetch("lyric_failed_reviews") >= 2
                "repeated_adherence_failure"
              elsif preflight.fetch("risks").any?
                "vocal_risk_detected"
              else
                "preflight_clear"
              end
      recommendations = recommendations_for(preflight, attempts)
      {
        "schema_version" => SCHEMA_VERSION,
        "project_id" => project.fetch("project_id"),
        "title" => project.fetch("title"),
        "vocal_mode" => project.fetch("vocal_mode"),
        "state" => state,
        "summary" => summary_for(state, attempts),
        "authority" => {
          "classification" => "advisory_read_only",
          "human_review_required" => true,
          "blocks_generation" => false,
          "automatic_rewrite" => false,
          "automatic_generation" => false
        },
        "preflight" => preflight,
        "attempts" => attempts,
        "recommendations" => recommendations
      }
    end

    def instrumental_preflight
      {
        "state" => "not_applicable",
        "line_count" => 0,
        "word_count" => 0,
        "section_count" => 0,
        "lines" => [],
        "tags" => [],
        "risks" => []
      }
    end

    def vocal_preflight(project)
      lyrics = project.fetch("lyrics").to_s
      lines = lyric_lines(lyrics)
      tags = tag_evidence(lyrics)
      risks = []
      outside = lines.select { |line| !line.fetch("preferred_syllable_range") }
      risks << risk("line_pacing", "advisory", "#{outside.length} of #{lines.length} lyric lines fall outside the usual 6-10 syllable range", outside.map { |line| line.fetch("text") }) if outside.any?
      unanchored = tags.select { |tag| tag.fetch("classification") == "unanchored_performance" }
      risks << risk("unanchored_performance_sections", "advisory", "performance-only tags create separate pseudo-sections instead of anchoring delivery to a song section", unanchored.map { |tag| tag.fetch("raw") }) if unanchored.any?
      masking = masking_evidence(project.fetch("caption").to_s, lyrics)
      risks << risk("obscured_intelligibility", "material", "the creative brief explicitly asks the model to obscure or distance vocals", masking) if masking.any?
      if lines.length >= 2 && tags.length >= lines.length
        risks << risk("sparse_fragmentation", "advisory", "nearly every short lyric line is isolated behind its own tag", ["#{lines.length} lyric lines", "#{tags.length} tags"])
      end
      {
        "state" => risks.empty? ? "clear" : "risks_detected",
        "line_count" => lines.length,
        "word_count" => lines.sum { |line| line.fetch("word_count") },
        "section_count" => tags.length,
        "lines" => lines,
        "tags" => tags,
        "risks" => risks
      }
    end

    def lyric_lines(lyrics)
      lyrics.lines.map(&:strip).reject { |line| line.empty? || line.match?(/\A\[[^\]]+\]\z/) }.map do |text|
        syllables = estimated_syllables(text)
        {
          "text" => text,
          "word_count" => text.scan(/[[:alpha:]]+(?:['’][[:alpha:]]+)?/).length,
          "estimated_syllables" => syllables,
          "preferred_syllable_range" => syllables.between?(6, 10)
        }
      end
    end

    def tag_evidence(lyrics)
      lyrics.scan(/^\s*\[([^\]]+)\]\s*$/).flatten.map do |raw|
        normalized = raw.downcase.strip
        structural = STRUCTURAL_TAGS.find { |tag| normalized == tag || normalized.start_with?("#{tag} ") || normalized.start_with?("#{tag} -") || normalized.match?(/\A#{Regexp.escape(tag)}\s+\d+/) }
        modifier = VOCAL_MODIFIERS.find { |term| normalized.include?(term) }
        classification = if structural
                           modifier ? "anchored_structure_with_modifier" : "structural"
                         elsif modifier || masking_evidence("", raw).any?
                           "unanchored_performance"
                         else
                           "nonstandard"
                         end
        { "raw" => "[#{raw}]", "classification" => classification, "structure" => structural, "modifier" => modifier }
      end
    end

    def masking_evidence(caption, lyrics)
      text = "#{caption}\n#{lyrics}".downcase
      MASKING_TERMS.select { |term| text.include?(term) }.each_with_object([]) do |term, evidence|
        evidence << term unless evidence.any? { |existing| existing.include?(term) }
      end
    end

    def attempt_evidence(project_id, candidates)
      vocal_candidates = candidates.select { |candidate| vocal_candidate?(candidate) }
      reviews = vocal_candidates.filter_map { |candidate| candidate["review"] }
      lyric_outcomes = reviews.map { |review| review["lyric_adherence"] }.compact
      analyses = vocal_candidates.filter_map do |candidate|
        analysis = @analysis_service.read(project_id: project_id, candidate_id: candidate.fetch("candidate_id"))
        next unless analysis
        recall = analysis.dig("alignment", "sequence_recall")
        { "candidate_id" => candidate.fetch("candidate_id"), "sequence_recall" => recall, "machine_route" => analysis["machine_route"] }
      end
      recalls = analyses.filter_map { |analysis| analysis["sequence_recall"]&.to_f }
      {
        "candidate_count" => candidates.length,
        "vocal_candidate_count" => vocal_candidates.length,
        "excluded_instrumental_candidate_count" => candidates.length - vocal_candidates.length,
        "reviewed_count" => reviews.length,
        "unreviewed_count" => vocal_candidates.length - reviews.length,
        "lyric_passed_reviews" => lyric_outcomes.count("passed"),
        "lyric_partial_reviews" => lyric_outcomes.count("partial"),
        "lyric_failed_reviews" => lyric_outcomes.count("failed"),
        "analysis_count" => analyses.length,
        "best_sequence_recall" => recalls.max,
        "latest_sequence_recall" => analyses.first&.fetch("sequence_recall", nil),
        "analyses" => analyses
      }
    end

    def vocal_candidate?(candidate)
      lyrics = candidate.dig("generation_input", "lyrics")
      return true if lyrics.nil?

      lyric_lines(lyrics.to_s).any?
    end

    def recommendations_for(preflight, attempts)
      return ["No vocal adherence diagnostic is needed for an instrumental project."] if preflight.fetch("state") == "not_applicable"

      codes = preflight.fetch("risks").map { |risk| risk.fetch("code") }
      items = []
      items << "Anchor delivery modifiers to standard sections, for example [Verse - whispered], rather than making each modifier a separate section." if codes.include?("unanchored_performance_sections") || codes.include?("sparse_fragmentation")
      items << "If intelligibility is required, remove directions that ask for inaudible, distant, buried, chopped, or transmission-damaged vocals; express the atmosphere in the instrumentation instead." if codes.include?("obscured_intelligibility")
      items << "Reshape very short fragments toward roughly 6-10 syllables per lyric line while preserving the intended words and cadence." if codes.include?("line_pacing")
      items << "Treat the retained failures as model evidence: revise one bounded variable at a time and preserve human listening review." if attempts.fetch("lyric_failed_reviews") >= 2
      items << "The current script has no deterministic risk flags, but generation remains probabilistic and still requires listening review." if items.empty?
      items
    end

    def estimated_syllables(text)
      words = text.downcase.scan(/[a-z]+(?:['’][a-z]+)?/)
      [words.sum { |word| syllables_in_word(word) }, words.empty? ? 0 : 1].max
    end

    def syllables_in_word(word)
      clean = word.gsub(/[^a-z]/, "")
      return 0 if clean.empty?
      groups = clean.scan(/[aeiouy]+/).length
      groups -= 1 if clean.length > 3 && clean.end_with?("e") && !clean.end_with?("le")
      [groups, 1].max
    end

    def risk(code, severity, explanation, evidence)
      { "code" => code, "severity" => severity, "explanation" => explanation, "evidence" => evidence }
    end

    def summary_for(state, attempts)
      case state
      when "not_applicable" then "instrumental project; vocal adherence is not applicable"
      when "repeated_adherence_failure" then "repeated structured lyric-adherence failures are retained for human diagnosis"
      when "vocal_risk_detected" then "the vocal brief contains advisory intelligibility risks"
      else "no deterministic vocal-feasibility risks were detected"
      end
    end

    def outcome(state, ok, message, data: nil)
      payload = { "lifecycle_state" => state, "ok" => ok, "message" => message, "errors" => [] }
      payload["data"] = data if data
      payload["errors"] << { "code" => state, "message" => message } unless ok
      payload
    end
  end
end
