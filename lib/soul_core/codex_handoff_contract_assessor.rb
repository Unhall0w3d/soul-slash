
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module SoulCore
  class CodexHandoffContractAssessor
    REQUIRED_FIELDS = [
      "task",
      "repo_context",
      "allowed_files",
      "forbidden_files",
      "acceptance_criteria",
      "verifier_expectations",
      "security_boundaries",
      "output_format",
      "rollback_notes"
    ].freeze

    DEFAULT_ALLOWED_FILES = [
      "lib/soul_core/<new_feature>.rb",
      "scripts/verify-<feature>.rb",
      "docs/maintenance/<PHASE_DOC>.md",
      "docs/<FEATURE_DOC>.md"
    ].freeze

    DEFAULT_FORBIDDEN_FILES = [
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
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess(write_files: false, task: nil)
      normalized_task = normalize_task(task)
      contract = contract_for(normalized_task)
      output_path = nil

      if write_files
        output_path = write_contract(contract)
      end

      {
        "ok" => true,
        "assessment" => "codex_handoff_contract",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "read_only" => !write_files,
        "write_requested" => write_files,
        "contract_path" => output_path,
        "contract" => contract,
        "required_fields" => REQUIRED_FIELDS,
        "validation" => validate_contract(contract),
        "verification" => {
          "contract_only" => true,
          "no_codex_invoked" => true,
          "no_implementation_written" => true,
          "no_production_files_modified" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true,
          "writes_only_when_requested" => true
        }
      }
    end

    def render(report)
      contract = report.fetch("contract")
      lines = []
      lines << "Soul Codex Handoff Contract"
      lines << "Generated: #{report['generated_at']}"
      lines << "Task: #{contract['task']['id']}"
      lines << "Write requested: #{report['write_requested']}"
      lines << "Contract path: #{report['contract_path'] || 'not written'}"
      lines << ""
      lines << "Purpose"
      lines << contract.dig("task", "summary")
      lines << ""
      lines << "Required fields"
      report.fetch("required_fields").each { |field| lines << "- #{field}" }
      lines << ""
      lines << "Allowed files"
      contract.fetch("allowed_files").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Forbidden files"
      contract.fetch("forbidden_files").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Acceptance criteria"
      contract.fetch("acceptance_criteria").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Security boundaries"
      contract.fetch("security_boundaries").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Validation"
      report.fetch("validation").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def normalize_task(task)
      value = task.to_s.strip
      return "model_suitability_registry" if value.empty?

      value.tr("-", "_")
    end

    def contract_for(task_id)
      {
        "task" => {
          "id" => task_id,
          "title" => title_for(task_id),
          "summary" => "Produce a bounded implementation proposal or review artifact for #{task_id}.",
          "model_recommendation" => "gpt-5.5 medium",
          "status" => "handoff_contract_only"
        },
        "repo_context" => {
          "project" => "Soul",
          "language" => "Ruby",
          "scope" => "local-first assistant with explicit review and promotion gates",
          "current_boundaries" => [
            "Generated implementation work is advisory until reviewed.",
            "Alpha artifacts remain proposal-local until explicitly promoted.",
            "Codex output must be reviewed by deterministic verifiers and a human.",
            "Cloud/provider use must follow model suitability policy."
          ],
          "relevant_commands" => [
            "ruby bin/soul assess model-suitability",
            "ruby bin/soul assess model-policy",
            "ruby bin/soul assess feature-direction",
            "ruby bin/soul improve alpha-review --latest",
            "ruby bin/soul improve promotion-gate --latest"
          ]
        },
        "allowed_files" => DEFAULT_ALLOWED_FILES,
        "forbidden_files" => DEFAULT_FORBIDDEN_FILES,
        "acceptance_criteria" => [
          "Output must stay within the allowed file list.",
          "Output must include or update a deterministic verifier.",
          "Output must include documentation for the changed behavior.",
          "Output must not require secrets or provider activation.",
          "Output must not install packages or download models.",
          "Output must preserve existing CLI behavior unless explicitly requested.",
          "Output must include rollback notes."
        ],
        "verifier_expectations" => [
          "Verifier must check Ruby syntax for changed Ruby files.",
          "Verifier must check command output shape when a CLI is added.",
          "Verifier must check safety boundaries relevant to the task.",
          "Verifier must not require network access.",
          "Verifier must not mutate production paths except for explicitly requested files."
        ],
        "security_boundaries" => [
          "Do not read, print, or persist secrets.",
          "Do not modify .env or provider configuration.",
          "Do not enable cloud routing.",
          "Do not add background services.",
          "Do not capture screen, microphone, or file content unless explicitly part of the approved task.",
          "Do not delete files unless each path is explicitly listed."
        ],
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
          "State whether any generated artifacts can be deleted safely.",
          "State whether runtime behavior changes before promotion."
        ]
      }
    end

    def validate_contract(contract)
      missing = REQUIRED_FIELDS.reject { |field| contract.key?(field) }
      {
        "valid" => missing.empty?,
        "missing_fields" => missing,
        "allowed_files_count" => contract.fetch("allowed_files", []).length,
        "forbidden_files_count" => contract.fetch("forbidden_files", []).length,
        "acceptance_criteria_count" => contract.fetch("acceptance_criteria", []).length,
        "security_boundaries_count" => contract.fetch("security_boundaries", []).length
      }
    end

    def write_contract(contract)
      dir = File.join(@root, "Soul", "codex", "handoffs")
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{contract.dig('task', 'id')}.json")
      File.write(path, JSON.pretty_generate(contract))
      path
    end

    def title_for(task_id)
      task_id.split("_").map(&:capitalize).join(" ")
    end
  end
end
