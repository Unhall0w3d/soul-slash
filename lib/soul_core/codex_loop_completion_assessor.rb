
# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class CodexLoopCompletionAssessor
    REQUIRED_SOURCE_FILES = [
      "lib/soul_core/codex_handoff_contract_assessor.rb",
      "lib/soul_core/codex_dry_run_review.rb",
      "lib/soul_core/codex_dry_run_fixture_pack.rb",
      "lib/soul_core/first_bounded_codex_task.rb"
    ].freeze

    REQUIRED_DOCS = [
      "docs/CODEX_HANDOFF_CONTRACT.md",
      "docs/CODEX_DRY_RUN_REVIEW.md",
      "docs/CODEX_DRY_RUN_FIXTURE_PACK.md",
      "docs/FIRST_BOUNDED_CODEX_TASK.md"
    ].freeze

    REQUIRED_FIXTURES = [
      "docs/fixtures/codex_dry_run/safe_contract.json",
      "docs/fixtures/codex_dry_run/safe_response.json",
      "docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json",
      "docs/fixtures/codex_dry_run/blocked_response_missing_sections.json",
      "docs/fixtures/codex_dry_run/README.md"
    ].freeze

    LOOP_STAGES = [
      {
        "phase" => 27,
        "id" => "codex_handoff_contract",
        "command" => "ruby bin/soul assess codex-handoff",
        "purpose" => "Generate a bounded handoff contract."
      },
      {
        "phase" => 28,
        "id" => "codex_dry_run_review",
        "command" => "ruby bin/soul assess codex-dry-run-review --contract <contract.json> --response <response.json>",
        "purpose" => "Review Codex-style output without applying it."
      },
      {
        "phase" => 32,
        "id" => "codex_dry_run_fixtures",
        "command" => "ruby bin/soul improve codex-fixtures",
        "purpose" => "Generate safe pass/fail fixtures for the dry-run review gate."
      },
      {
        "phase" => 33,
        "id" => "first_bounded_codex_task",
        "command" => "ruby bin/soul improve bounded-codex-task",
        "purpose" => "Generate the first manual Codex task package."
      },
      {
        "phase" => 34,
        "id" => "human_applied_doc_change",
        "command" => "ruby scripts/verify-apply-codex-dry-run-fixture-doc-phase34.rb",
        "purpose" => "Verify the reviewed documentation change was applied deterministically."
      }
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      missing_sources = missing(REQUIRED_SOURCE_FILES)
      missing_docs = missing(REQUIRED_DOCS)
      missing_fixtures = missing(REQUIRED_FIXTURES)

      app = read_file("lib/soul_core/app.rb")
      docs = read_file("docs/CODEX_DRY_RUN_FIXTURE_PACK.md")

      missing_routes = []
      missing_routes << "codex-handoff" unless app.include?('"codex-handoff", "handoff-contract", "codex-contract"')
      missing_routes << "codex-dry-run-review" unless app.include?('"codex-dry-run-review", "codex-review", "handoff-review"')
      missing_routes << "codex-fixtures" unless app.include?('"codex-fixtures", "codex-fixture-pack", "dry-run-fixtures"')
      missing_routes << "bounded-codex-task" unless app.include?('"bounded-codex-task", "first-codex-task", "codex-task"')

      doc_checks = {
        "preflight_section" => docs.include?("## Before a real Codex task"),
        "safe_fixture_expected" => docs.include?("`review_ready`"),
        "blocked_fixture_expected" => docs.include?("`blocked`"),
        "no_auto_apply_warning" => docs.include?("Do not apply Codex output automatically."),
        "safe_fixture_command" => docs.include?("safe_response.json"),
        "blocked_forbidden_command" => docs.include?("blocked_response_forbidden_file.json"),
        "blocked_missing_sections_command" => docs.include?("blocked_response_missing_sections.json")
      }

      local_artifact_paths = [
        "Soul/codex/tasks/phase33_first_bounded_task",
        "Soul/codex/tasks"
      ]
      local_artifacts_present = local_artifact_paths.select { |path| File.exist?(File.join(@root, path)) }

      blockers = []
      blockers << "Missing Codex loop source file(s): #{missing_sources.join(', ')}" unless missing_sources.empty?
      blockers << "Missing Codex loop documentation file(s): #{missing_docs.join(', ')}" unless missing_docs.empty?
      blockers << "Missing Codex dry-run fixture file(s): #{missing_fixtures.join(', ')}" unless missing_fixtures.empty?
      blockers << "Missing Codex loop app route(s): #{missing_routes.join(', ')}" unless missing_routes.empty?

      missing_doc_checks = doc_checks.select { |_key, value| value == false }.keys
      blockers << "Dry-run fixture documentation missing required preflight content: #{missing_doc_checks.join(', ')}" unless missing_doc_checks.empty?

      {
        "ok" => blockers.empty?,
        "assessment" => "codex_loop_completion",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "first_bounded_codex_loop_complete" : "blocked",
        "summary" => {
          "complete" => blockers.empty?,
          "meaning" => "Soul has completed the first bounded Codex loop: generate task package, manually use Codex, locally dry-run review the response, and apply the reviewed documentation change through a deterministic overlay.",
          "not_in_scope" => [
            "automatic Codex invocation",
            "automatic patch application",
            "automatic promotion",
            "provider activation",
            "secret handling",
            "runtime configuration mutation",
            "background services"
          ]
        },
        "loop_stages" => LOOP_STAGES,
        "required_source_files" => REQUIRED_SOURCE_FILES,
        "required_docs" => REQUIRED_DOCS,
        "required_fixtures" => REQUIRED_FIXTURES,
        "missing_source_files" => missing_sources,
        "missing_docs" => missing_docs,
        "missing_fixtures" => missing_fixtures,
        "missing_routes" => missing_routes,
        "documentation_checks" => doc_checks,
        "local_generated_artifacts" => {
          "checked_paths" => local_artifact_paths,
          "present" => local_artifacts_present,
          "required_for_completion" => false,
          "recommendation" => local_artifacts_present.empty? ? "No Phase 33 local task artifacts are present." : "Local task artifacts are present; remove them when no longer needed unless deliberately retained."
        },
        "next_optional_tracks" => [
          {
            "id" => "doctor_surface_expansion",
            "summary" => "Expand doctor so it validates more user-facing workflow routes, not just handler contracts."
          },
          {
            "id" => "documentation_registry_refresh",
            "summary" => "Refresh stale current-state docs against the active skill registry."
          },
          {
            "id" => "second_bounded_codex_task",
            "summary" => "Run another bounded Codex task with a more useful but still documentation-only scope."
          },
          {
            "id" => "local_stt_assessment",
            "summary" => "Begin local-only speech-to-text readiness assessment with no recording or provider activation."
          }
        ],
        "blockers" => blockers,
        "verification" => {
          "read_only" => true,
          "no_codex_invoked" => true,
          "no_patches_applied" => true,
          "no_files_modified" => true,
          "no_promotion_performed" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Codex Loop Completion Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << "Complete: #{report.dig('summary', 'complete')}"
      lines << ""
      lines << "Meaning"
      lines << report.dig("summary", "meaning")
      lines << ""
      lines << "Loop stages"
      report.fetch("loop_stages").each do |stage|
        lines << "- Phase #{stage['phase']}: #{stage['id']}"
        lines << "  #{stage['command']}"
        lines << "  #{stage['purpose']}"
      end
      lines << ""
      lines << "Documentation checks"
      report.fetch("documentation_checks").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Local generated artifacts"
      lines << "- present: #{report.dig('local_generated_artifacts', 'present').join(', ')}"
      lines << "- required_for_completion: #{report.dig('local_generated_artifacts', 'required_for_completion')}"
      lines << "- recommendation: #{report.dig('local_generated_artifacts', 'recommendation')}"
      lines << ""
      lines << "Not in scope"
      report.dig("summary", "not_in_scope").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Next optional tracks"
      report.fetch("next_optional_tracks").each { |item| lines << "- #{item['id']}: #{item['summary']}" }
      lines << ""
      lines << "Blockers"
      append_items(lines, report.fetch("blockers"))
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def missing(paths)
      paths.reject { |path| File.exist?(File.join(@root, path)) }
    end

    def read_file(path)
      full = File.join(@root, path)
      File.exist?(full) ? File.read(full) : ""
    end

    def append_items(lines, items)
      items = Array(items)
      if items.empty?
        lines << "- None"
      else
        items.each { |item| lines << "- #{item}" }
      end
    end
  end
end
