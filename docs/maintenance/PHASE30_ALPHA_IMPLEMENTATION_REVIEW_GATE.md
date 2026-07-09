
# Phase 30 Alpha Implementation Review Gate

Phase 30 adds a review-only gate for alpha implementation task packs.

## Purpose

Phase 29 generates proposal-local implementation task packs.

Phase 30 validates those packs before any Codex output or human implementation work is treated as useful.

## New commands

```bash
ruby bin/soul improve implementation-review --latest
ruby bin/soul improve implementation-review --latest --json
ruby bin/soul improve implementation-review --proposal-rank 1
ruby bin/soul improve implementation-review --proposal Soul/improvement/proposals/<proposal-folder>
```

Aliases:

```bash
ruby bin/soul improve implementation-gate --latest
ruby bin/soul improve review-implementation --latest
```

## Scope

Phase 30 does not:

```text
invoke Codex
apply Codex output
write production implementation
promote alpha artifacts
enable providers
read secrets
alter runtime configuration
```

## Next phase

Phase 31 should summarize the completed controlled skill loop.
