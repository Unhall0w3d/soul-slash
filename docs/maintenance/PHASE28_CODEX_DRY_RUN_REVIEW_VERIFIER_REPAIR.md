
# Phase 28 Verifier Repair

This repair updates the Phase 28 Codex dry-run review verifier.

## Issue

The Phase 28 implementation correctly returned a blocked review report for a bad Codex response artifact.

The verifier incorrectly expected the CLI process exit status to indicate the blocked state. In this repository, blocked/review reports may still be returned as normal command output, so the verifier should validate report content rather than process status.

The bad response correctly produced:

```text
ok: false
readiness: blocked
forbidden_hits: .env
missing sections including rollback
```

## Fix

The verifier now treats the JSON report body as the source of truth for blocked dry-run review output.

It still validates:

```text
passing response is review_ready
bad response is blocked
forbidden file detection works
missing section detection works
alias output works
repo curation remains clean apart from the current phase verifier
```

## Scope

This repair changes only:

```text
scripts/verify-codex-dry-run-review-phase28.rb
docs/maintenance/PHASE28_CODEX_DRY_RUN_REVIEW_VERIFIER_REPAIR.md
```
