
# First Bounded Codex Task

The first bounded Codex task package prepares a real manual Codex prompt while keeping Soul local and review-only.

It does not invoke Codex. It does not send context to a provider. It does not apply patches. It does not modify production files.

## Command

```bash
ruby bin/soul improve bounded-codex-task
ruby bin/soul improve bounded-codex-task --json
```

Aliases:

```bash
ruby bin/soul improve first-codex-task
ruby bin/soul improve codex-task
```

## Generated task package

```text
Soul/codex/tasks/phase33_first_bounded_task/contract.json
Soul/codex/tasks/phase33_first_bounded_task/codex_prompt.md
Soul/codex/tasks/phase33_first_bounded_task/expected_response_schema.json
Soul/codex/tasks/phase33_first_bounded_task/local_review_instructions.md
Soul/codex/tasks/phase33_first_bounded_task/README.md
```

## Intended flow

```text
1. Generate the task package locally.
2. Paste codex_prompt.md into Codex using gpt-5.5 medium.
3. Save Codex's JSON response locally.
4. Run codex-dry-run-review against contract.json and the saved response.
5. Apply nothing automatically.
```

## First task scope

The first bounded task is documentation-only.

Codex may propose edits only under allowed documentation paths defined in the contract.

Codex must not propose edits to:

```text
Ruby source
scripts
runtime state
secrets
provider configuration
Soul/codex task package files
proposal-local generated artifacts
```

## Cleanup

Generated task package files live under `Soul/codex/tasks/` and should remain local unless deliberately retained.
