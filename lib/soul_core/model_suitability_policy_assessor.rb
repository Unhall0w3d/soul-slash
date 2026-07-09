
# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class ModelSuitabilityPolicyAssessor
    POLICY_TIERS = {
      "local_only" => {
        "summary" => "Must remain local. Cloud routing is forbidden unless a future explicit override policy exists.",
        "examples" => [
          "secrets",
          "credentials",
          "private keys",
          "local private files",
          "raw audio",
          "screenshots containing private content",
          "unredacted customer data",
          "personal health, financial, or legal records"
        ],
        "allowed_provider_classes" => ["local_llm", "local_stt", "local_tts"],
        "requires_explicit_approval" => false,
        "cloud_allowed" => false
      },
      "approval_required" => {
        "summary" => "Cloud may be used only after explicit approval for a specific task and bounded context.",
        "examples" => [
          "repo context",
          "bounded coding tasks",
          "approved documentation drafts",
          "approved screenshots",
          "approved research synthesis",
          "long-context reasoning over non-secret material"
        ],
        "allowed_provider_classes" => ["local_llm", "approved_cloud_llm", "approved_cloud_vision"],
        "requires_explicit_approval" => true,
        "cloud_allowed" => true
      },
      "public_or_low_risk" => {
        "summary" => "Cloud may be suitable when the content is public, non-sensitive, and the task benefits from stronger external reasoning.",
        "examples" => [
          "public documentation",
          "public research sources",
          "non-sensitive README drafting",
          "generic architecture notes",
          "public API documentation synthesis"
        ],
        "allowed_provider_classes" => ["local_llm", "approved_cloud_llm"],
        "requires_explicit_approval" => true,
        "cloud_allowed" => true
      },
      "local_preferred" => {
        "summary" => "Local should be tried first, but approved cloud assistance may be used when quality or context demands it.",
        "examples" => [
          "summarization",
          "routing",
          "routine documentation",
          "non-sensitive long-context notes"
        ],
        "allowed_provider_classes" => ["local_llm", "approved_cloud_llm"],
        "requires_explicit_approval" => true,
        "cloud_allowed" => true
      }
    }.freeze

    TASK_POLICY = {
      "routing" => {
        "tier" => "local_preferred",
        "reason" => "Routine intent routing does not usually justify cloud use."
      },
      "summarization" => {
        "tier" => "local_preferred",
        "reason" => "Summarization sensitivity depends on the source material."
      },
      "coding" => {
        "tier" => "approval_required",
        "reason" => "Repo context and file changes must be bounded before cloud coding assistance."
      },
      "documentation" => {
        "tier" => "public_or_low_risk",
        "reason" => "Documentation can be cloud-assisted when based on approved non-sensitive context."
      },
      "research_synthesis" => {
        "tier" => "public_or_low_risk",
        "reason" => "Research synthesis often benefits from cloud capability, but sources and user data must be approved."
      },
      "vision" => {
        "tier" => "approval_required",
        "reason" => "Screenshots and images may contain sensitive information."
      },
      "speech_to_text" => {
        "tier" => "local_only",
        "reason" => "Raw voice/audio should remain local unless a future explicit override policy is created."
      },
      "text_to_speech" => {
        "tier" => "local_preferred",
        "reason" => "Routine assistant speech should prefer local synthesis."
      },
      "long_context" => {
        "tier" => "approval_required",
        "reason" => "Long context may include private repo, project, or user-specific material."
      },
      "local_privacy_sensitive" => {
        "tier" => "local_only",
        "reason" => "Privacy-sensitive tasks must not leave the machine."
      }
    }.freeze

    CODEX_BOUNDARY = {
      "recommended_model" => "gpt-5.5 medium",
      "allowed_use" => [
        "bounded implementation drafts",
        "single-task patch proposals",
        "verifier design",
        "documentation review",
        "acceptance-test suggestions",
        "risk review against explicit boundaries"
      ],
      "required_handoff_fields" => [
        "task",
        "repo_context",
        "allowed_files",
        "forbidden_files",
        "acceptance_criteria",
        "verifier_expectations",
        "security_boundaries",
        "output_format",
        "rollback_notes"
      ],
      "forbidden_use" => [
        "open-ended repo cleanup",
        "unbounded implementation",
        "secret handling",
        "provider activation",
        "automatic promotion",
        "runtime configuration changes",
        "dependency installation without approval",
        "file deletion without explicit paths"
      ]
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess(task: nil)
      normalized_task = normalize_task(task)
      policies = normalized_task ? {normalized_task => task_policy(normalized_task)} : all_task_policies

      {
        "ok" => true,
        "assessment" => "model_suitability_policy",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "read_only" => true,
        "selected_task" => normalized_task,
        "policy_tiers" => POLICY_TIERS,
        "task_policy" => policies,
        "codex_boundary" => CODEX_BOUNDARY,
        "approval_rules" => approval_rules,
        "verification" => {
          "advisory_only" => true,
          "no_files_modified" => true,
          "no_packages_installed" => true,
          "no_models_downloaded" => true,
          "no_providers_enabled" => true,
          "no_secrets_read" => true,
          "no_runtime_configuration_changed" => true,
          "no_cloud_routing_enabled" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Model Suitability Policy Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Selected task: #{report['selected_task'] || 'all'}"
      lines << ""
      lines << "Task policy"
      report.fetch("task_policy").each do |task, policy|
        lines << "- #{task}: #{policy['tier']}"
        lines << "  #{policy['reason']}"
        lines << "  cloud_allowed: #{policy['tier_details']['cloud_allowed']}"
        lines << "  requires_explicit_approval: #{policy['tier_details']['requires_explicit_approval']}"
      end
      lines << ""
      lines << "Codex boundary"
      lines << "- recommended_model: #{report.dig('codex_boundary', 'recommended_model')}"
      lines << "- allowed_use:"
      report.dig("codex_boundary", "allowed_use").each { |item| lines << "  - #{item}" }
      lines << "- forbidden_use:"
      report.dig("codex_boundary", "forbidden_use").each { |item| lines << "  - #{item}" }
      lines << ""
      lines << "Approval rules"
      report.fetch("approval_rules").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def normalize_task(task)
      return nil if task.nil? || task.strip.empty?

      value = task.strip.tr("-", "_")
      raise ArgumentError, "Unknown model suitability policy task: #{task}" unless TASK_POLICY.key?(value)

      value
    end

    def all_task_policies
      TASK_POLICY.keys.to_h { |task| [task, task_policy(task)] }
    end

    def task_policy(task)
      policy = TASK_POLICY.fetch(task)
      tier = policy.fetch("tier")
      {
        "tier" => tier,
        "reason" => policy.fetch("reason"),
        "tier_details" => POLICY_TIERS.fetch(tier)
      }
    end

    def approval_rules
      [
        "Cloud use requires explicit approval when repo context, screenshots, audio, private files, or long-context project material are involved.",
        "Local-only tasks must not be routed to cloud providers.",
        "Approval applies to a specific task and context, not to broad future use.",
        "Secrets, credentials, private keys, and raw audio are local-only by default.",
        "Codex handoffs must include allowed files, forbidden files, acceptance criteria, verifier expectations, and rollback notes.",
        "Model suitability scores are advisory and must not automatically route tasks."
      ]
    end
  end
end
