# Codex Dry-Run Fixtures

Generated: 2026-07-09T16:33:30-04:00

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
