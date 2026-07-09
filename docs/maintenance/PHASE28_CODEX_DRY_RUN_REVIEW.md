
# Phase 28 Codex Dry-Run Review

Phase 28 adds a review-only checker for Codex output artifacts.

## Purpose

After Phase 27, Soul can generate a bounded handoff contract.

Phase 28 lets Soul inspect a proposed Codex response against that contract before any human considers applying it.

## New command

```bash
ruby bin/soul assess codex-dry-run-review --contract <contract.json> --response <response.json>
ruby bin/soul assess codex-dry-run-review --contract <contract.json> --response <response.json> --json
```

Aliases:

```bash
ruby bin/soul assess codex-review --contract <contract.json> --response <response.json>
ruby bin/soul assess handoff-review --contract <contract.json> --response <response.json>
```

## Scope

Phase 28 does not:

```text
invoke Codex
apply patches
modify production files
read secrets
enable providers
change runtime configuration
promote alpha artifacts
```

## Result

A passing dry-run review means the proposed Codex output has the right sections and stays inside the handoff contract boundaries.

It does not mean the output is correct or approved for production.
