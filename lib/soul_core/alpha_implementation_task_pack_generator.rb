
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require "pathname"

module SoulCore
  class AlphaImplementationTaskPackGenerator
    REQUIRED_FILES = [
      "implementation_task_pack.json",
      "implementation_task_pack.md",
      "codex_handoff_contract.json",
      "human_review_checklist.md",
      "rollback_plan.md"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def generate(proposal_path:)
      absolute_proposal_path = File.expand_path(proposal_path, @root)
      alpha_path = File.join(absolute_proposal_path, "alpha")

      raise ArgumentError, "Proposal path does not exist: #{proposal_path}" unless Dir.exist?(absolute_proposal_path)
      raise ArgumentError, "Alpha folder does not exist for proposal: #{proposal_path}" unless Dir.exist?(alpha_path)

      task_id = File.basename(absolute_proposal_path)
      generated_at = Time.now.iso8601
      pack = build_pack(task_id: task_id, proposal_path: relative_path(absolute_proposal_path), generated_at: generated_at)

      files = {
        "implementation_task_pack.json" => JSON.pretty_generate(pack),
        "implementation_task_pack.md" => render_pack_markdown(pack),
        "codex_handoff_contract.json" => JSON.pretty_generate(pack.fetch("codex_handoff_contract")),
        "human_review_checklist.md" => render_human_review(pack),
        "rollback_plan.md" => render_rollback(pack)
      }

      written = files.map do |filename, content|
        path = File.join(alpha_path, filename)
        File.write(path, content)
        relative_path(path)
      end

      {
        "ok" => true,
        "assessment" => "alpha_implementation_task_pack",
        "generated_at" => generated_at,
        "root" => @root,
        "proposal_path" => relative_path(absolute_proposal_path),
        "alpha_path" => relative_path(alpha_path),
        "task_id" => task_id,
        "written_files" => written,
        "task_pack" => pack,
        "promotion_allowed" => false,
        "implementation_written" => false,
        "codex_invoked" => false,
        "verification" => {
          "proposal_local_only" => true,
          "no_production_files_modified" => true,
          "no_codex_invoked" => true,
          "no_patches_applied" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Alpha Implementation Task Pack"
      lines << "Generated: #{report['generated_at']}"
      lines << "Proposal: #{report['proposal_path']}"
      lines << "Alpha path: #{report['alpha_path']}"
      lines << "Task: #{report['task_id']}"
      lines << ""
      lines << "Written files"
      report.fetch("written_files").each { |path| lines << "- #{path}" }
      lines << ""
      lines << "Boundaries"
      report.dig("task_pack", "boundaries").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Acceptance criteria"
      report.dig("task_pack", "acceptance_criteria").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def build_pack(task_id:, proposal_path:, generated_at:)
      allowed_files = [
        "lib/soul_core/<new_feature>.rb",
        "scripts/verify-<feature>.rb",
        "docs/maintenance/<PHASE_DOC>.md",
        "docs/<FEATURE_DOC>.md"
      ]

      forbidden_files = [
        ".env",
        ".env.*",
        "Soul/runtime/*",
        "Soul/improvement/proposals/*",
        "Soul/artifacts/cloud_assist/*",
        "Soul/proposals/skills/*",
        "config/secrets/*",
        "models/*",
        "vendor/*",
        "overlay_files/*"
      ]

      acceptance = [
        "Implementation proposal must stay within allowed file patterns.",
        "Implementation proposal must not modify generated proposal-local source except for task-pack artifacts.",
        "Implementation proposal must include or update a deterministic verifier.",
        "Implementation proposal must include documentation for changed behavior.",
        "Implementation proposal must not require secrets or provider activation.",
        "Implementation proposal must not install packages or download models.",
        "Implementation proposal must preserve existing CLI behavior unless explicitly requested.",
        "Implementation proposal must include rollback notes."
      ]

      verifier_expectations = [
        "Run ruby -c on changed Ruby files.",
        "Exercise any new CLI command with text and JSON output when applicable.",
        "Check advisory-only boundaries when the feature is not meant to mutate production state.",
        "Check generated files are proposal-local when generation is expected.",
        "Do not require network access.",
        "Do not invoke Codex from the verifier."
      ]

      security = [
        "Do not read, print, or persist secrets.",
        "Do not modify .env or provider configuration.",
        "Do not enable cloud routing.",
        "Do not add background services.",
        "Do not capture screen, microphone, or private file content.",
        "Do not delete files unless every path is explicitly listed."
      ]

      {
        "task" => {
          "id" => task_id,
          "proposal_path" => proposal_path,
          "status" => "implementation_task_pack_only",
          "generated_at" => generated_at,
          "model_recommendation" => "gpt-5.5 medium"
        },
        "codex_handoff_contract" => {
          "task" => {
            "id" => task_id,
            "title" => task_id.split(/[-_]/).map(&:capitalize).join(" "),
            "summary" => "Produce a bounded implementation proposal for #{task_id}.",
            "model_recommendation" => "gpt-5.5 medium",
            "status" => "handoff_contract_only"
          },
          "repo_context" => {
            "project" => "Soul",
            "language" => "Ruby",
            "scope" => "local-first assistant with explicit review and promotion gates",
            "proposal_path" => proposal_path,
            "current_boundaries" => [
              "Generated implementation work is advisory until reviewed.",
              "Alpha artifacts remain proposal-local until explicitly promoted.",
              "Codex output must be reviewed by deterministic verifiers and a human.",
              "Cloud/provider use must follow model suitability policy."
            ]
          },
          "allowed_files" => allowed_files,
          "forbidden_files" => forbidden_files,
          "acceptance_criteria" => acceptance,
          "verifier_expectations" => verifier_expectations,
          "security_boundaries" => security,
          "output_format" => {
            "preferred" => "patch_plan",
            "required_sections" => [
              "summary",
              "files_changed",
              "commands_to_verify",
              "risks",
              "rollback",
              "human_review_notes"
            ],
            "no_direct_commit" => true
          },
          "rollback_notes" => [
            "List every changed file.",
            "Describe how to revert each file.",
            "State whether generated artifacts can be deleted safely.",
            "State whether runtime behavior changes before promotion."
          ]
        },
        "allowed_files" => allowed_files,
        "forbidden_files" => forbidden_files,
        "acceptance_criteria" => acceptance,
        "verifier_expectations" => verifier_expectations,
        "security_boundaries" => security,
        "human_review_checklist" => [
          "Confirm the proposed implementation matches the proposal scope.",
          "Confirm every changed file is allowed by the handoff contract.",
          "Confirm forbidden paths are untouched.",
          "Confirm verifier coverage is deterministic and local.",
          "Confirm documentation explains user-visible behavior.",
          "Confirm rollback notes are practical.",
          "Confirm no secrets, provider activation, model downloads, or runtime config changes are introduced.",
          "Confirm promotion remains blocked until explicit approval."
        ],
        "rollback_plan" => [
          "Delete proposal-local generated implementation task-pack artifacts if abandoning the task.",
          "Revert any Codex-proposed production file changes before retrying.",
          "Keep alpha review and promotion gate outputs separate from implementation output.",
          "Do not promote implementation until review gate passes and human approval is recorded."
        ],
        "boundaries" => [
          "Do not invoke Codex.",
          "Do not apply patches.",
          "Do not write production implementation.",
          "Do not promote alpha artifacts.",
          "Do not alter runtime configuration."
        ]
      }
    end

    def render_pack_markdown(pack)
      lines = []
      lines << "# Alpha Implementation Task Pack"
      lines << ""
      lines << "Task: `#{pack.dig('task', 'id')}`"
      lines << ""
      lines << "## Model Recommendation"
      lines << ""
      lines << "`#{pack.dig('task', 'model_recommendation')}`"
      lines << ""
      lines << "## Allowed Files"
      pack.fetch("allowed_files").each { |item| lines << "- `#{item}`" }
      lines << ""
      lines << "## Forbidden Files"
      pack.fetch("forbidden_files").each { |item| lines << "- `#{item}`" }
      lines << ""
      lines << "## Acceptance Criteria"
      pack.fetch("acceptance_criteria").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "## Verifier Expectations"
      pack.fetch("verifier_expectations").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "## Boundaries"
      pack.fetch("boundaries").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    def render_human_review(pack)
      lines = ["# Human Review Checklist", ""]
      pack.fetch("human_review_checklist").each { |item| lines << "- [ ] #{item}" }
      lines.join("\n")
    end

    def render_rollback(pack)
      lines = ["# Rollback Plan", ""]
      pack.fetch("rollback_plan").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end
  end
end
