
# Codex Dry-Run Fixture Pack

The Codex dry-run fixture pack provides safe, deterministic fixture files for testing the Codex dry-run review path.

It does not invoke Codex. It does not apply patches. It does not include private repo context. It does not write implementation output.

## Command

```bash
ruby bin/soul improve codex-fixtures
ruby bin/soul improve codex-fixtures --json
```

Aliases:

```bash
ruby bin/soul improve codex-fixture-pack
ruby bin/soul improve dry-run-fixtures
```

## Generated fixture files

```text
docs/fixtures/codex_dry_run/safe_contract.json
docs/fixtures/codex_dry_run/safe_response.json
docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json
docs/fixtures/codex_dry_run/blocked_response_missing_sections.json
docs/fixtures/codex_dry_run/README.md
```

## Expected dry-run review behavior

```text
safe_response.json: review_ready
blocked_response_forbidden_file.json: blocked
blocked_response_missing_sections.json: blocked
```

## Purpose

These fixtures give the repo a deterministic way to test the Codex review rails before spending Codex budget on a real bounded task.

## Before a real Codex task

Run the fixture pack checks before sending any real bounded task package to Codex.

Use the safe fixture first to confirm the dry-run review path can return `review_ready`:

```bash
ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/safe_response.json --json
```

Then run the blocked fixtures to confirm the review gate rejects unsafe or incomplete responses:

```bash
ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/blocked_response_forbidden_file.json --json
ruby bin/soul assess codex-dry-run-review --contract docs/fixtures/codex_dry_run/safe_contract.json --response docs/fixtures/codex_dry_run/blocked_response_missing_sections.json --json
```

Only proceed to a real Codex prompt after the safe fixture is `review_ready` and both blocked fixtures are `blocked`.

Do not apply Codex output automatically. Save the returned JSON locally and review it with `codex-dry-run-review` against the task contract first.

## Boundaries

Fixtures must not:

```text
invoke Codex
apply patches
include private context
touch production source
enable providers
read secrets
alter runtime configuration
```
