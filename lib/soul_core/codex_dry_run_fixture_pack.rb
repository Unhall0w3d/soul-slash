
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require "pathname"

module SoulCore
  class CodexDryRunFixturePack
    FIXTURE_ROOT = File.join("docs", "fixtures", "codex_dry_run").freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def generate
      generated_at = Time.now.iso8601
      fixture_root = File.join(@root, FIXTURE_ROOT)
      FileUtils.mkdir_p(fixture_root)

      files = {
        "safe_contract.json" => safe_contract(generated_at),
        "safe_response.json" => safe_response(generated_at),
        "blocked_response_forbidden_file.json" => blocked_response_forbidden_file(generated_at),
        "blocked_response_missing_sections.json" => blocked_response_missing_sections(generated_at),
        "README.md" => readme(generated_at)
      }

      written = files.map do |filename, content|
        path = File.join(fixture_root, filename)
        File.write(path, filename.end_with?(".json") ? JSON.pretty_generate(content) : content)
        relative_path(path)
      end

      {
        "ok" => true,
        "assessment" => "codex_dry_run_fixture_pack",
        "generated_at" => generated_at,
        "root" => @root,
        "fixture_root" => FIXTURE_ROOT,
        "written_files" => written,
        "fixtures" => {
          "safe_contract" => File.join(FIXTURE_ROOT, "safe_contract.json"),
          "safe_response" => File.join(FIXTURE_ROOT, "safe_response.json"),
          "blocked_response_forbidden_file" => File.join(FIXTURE_ROOT, "blocked_response_forbidden_file.json"),
          "blocked_response_missing_sections" => File.join(FIXTURE_ROOT, "blocked_response_missing_sections.json")
        },
        "verification" => {
          "fixture_only" => true,
          "no_codex_invoked" => true,
          "no_patches_applied" => true,
          "no_production_files_modified" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Codex Dry-Run Fixture Pack"
      lines << "Generated: #{report['generated_at']}"
      lines << "Fixture root: #{report['fixture_root']}"
      lines << ""
      lines << "Written files"
      report.fetch("written_files").each { |path| lines << "- #{path}" }
      lines << ""
      lines << "Fixtures"
      report.fetch("fixtures").each { |name, path| lines << "- #{name}: #{path}" }
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def safe_contract(generated_at)
      {
        "task" => {
          "id" => "fixture_bounded_documentation_update",
          "title" => "Fixture Bounded Documentation Update",
          "summary" => "Produce a bounded documentation-only update for dry-run review fixture testing.",
          "model_recommendation" => "gpt-5.5 medium",
          "status" => "fixture_contract_only",
          "generated_at" => generated_at
        },
        "repo_context" => {
          "project" => "Soul",
          "language" => "Ruby",
          "scope" => "fixture-only Codex dry-run review validation",
          "current_boundaries" => [
            "This fixture must not be used as a production implementation task.",
            "This fixture must not include private repo context.",
            "This fixture must not invoke Codex.",
            "This fixture must not apply patches."
          ]
        },
        "allowed_files" => [
          "docs/fixtures/codex_dry_run/<FEATURE_DOC>.md",
          "docs/maintenance/<PHASE_DOC>.md",
          "scripts/verify-<feature>.rb"
        ],
        "forbidden_files" => [
          ".env",
          ".env.*",
          "Soul/runtime/*",
          "Soul/improvement/proposals/*",
          "Soul/artifacts/cloud_assist/*",
          "Soul/proposals/skills/*",
          "lib/soul_core/*",
          "bin/*",
          "models/*",
          "config/secrets/*"
        ],
        "acceptance_criteria" => [
          "Response remains fixture-only.",
          "Response changes only allowed fixture or documentation paths.",
          "Response includes verification commands.",
          "Response includes risks and rollback notes.",
          "Response does not touch source, runtime, secrets, or proposal-local artifacts."
        ],
        "verifier_expectations" => [
          "Dry-run review of safe_response.json should pass.",
          "Dry-run review of blocked_response_forbidden_file.json should block.",
          "Dry-run review of blocked_response_missing_sections.json should block.",
          "No network access is required.",
          "No patches are applied."
        ],
        "security_boundaries" => [
          "Do not read secrets.",
          "Do not include private file contents.",
          "Do not invoke Codex.",
          "Do not apply patches.",
          "Do not change runtime configuration."
        ],
        "output_format" => {
          "preferred" => "fixture_response",
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
          "Delete fixture files if abandoning the fixture pack.",
          "Do not revert unrelated production files.",
          "No runtime state should be created."
        ]
      }
    end

    def safe_response(generated_at)
      {
        "summary" => "Fixture response that proposes a bounded documentation-only update.",
        "generated_at" => generated_at,
        "files_changed" => [
          "docs/fixtures/codex_dry_run/SAFE_FIXTURE_RESULT.md",
          "docs/maintenance/PHASE32_CODEX_DRY_RUN_FIXTURE_PACK.md",
          "scripts/verify-codex-dry-run-fixture-pack-phase32.rb"
        ],
        "commands_to_verify" => [
          "ruby scripts/verify-codex-dry-run-fixture-pack-phase32.rb",
          "ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/safe_response.json --json"
        ],
        "risks" => [
          "Fixture files could be mistaken for real Codex output.",
          "Allowed file patterns must remain narrow."
        ],
        "rollback" => "Remove docs/fixtures/codex_dry_run fixture files and the phase 32 verifier/doc if abandoning this fixture pack.",
        "human_review_notes" => "Confirm this is fixture-only and contains no private context, secrets, provider activation, or production implementation changes."
      }
    end

    def blocked_response_forbidden_file(generated_at)
      {
        "summary" => "Fixture response that intentionally touches a forbidden file.",
        "generated_at" => generated_at,
        "files_changed" => [
          ".env",
          "docs/fixtures/codex_dry_run/SAFE_FIXTURE_RESULT.md"
        ],
        "commands_to_verify" => [
          "ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json --json"
        ],
        "risks" => [
          "This fixture intentionally violates forbidden file policy."
        ],
        "rollback" => "Do not apply this response. It is intentionally blocked.",
        "human_review_notes" => "Expected result: blocked because .env is forbidden."
      }
    end

    def blocked_response_missing_sections(generated_at)
      {
        "summary" => "Fixture response that intentionally omits required sections.",
        "generated_at" => generated_at,
        "files_changed" => [
          "docs/fixtures/codex_dry_run/SAFE_FIXTURE_RESULT.md"
        ]
      }
    end

    def readme(generated_at)
      <<~MD
        # Codex Dry-Run Fixtures

        Generated: #{generated_at}

        These fixtures test the Codex dry-run review path without invoking Codex or applying patches.

        ## Fixtures

        ```text
        safe_contract.json
        safe_response.json
        blocked_response_forbidden_file.json
        blocked_response_missing_sections.json
        ```

        ## Expected behavior

        ```text
        safe_response.json: review_ready
        blocked_response_forbidden_file.json: blocked
        blocked_response_missing_sections.json: blocked
        ```

        ## Commands

        ```bash
        ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/safe_response.json --json
        ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json --json
        ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/blocked_response_missing_sections.json --json
        ```

        ## Boundaries

        These fixtures are not real Codex output and must not be applied as patches.
      MD
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end
  end
end
