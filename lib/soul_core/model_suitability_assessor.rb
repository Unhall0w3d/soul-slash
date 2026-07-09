
# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class ModelSuitabilityAssessor
    TASKS = {
      "routing" => {
        "description" => "Classify user intent and select a bounded local workflow.",
        "privacy" => "medium",
        "preferred_execution" => "local",
        "criteria" => ["fast", "reliable", "low-cost", "structured-output"]
      },
      "summarization" => {
        "description" => "Summarize local text or user-provided artifacts.",
        "privacy" => "context-dependent",
        "preferred_execution" => "local-first",
        "criteria" => ["long-context", "faithful", "low-hallucination"]
      },
      "coding" => {
        "description" => "Draft or review code under an explicit file and verifier boundary.",
        "privacy" => "context-dependent",
        "preferred_execution" => "local-or-approved-cloud",
        "criteria" => ["code-reasoning", "test-awareness", "multi-file-awareness"]
      },
      "documentation" => {
        "description" => "Draft docs from approved outlines, local repo context, or explicit notes.",
        "privacy" => "low-to-medium",
        "preferred_execution" => "local-or-approved-cloud",
        "criteria" => ["clarity", "structure", "consistency"]
      },
      "research_synthesis" => {
        "description" => "Synthesize public or approved external research into reviewable notes.",
        "privacy" => "low-unless-user-data-included",
        "preferred_execution" => "approved-cloud",
        "criteria" => ["current-knowledge", "source-discipline", "long-context"]
      },
      "vision" => {
        "description" => "Interpret explicitly provided images or screenshots.",
        "privacy" => "high",
        "preferred_execution" => "local-first-explicit-cloud-approval",
        "criteria" => ["vision-capable", "explicit-input-only", "privacy-boundaries"]
      },
      "speech_to_text" => {
        "description" => "Transcribe explicitly activated audio.",
        "privacy" => "high",
        "preferred_execution" => "local",
        "criteria" => ["local-audio", "low-latency", "retention-policy"]
      },
      "text_to_speech" => {
        "description" => "Generate spoken output from approved response text.",
        "privacy" => "medium",
        "preferred_execution" => "local-first",
        "criteria" => ["local-voice", "latency", "quality"]
      },
      "long_context" => {
        "description" => "Handle large documents, repo summaries, or long project context.",
        "privacy" => "context-dependent",
        "preferred_execution" => "local-or-approved-cloud",
        "criteria" => ["long-context-window", "retrieval-friendly", "summary-fidelity"]
      },
      "local_privacy_sensitive" => {
        "description" => "Handle tasks involving secrets, credentials, private files, screenshots, audio, or personal data.",
        "privacy" => "very-high",
        "preferred_execution" => "local-only",
        "criteria" => ["offline-capable", "no-cloud", "no-persistence-by-default"]
      }
    }.freeze

    PROVIDERS = [
      {
        "id" => "local_llm",
        "name" => "Local LLM runtime",
        "execution" => "local",
        "secrets_required" => false,
        "activation_required" => false,
        "notes" => "Represents locally hosted text models. This assessment does not detect or start any model server."
      },
      {
        "id" => "local_stt",
        "name" => "Local speech-to-text runtime",
        "execution" => "local",
        "secrets_required" => false,
        "activation_required" => false,
        "notes" => "Represents local transcription engines. This assessment does not record audio or invoke transcription."
      },
      {
        "id" => "local_tts",
        "name" => "Local text-to-speech runtime",
        "execution" => "local",
        "secrets_required" => false,
        "activation_required" => false,
        "notes" => "Represents local speech synthesis engines. This assessment does not generate audio."
      },
      {
        "id" => "approved_cloud_llm",
        "name" => "Approved cloud LLM",
        "execution" => "cloud",
        "secrets_required" => true,
        "activation_required" => true,
        "notes" => "Represents an explicitly approved cloud provider. This assessment does not enable providers or read secrets."
      },
      {
        "id" => "approved_cloud_vision",
        "name" => "Approved cloud vision model",
        "execution" => "cloud",
        "secrets_required" => true,
        "activation_required" => true,
        "notes" => "Represents cloud vision only after explicit user approval for specific image context."
      }
    ].freeze

    SUITABILITY = {
      "routing" => [
        ["local_llm", 92, "Local routing avoids unnecessary cloud use and keeps routine intent parsing private."],
        ["approved_cloud_llm", 55, "Cloud routing is usually unnecessary unless local routing quality is insufficient."]
      ],
      "summarization" => [
        ["local_llm", 82, "Local summarization is preferred for private or routine material."],
        ["approved_cloud_llm", 76, "Cloud summarization can help for long or difficult public material when approved."]
      ],
      "coding" => [
        ["approved_cloud_llm", 88, "Cloud coding models are useful for bounded implementation drafts and reviews when repo context is approved."],
        ["local_llm", 68, "Local coding can help for small patches, but may struggle with broad multi-file reasoning."]
      ],
      "documentation" => [
        ["approved_cloud_llm", 84, "Cloud drafting is useful for polished docs from explicit outlines."],
        ["local_llm", 78, "Local drafting is appropriate for private notes and lightweight docs."]
      ],
      "research_synthesis" => [
        ["approved_cloud_llm", 90, "Research synthesis benefits from stronger current-knowledge and long-context capability when sources are public or approved."],
        ["local_llm", 45, "Local models may summarize supplied sources but should not be trusted for current research."]
      ],
      "vision" => [
        ["approved_cloud_vision", 78, "Cloud vision can be useful only with explicit image approval and retention boundaries."],
        ["local_llm", 35, "Generic local text models are not sufficient unless backed by a local vision model."]
      ],
      "speech_to_text" => [
        ["local_stt", 95, "Local STT is preferred for private voice workflows."],
        ["approved_cloud_llm", 35, "Cloud transcription should be avoided unless explicitly approved for a specific audio artifact."]
      ],
      "text_to_speech" => [
        ["local_tts", 92, "Local TTS is preferred for routine assistant speech output."],
        ["approved_cloud_llm", 30, "Cloud LLMs are not a TTS runtime by themselves."]
      ],
      "long_context" => [
        ["approved_cloud_llm", 86, "Approved cloud models may be useful for large-context reasoning when content is allowed to leave the machine."],
        ["local_llm", 62, "Local long-context suitability depends on installed model and hardware capacity."]
      ],
      "local_privacy_sensitive" => [
        ["local_llm", 80, "Local-only text handling is preferred for private content."],
        ["local_stt", 80, "Local-only transcription is preferred for private audio."],
        ["local_tts", 75, "Local TTS avoids sending response text to a third party."],
        ["approved_cloud_llm", 0, "Cloud use is not suitable for local-only privacy-sensitive tasks."]
      ]
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess(task: nil)
      normalized_task = normalize_task(task)
      tasks = normalized_task ? {normalized_task => TASKS.fetch(normalized_task)} : TASKS

      {
        "ok" => true,
        "assessment" => "model_suitability",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "read_only" => true,
        "selected_task" => normalized_task,
        "known_tasks" => TASKS.keys,
        "tasks" => tasks.transform_values { |details| details },
        "providers" => PROVIDERS,
        "suitability" => suitability_for(tasks.keys),
        "policy" => policy,
        "verification" => {
          "advisory_only" => true,
          "no_files_modified" => true,
          "no_packages_installed" => true,
          "no_models_downloaded" => true,
          "no_providers_enabled" => true,
          "no_secrets_read" => true,
          "no_runtime_configuration_changed" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Model Suitability Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Selected task: #{report['selected_task'] || 'all'}"
      lines << ""
      lines << "Known tasks"
      report.fetch("tasks").each do |task, details|
        lines << "- #{task}: #{details['description']}"
        lines << "  preferred_execution: #{details['preferred_execution']}"
        lines << "  privacy: #{details['privacy']}"
      end
      lines << ""
      lines << "Suitability"
      report.fetch("suitability").each do |task, entries|
        lines << "#{task}:"
        entries.each do |entry|
          lines << "- #{entry['provider_id']}: #{entry['score']} - #{entry['reason']}"
        end
      end
      lines << ""
      lines << "Policy"
      report.fetch("policy").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def normalize_task(task)
      return nil if task.nil? || task.strip.empty?
      value = task.strip.tr("-", "_")
      raise ArgumentError, "Unknown model suitability task: #{task}" unless TASKS.key?(value)
      value
    end

    def suitability_for(task_ids)
      task_ids.to_h do |task_id|
        entries = SUITABILITY.fetch(task_id).map do |provider_id, score, reason|
          {
            "provider_id" => provider_id,
            "provider_name" => provider_name(provider_id),
            "score" => score,
            "reason" => reason
          }
        end
        [task_id, entries]
      end
    end

    def provider_name(provider_id)
      provider = PROVIDERS.find { |item| item["id"] == provider_id }
      provider ? provider["name"] : provider_id
    end

    def policy
      [
        "Prefer local execution for private, audio, screenshot, credential, and local-file tasks.",
        "Require explicit approval before sending repo context, screenshots, audio, or private files to a cloud provider.",
        "Do not use model suitability assessment to enable providers automatically.",
        "Do not download models automatically.",
        "Do not store secrets in the suitability registry.",
        "Treat scores as advisory, not as automatic routing decisions.",
        "Codex or cloud coding tasks must receive bounded file lists, acceptance criteria, and verifier expectations."
      ]
    end
  end
end
