# frozen_string_literal: true

module SoulCore
  class AlphaBehaviorScaffold
    def initialize(metadata)
      @metadata = metadata
      @capability = metadata.fetch("capability", "unknown")
      @summary = metadata.fetch("summary", "Alpha behavior scaffold.")
    end

    def planned_artifacts
      case @capability
      when "alpha_skill_generation"
        [
          "implementation_plan.md",
          "skill.rb",
          "verify-alpha.rb",
          "test_cases.json",
          "promotion_checklist.md",
          "alpha_manifest.json"
        ]
      when "model_suitability_routing"
        [
          "model_capability_schema.json",
          "routing_policy.md",
          "model_roles.json",
          "verification_cases.json"
        ]
      when "vision_screen_understanding"
        [
          "screenshot_boundary_policy.md",
          "vision_runtime_requirements.json",
          "vision_workflow_contract.md",
          "privacy_review.md"
        ]
      when "speech_to_text"
        [
          "audio_boundary_policy.md",
          "stt_runtime_requirements.json",
          "transcription_skill_contract.md",
          "retention_policy.md"
        ]
      else
        [
          "implementation_plan.md",
          "skill.rb",
          "verify-alpha.rb",
          "test_cases.json"
        ]
      end
    end

    def behavior_steps
      case @capability
      when "alpha_skill_generation"
        [
          "Validate that the proposal folder exists.",
          "Validate proposal metadata and proposal markdown exist.",
          "Create an alpha folder under the proposal.",
          "Write proposal-local alpha artifacts only.",
          "Generate an alpha verifier.",
          "Record no registration and no production modification in the manifest."
        ]
      when "model_suitability_routing"
        [
          "Collect detected model endpoints.",
          "Load a local model capability registry.",
          "Map task categories to suitable models.",
          "Generate recommendations with resource and rollback notes."
        ]
      when "vision_screen_understanding"
        [
          "Require explicit user-triggered screenshot capture.",
          "Store image artifacts in a clearly configured local path.",
          "Invoke a local vision runtime when available.",
          "Return bounded observations for the provided image only."
        ]
      when "speech_to_text"
        [
          "Require explicit audio capture activation.",
          "Detect local microphone/audio stack readiness.",
          "Invoke a local speech-to-text runtime when available.",
          "Apply retention policy to generated audio/text artifacts."
        ]
      else
        [
          "Validate inputs.",
          "Run alpha-safe placeholder behavior.",
          "Return structured output.",
          "Preserve proposal-local boundaries."
        ]
      end
    end

    def risks
      case @capability
      when "alpha_skill_generation"
        [
          "Accidentally registering alpha skills before review.",
          "Writing generated files into production paths.",
          "Creating verifiers that only check file existence and not safety boundaries."
        ]
      when "model_suitability_routing"
        [
          "Routing sensitive tasks to inappropriate models.",
          "Treating model recommendations as authoritative without measurement.",
          "Downloading or replacing models automatically."
        ]
      when "vision_screen_understanding"
        [
          "Capturing private screen content without explicit request.",
          "Creating background monitoring behavior.",
          "Sending screenshots to cloud providers without approval."
        ]
      when "speech_to_text"
        [
          "Recording audio continuously.",
          "Retaining raw audio too long.",
          "Sending voice data to cloud providers without approval."
        ]
      else
        [
          "Expanding scope beyond the proposal.",
          "Bypassing human review.",
          "Producing artifacts that imply production readiness."
        ]
      end
    end

    def ruby_methods
      {
        "planned_artifacts" => planned_artifacts,
        "behavior_steps" => behavior_steps,
        "risks" => risks
      }
    end
  end
end
