
# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class FeatureDirectionAssessor
    Candidate = Struct.new(
      :id,
      :title,
      :summary,
      :recommended_phase,
      :scores,
      :rationale,
      :first_steps,
      :boundaries,
      :risks,
      keyword_init: true
    )

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      ranked = candidates.sort_by { |candidate| [-total_score(candidate), candidate.id] }

      {
        "ok" => true,
        "assessment" => "feature_direction",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "read_only" => true,
        "recommended_next_capability" => ranked.first.id,
        "recommended_next_title" => ranked.first.title,
        "ranked_candidates" => ranked.map.with_index(1) { |candidate, rank| serialize(candidate, rank) },
        "decision_policy" => {
          "prefer_low_risk_foundational_work" => true,
          "prefer_capability_gap_closure" => true,
          "prefer_local_first_features" => true,
          "require_human_approval_before_implementation" => true,
          "avoid_background_services_by_default" => true,
          "avoid_cloud_routing_without_explicit_policy" => true
        },
        "out_of_scope" => [
          {
            "id" => "automatic_skill_promotion",
            "reason" => "Promotion gates exist, but automatic promotion is intentionally not implemented."
          },
          {
            "id" => "background_screen_monitoring",
            "reason" => "Screen understanding must remain explicit and user-triggered."
          },
          {
            "id" => "continuous_audio_recording",
            "reason" => "Speech workflows require explicit activation and retention boundaries."
          }
        ],
        "verification" => {
          "advisory_only" => true,
          "no_files_modified" => true,
          "no_packages_installed" => true,
          "no_models_downloaded" => true,
          "no_runtime_configuration_changed" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Feature Direction Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Recommended next capability: #{report['recommended_next_capability']}"
      lines << "Recommended next title: #{report['recommended_next_title']}"
      lines << ""
      lines << "Ranked candidates"
      report.fetch("ranked_candidates").each do |candidate|
        lines << "#{candidate['rank']}. #{candidate['title']} [#{candidate['id']}]"
        lines << "   Score: #{candidate['total_score']}"
        lines << "   Phase: #{candidate['recommended_phase']}"
        lines << "   #{candidate['summary']}"
      end
      lines << ""
      lines << "Decision policy"
      report.fetch("decision_policy").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Out of scope"
      report.fetch("out_of_scope").each { |item| lines << "- #{item['id']}: #{item['reason']}" }
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def total_score(candidate)
      candidate.scores.values.sum
    end

    def serialize(candidate, rank)
      {
        "rank" => rank,
        "id" => candidate.id,
        "title" => candidate.title,
        "summary" => candidate.summary,
        "recommended_phase" => candidate.recommended_phase,
        "scores" => candidate.scores,
        "total_score" => total_score(candidate),
        "rationale" => candidate.rationale,
        "first_steps" => candidate.first_steps,
        "boundaries" => candidate.boundaries,
        "risks" => candidate.risks
      }
    end

    def candidates
      [
        Candidate.new(
          id: "model_suitability_registry",
          title: "Add model suitability registry",
          summary: "Create a local registry that maps available models and providers to safe task categories.",
          recommended_phase: "phase_25",
          scores: {
            "foundation_value" => 5,
            "implementation_safety" => 5,
            "dependency_reduction" => 4,
            "user_value" => 4,
            "complexity_fit" => 5
          },
          rationale: [
            "It supports future cloud/local routing without adding risky automation.",
            "It gives Soul a durable way to explain why a model is appropriate for a task.",
            "It helps future STT, vision, coding, and research workflows make bounded choices."
          ],
          first_steps: [
            "Define model capability schema.",
            "Record known local and cloud model roles without storing secrets.",
            "Add advisory CLI assessment output.",
            "Add verifier for schema shape and no runtime changes."
          ],
          boundaries: [
            "Do not download models.",
            "Do not enable cloud routing automatically.",
            "Do not persist secrets.",
            "Keep the assessment advisory."
          ],
          risks: [
            "Overstating model capabilities.",
            "Letting recommendations become implicit routing decisions.",
            "Treating online model popularity as proof of suitability."
          ]
        ),
        Candidate.new(
          id: "alpha_implementation_behavior",
          title: "Add alpha implementation behavior planning",
          summary: "Extend the alpha pipeline from scaffold generation toward implementation planning without promotion.",
          recommended_phase: "phase_26_candidate",
          scores: {
            "foundation_value" => 5,
            "implementation_safety" => 3,
            "dependency_reduction" => 3,
            "user_value" => 5,
            "complexity_fit" => 3
          },
          rationale: [
            "The alpha pipeline already generates proposals, plans, scaffolds, reviews, and promotion gates.",
            "The next useful step is to define how real implementation work is represented before promotion.",
            "This should remain plan-first because automatic code promotion is still intentionally blocked."
          ],
          first_steps: [
            "Define implementation task checklist format.",
            "Add explicit human approval fields.",
            "Require verifier and rollback notes before candidate implementation.",
            "Keep all generated implementation work proposal-local."
          ],
          boundaries: [
            "Do not promote generated code.",
            "Do not register generated skills.",
            "Do not modify production paths.",
            "Do not bypass alpha review or promotion gate."
          ],
          risks: [
            "Generating plausible but unsafe implementation code.",
            "Blurring review-only and production-ready states.",
            "Expanding scope faster than verifiers can cover."
          ]
        ),
        Candidate.new(
          id: "speech_to_text_assessment",
          title: "Add local speech-to-text assessment",
          summary: "Assess local microphone/audio stack readiness and local transcription options without recording audio.",
          recommended_phase: "phase_27_candidate",
          scores: {
            "foundation_value" => 4,
            "implementation_safety" => 4,
            "dependency_reduction" => 4,
            "user_value" => 5,
            "complexity_fit" => 3
          },
          rationale: [
            "Voice workflows are central to the Soul direction.",
            "A safe assessment phase can inspect local readiness without capturing audio.",
            "This should follow model suitability so transcription choices are classified consistently."
          ],
          first_steps: [
            "Detect audio stack and microphone visibility.",
            "Detect installed local STT tools without invoking recording.",
            "Define audio retention policy.",
            "Add explicit activation requirements."
          ],
          boundaries: [
            "Do not record audio.",
            "Do not run continuous listeners.",
            "Do not send audio to cloud providers.",
            "Do not store raw audio by default."
          ],
          risks: [
            "Accidental audio capture.",
            "Ambiguous activation policy.",
            "Cloud fallback without explicit approval."
          ]
        ),
        Candidate.new(
          id: "screen_understanding_assessment",
          title: "Add bounded screen understanding assessment",
          summary: "Assess screenshot and vision-model readiness for explicit user-triggered screen understanding workflows.",
          recommended_phase: "phase_28_candidate",
          scores: {
            "foundation_value" => 4,
            "implementation_safety" => 3,
            "dependency_reduction" => 3,
            "user_value" => 4,
            "complexity_fit" => 3
          },
          rationale: [
            "Screen understanding is useful for troubleshooting and UI interpretation.",
            "The privacy boundary must be defined before any screenshot capture exists.",
            "This should follow model suitability so local/cloud vision choices have policy context."
          ],
          first_steps: [
            "Define screenshot artifact policy.",
            "Detect Wayland screenshot tooling availability.",
            "Detect vision model/provider readiness.",
            "Require explicit user trigger and confirmation boundaries."
          ],
          boundaries: [
            "Do not monitor the screen in the background.",
            "Do not capture screenshots without explicit user action.",
            "Do not send screenshots to cloud providers without explicit approval.",
            "Do not store screenshots indefinitely by default."
          ],
          risks: [
            "Capturing sensitive screen content.",
            "Background monitoring creep.",
            "Unclear artifact retention."
          ]
        )
      ]
    end
  end
end
