
# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class SkillLoopCompletionAssessor
    LOOP_STAGES = [
      {
        "phase" => 11,
        "id" => "environment_assessment",
        "command" => "ruby bin/soul assess environment",
        "purpose" => "Assess host environment readiness."
      },
      {
        "phase" => 12,
        "id" => "model_runtime_assessment",
        "command" => "ruby bin/soul assess models",
        "purpose" => "Assess local model/runtime visibility."
      },
      {
        "phase" => 13,
        "id" => "capability_matrix",
        "command" => "ruby bin/soul assess capabilities",
        "purpose" => "Assess capability gaps and improvement candidates."
      },
      {
        "phase" => 14,
        "id" => "proposal_generation",
        "command" => "ruby bin/soul improve proposals --write",
        "purpose" => "Generate reviewable improvement proposals."
      },
      {
        "phase" => 15,
        "id" => "alpha_generation",
        "command" => "ruby bin/soul improve alpha --latest",
        "purpose" => "Generate proposal-local alpha artifacts."
      },
      {
        "phase" => 18,
        "id" => "alpha_review",
        "command" => "ruby bin/soul improve alpha-review --latest",
        "purpose" => "Review alpha artifact readiness."
      },
      {
        "phase" => 19,
        "id" => "promotion_gate",
        "command" => "ruby bin/soul improve promotion-gate --latest",
        "purpose" => "Block or allow promotion based on explicit gate checks."
      },
      {
        "phase" => 24,
        "id" => "feature_direction",
        "command" => "ruby bin/soul assess feature-direction",
        "purpose" => "Rank next bounded feature direction."
      },
      {
        "phase" => 25,
        "id" => "model_suitability",
        "command" => "ruby bin/soul assess model-suitability",
        "purpose" => "Rank model/provider classes by task category."
      },
      {
        "phase" => 26,
        "id" => "model_policy",
        "command" => "ruby bin/soul assess model-policy",
        "purpose" => "Define local/cloud approval boundaries."
      },
      {
        "phase" => 27,
        "id" => "codex_handoff_contract",
        "command" => "ruby bin/soul assess codex-handoff",
        "purpose" => "Generate bounded Codex handoff contracts."
      },
      {
        "phase" => 28,
        "id" => "codex_dry_run_review",
        "command" => "ruby bin/soul assess codex-dry-run-review --contract <contract.json> --response <response.json>",
        "purpose" => "Review proposed Codex output against a handoff contract."
      },
      {
        "phase" => 29,
        "id" => "implementation_task_pack",
        "command" => "ruby bin/soul improve implementation-pack --latest",
        "purpose" => "Generate proposal-local implementation task packs."
      },
      {
        "phase" => 30,
        "id" => "implementation_review_gate",
        "command" => "ruby bin/soul improve implementation-review --latest",
        "purpose" => "Validate implementation task-pack structure before any promotion."
      }
    ].freeze

    REQUIRED_SOURCE_FILES = [
      "lib/soul_core/environment_assessor.rb",
      "lib/soul_core/model_runtime_assessor.rb",
      "lib/soul_core/capability_matrix.rb",
      "lib/soul_core/improvement_proposal_generator.rb",
      "lib/soul_core/alpha_skill_generator.rb",
      "lib/soul_core/alpha_review.rb",
      "lib/soul_core/alpha_promotion_gate.rb",
      "lib/soul_core/feature_direction_assessor.rb",
      "lib/soul_core/model_suitability_assessor.rb",
      "lib/soul_core/model_suitability_policy_assessor.rb",
      "lib/soul_core/codex_handoff_contract_assessor.rb",
      "lib/soul_core/codex_dry_run_review.rb",
      "lib/soul_core/alpha_implementation_task_pack_generator.rb",
      "lib/soul_core/alpha_implementation_review_gate.rb"
    ].freeze

    REQUIRED_DOCS = [
      "docs/FEATURE_DIRECTION.md",
      "docs/MODEL_SUITABILITY.md",
      "docs/MODEL_SUITABILITY_POLICY.md",
      "docs/CODEX_HANDOFF_CONTRACT.md",
      "docs/CODEX_DRY_RUN_REVIEW.md",
      "docs/ALPHA_IMPLEMENTATION_TASK_PACK.md",
      "docs/ALPHA_IMPLEMENTATION_REVIEW_GATE.md"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      missing_sources = REQUIRED_SOURCE_FILES.reject { |path| File.exist?(File.join(@root, path)) }
      missing_docs = REQUIRED_DOCS.reject { |path| File.exist?(File.join(@root, path)) }
      app = read_file("lib/soul_core/app.rb")

      missing_routes = LOOP_STAGES.reject { |stage| route_present?(app, stage.fetch("command")) }

      blockers = []
      blockers << "Missing source file(s): #{missing_sources.join(', ')}" unless missing_sources.empty?
      blockers << "Missing documentation file(s): #{missing_docs.join(', ')}" unless missing_docs.empty?
      blockers << "Missing route(s): #{missing_routes.map { |stage| stage['id'] }.join(', ')}" unless missing_routes.empty?

      {
        "ok" => blockers.empty?,
        "assessment" => "skill_loop_completion",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "read_only" => true,
        "status" => blockers.empty? ? "controlled_skill_loop_complete" : "blocked",
        "stop_point" => {
          "name" => "Controlled Advisory Skill Loop",
          "complete" => blockers.empty?,
          "meaning" => "Soul can assess, propose, generate alpha artifacts, review, gate, prepare Codex handoffs, dry-run review output, generate implementation task packs, and review those packs without autonomous production promotion.",
          "not_in_scope" => [
            "automatic production skill promotion",
            "automatic Codex invocation",
            "automatic patch application",
            "provider activation",
            "runtime configuration mutation",
            "background services"
          ]
        },
        "loop_stages" => LOOP_STAGES,
        "required_source_files" => REQUIRED_SOURCE_FILES,
        "required_docs" => REQUIRED_DOCS,
        "missing_source_files" => missing_sources,
        "missing_docs" => missing_docs,
        "missing_routes" => missing_routes.map { |stage| stage["id"] },
        "next_optional_tracks" => [
          {
            "id" => "codex_dry_run_fixture_pack",
            "summary" => "Add safe example handoff/response fixtures for testing Codex review behavior."
          },
          {
            "id" => "first_bounded_codex_task",
            "summary" => "Use Codex with gpt-5.5 medium on one contract-bound task, then review output locally."
          },
          {
            "id" => "speech_to_text_assessment",
            "summary" => "Begin local-only STT readiness assessment with no recording."
          },
          {
            "id" => "screen_understanding_assessment",
            "summary" => "Begin explicit, user-triggered screenshot/vision readiness assessment."
          }
        ],
        "blockers" => blockers,
        "verification" => {
          "read_only" => true,
          "no_files_modified" => true,
          "no_codex_invoked" => true,
          "no_patches_applied" => true,
          "no_promotion_performed" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Skill Loop Completion Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << "Stop point: #{report.dig('stop_point', 'name')}"
      lines << "Complete: #{report.dig('stop_point', 'complete')}"
      lines << ""
      lines << "Meaning"
      lines << report.dig("stop_point", "meaning")
      lines << ""
      lines << "Loop stages"
      report.fetch("loop_stages").each do |stage|
        lines << "- Phase #{stage['phase']}: #{stage['id']}"
        lines << "  #{stage['command']}"
        lines << "  #{stage['purpose']}"
      end
      lines << ""
      lines << "Not in scope"
      report.dig("stop_point", "not_in_scope").each { |item| lines << "- #{item}" }
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

    def read_file(path)
      full = File.join(@root, path)
      File.exist?(full) ? File.read(full) : ""
    end

    def route_present?(app, command)
      tokens = command.split
      return app.include?("environment") if command.include?("assess environment")
      return app.include?('"models", "model-runtime"') if command.include?("assess models")
      return app.include?('"capabilities", "capability-matrix"') if command.include?("assess capabilities")
      return app.include?('"proposals"') if command.include?("improve proposals")
      return app.include?('"alpha"') if command.include?("improve alpha --latest")
      return app.include?('"alpha-review", "review-alpha"') if command.include?("alpha-review")
      return app.include?('"promotion-gate", "alpha-promotion-gate", "promotion-check"') if command.include?("promotion-gate")
      return app.include?('"feature-direction", "features", "next-feature"') if command.include?("feature-direction")
      return app.include?('"model-suitability", "models-suitability", "suitability"') if command.include?("model-suitability")
      return app.include?('"model-policy", "model-suitability-policy", "suitability-policy"') if command.include?("model-policy")
      return app.include?('"codex-handoff", "handoff-contract", "codex-contract"') if command.include?("codex-handoff")
      return app.include?('"codex-dry-run-review", "codex-review", "handoff-review"') if command.include?("codex-dry-run-review")
      return app.include?('"implementation-pack", "task-pack", "alpha-task-pack"') if command.include?("implementation-pack")
      return app.include?('"implementation-review", "implementation-gate", "review-implementation"') if command.include?("implementation-review")

      tokens.any? { |token| app.include?(token) }
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
