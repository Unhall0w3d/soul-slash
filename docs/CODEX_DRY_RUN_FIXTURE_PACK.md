
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
