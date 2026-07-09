
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require "pathname"

module SoulCore
  class FirstBoundedCodexTask
    TASK_ROOT = File.join("Soul", "codex", "tasks", "phase33_first_bounded_task").freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def generate
      generated_at = Time.now.iso8601
      task_root = File.join(@root, TASK_ROOT)
      FileUtils.mkdir_p(task_root)

      contract = build_contract(generated_at)
      expected_response = expected_response_schema
      prompt = render_prompt(contract, expected_response, generated_at)

      files = {
        "contract.json" => JSON.pretty_generate(contract),
        "codex_prompt.md" => prompt,
        "expected_response_schema.json" => JSON.pretty_generate(expected_response),
        "local_review_instructions.md" => local_review_instructions(generated_at),
        "README.md" => readme(generated_at)
      }

      written = files.map do |filename, content|
        path = File.join(task_root, filename)
        File.write(path, content)
        relative_path(path)
      end

      {
        "ok" => true,
        "assessment" => "first_bounded_codex_task",
        "generated_at" => generated_at,
        "root" => @root,
        "task_root" => TASK_ROOT,
        "recommended_model" => "gpt-5.5 medium",
        "written_files" => written,
        "next_manual_step" => "Paste codex_prompt.md into Codex using gpt-5.5 medium, save the response JSON locally, then run codex-dry-run-review.",
        "review_command_template" => "ruby bin/soul assess codex-dry-run-review --contract #{File.join(TASK_ROOT, 'contract.json')} --response <response.json> --json",
        "verification" => {
          "task_package_only" => true,
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
      lines << "Soul First Bounded Codex Task Package"
      lines << "Generated: #{report['generated_at']}"
      lines << "Task root: #{report['task_root']}"
      lines << "Recommended model: #{report['recommended_model']}"
      lines << ""
      lines << "Written files"
      report.fetch("written_files").each { |path| lines << "- #{path}" }
      lines << ""
      lines << "Next manual step"
      lines << report.fetch("next_manual_step")
      lines << ""
      lines << "Review command template"
      lines << report.fetch("review_command_template")
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def build_contract(generated_at)
      {
        "task" => {
          "id" => "phase33_fixture_doc_review",
          "title" => "Phase 33 Fixture Documentation Review",
          "summary" => "Review the Codex dry-run fixture documentation and propose a bounded documentation-only improvement with concrete proposed wording.",
          "model_recommendation" => "gpt-5.5 medium",
          "status" => "first_bounded_codex_task_package",
          "generated_at" => generated_at
        },
        "repo_context" => {
          "project" => "Soul",
          "language" => "Ruby",
          "scope" => "local-first assistant with explicit review and promotion gates",
          "relevant_files_to_read" => [
            "docs/CODEX_DRY_RUN_FIXTURE_PACK.md",
            "docs/fixtures/codex_dry_run/README.md",
            "docs/CODEX_DRY_RUN_REVIEW.md"
          ],
          "context_summary" => [
            "The controlled advisory skill loop is complete.",
            "Codex must only receive bounded task packages.",
            "This first task is documentation-only.",
            "The output must be saved locally and reviewed with the dry-run review gate before any human considers applying it.",
            "The response must include concrete proposed documentation text, not just a summary."
          ]
        },
        "allowed_files" => [
          "docs/CODEX_DRY_RUN_FIXTURE_PACK.md",
          "docs/fixtures/codex_dry_run/README.md",
          "docs/CODEX_DRY_RUN_REVIEW.md",
          "docs/fixtures/codex_dry_run/<FEATURE_DOC>.md",
          "docs/maintenance/<PHASE_DOC>.md"
        ],
        "forbidden_files" => [
          ".env",
          ".env.*",
          "Soul/runtime/*",
          "Soul/improvement/proposals/*",
          "Soul/artifacts/cloud_assist/*",
          "Soul/proposals/skills/*",
          "Soul/codex/*",
          "lib/soul_core/*",
          "bin/*",
          "scripts/*",
          "models/*",
          "config/secrets/*"
        ],
        "acceptance_criteria" => [
          "Response must be documentation-only.",
          "Response must not modify Ruby source, scripts, runtime state, secrets, generated proposal-local files, or Codex task package files.",
          "Response must include the required dry-run response sections.",
          "Response must include proposed_documentation_change with exact proposed wording or a precise replacement section.",
          "Response must list only allowed documentation file paths in files_changed.",
          "files_changed means files the proposal would change if later applied by a human; it does not mean Codex has changed those files.",
          "Response must include concrete verification commands.",
          "Response must include risks and rollback notes.",
          "Response must clearly state that no patches should be applied automatically."
        ],
        "verifier_expectations" => [
          "Dry-run review should pass for a compliant response.",
          "Dry-run review should block if source, scripts, secrets, runtime, or Soul/codex task files are listed as changed.",
          "Dry-run review should block if required response fields are missing.",
          "No network access is required for local review.",
          "No Codex invocation occurs from Soul."
        ],
        "security_boundaries" => [
          "Do not include secrets.",
          "Do not include private files.",
          "Do not ask Codex to inspect the whole repo.",
          "Do not allow source or script edits for this first task.",
          "Do not apply any output automatically.",
          "Do not promote generated work."
        ],
        "output_format" => {
          "preferred" => "json",
          "required_sections" => [
            "summary",
            "files_changed",
            "proposed_documentation_change",
            "commands_to_verify",
            "risks",
            "rollback",
            "human_review_notes"
          ],
          "no_direct_commit" => true,
          "field_notes" => {
            "files_changed" => "Files the proposal would change if later applied by a human. Codex must not edit or apply patches.",
            "proposed_documentation_change" => "Exact proposed wording, replacement section, or clearly scoped documentation delta for human review."
          }
        },
        "rollback_notes" => [
          "Do not apply Codex output automatically.",
          "If the output is used later, revert only the explicitly changed documentation files.",
          "Delete local response artifacts under Soul/codex when finished."
        ]
      }
    end

    def expected_response_schema
      {
        "summary" => "String. Briefly summarize the proposed documentation-only improvement.",
        "files_changed" => [
          "Array of allowed documentation file paths the proposal would change if later applied by a human. Codex must not edit files."
        ],
        "proposed_documentation_change" => {
          "target_file" => "One allowed documentation path.",
          "change_type" => "add_section | replace_section | revise_paragraph",
          "proposed_text" => "Exact proposed wording for the human to inspect.",
          "placement_notes" => "Where the proposed text should go."
        },
        "commands_to_verify" => [
          "ruby bin/soul assess codex-dry-run-review --contract Soul/codex/tasks/phase33_first_bounded_task/contract.json --response <response.json> --json"
        ],
        "risks" => [
          "Array of risk notes."
        ],
        "rollback" => "String. Explain how to revert the documentation-only proposal.",
        "human_review_notes" => "String. Explain what a human should inspect before applying anything."
      }
    end

    def render_prompt(contract, expected_response, generated_at)
      <<~PROMPT
        # Codex Task: Phase 33 Fixture Documentation Review

        Generated: #{generated_at}

        Use model: **gpt-5.5 medium**.

        You are being given a bounded documentation-only task for the Soul repository.

        ## Hard boundaries

        Do not edit code.
        Do not edit scripts.
        Do not edit runtime files.
        Do not edit secrets.
        Do not edit files under `Soul/codex/`.
        Do not propose provider activation.
        Do not propose dependency installation.
        Do not apply patches.
        Do not commit anything.

        ## Important wording

        In your JSON response, `files_changed` means:

        ```text
        files this proposal would change if a human later applied it
        ```

        It does not mean you changed files. You must not change files.

        ## Task

        Review these files only:

        ```text
        docs/CODEX_DRY_RUN_FIXTURE_PACK.md
        docs/fixtures/codex_dry_run/README.md
        docs/CODEX_DRY_RUN_REVIEW.md
        ```

        Propose a documentation-only improvement that clarifies how the dry-run fixture pack should be used before a real Codex task.

        Your response must include concrete proposed documentation text in `proposed_documentation_change`. A structural response with only a summary is not sufficient.

        ## Contract

        ```json
        #{JSON.pretty_generate(contract)}
        ```

        ## Required response format

        Return only JSON matching this shape:

        ```json
        #{JSON.pretty_generate(expected_response)}
        ```

        ## Important

        `files_changed` must list only paths allowed by the contract.

        `proposed_documentation_change.proposed_text` must contain exact wording or a precise replacement section that a human can inspect.

        This is a proposal only. The output will be reviewed locally by Soul's dry-run review gate before any human applies anything.
      PROMPT
    end

    def local_review_instructions(generated_at)
      <<~MD
        # Local Review Instructions

        Generated: #{generated_at}

        ## Step 1: Use Codex manually

        Open Codex and use:

        ```text
        gpt-5.5 medium
        ```

        Paste the contents of:

        ```text
        #{File.join(TASK_ROOT, "codex_prompt.md")}
        ```

        ## Step 2: Save Codex output

        Save the returned JSON as a local file, for example:

        ```text
        Soul/codex/tasks/phase33_first_bounded_task/codex_response.json
        ```

        ## Step 3: Review locally

        Run:

        ```bash
        ruby bin/soul assess codex-dry-run-review --contract #{File.join(TASK_ROOT, "contract.json")} --response Soul/codex/tasks/phase33_first_bounded_task/codex_response.json --json
        ```

        ## Step 4: Inspect usefulness

        A passing dry-run review means the response stayed inside the contract.

        It does not mean the proposal is correct, useful, or approved for application.

        Specifically inspect:

        ```text
        proposed_documentation_change.target_file
        proposed_documentation_change.change_type
        proposed_documentation_change.proposed_text
        proposed_documentation_change.placement_notes
        ```

        If `proposed_text` is vague, missing, or not directly usable, reject the response and revise the prompt.
      MD
    end

    def readme(generated_at)
      <<~MD
        # Phase 33 First Bounded Codex Task

        Generated: #{generated_at}

        This package prepares the first real bounded Codex task.

        It does not invoke Codex. It does not apply patches. It does not change production files.

        ## Files

        ```text
        contract.json
        codex_prompt.md
        expected_response_schema.json
        local_review_instructions.md
        README.md
        ```

        ## Intended flow

        ```text
        1. Paste codex_prompt.md into Codex using gpt-5.5 medium.
        2. Save the returned JSON locally.
        3. Run codex-dry-run-review against contract.json and the saved response.
        4. Inspect proposed_documentation_change for concrete proposed wording.
        5. Apply nothing automatically.
        ```

        ## Cleanup

        This package is generated local task material. Delete it when finished if you do not need to retain the task artifacts.
      MD
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end
  end
end
