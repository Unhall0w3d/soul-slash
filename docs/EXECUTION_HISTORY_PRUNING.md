
# Execution History Pruning

Phase 53 adds execution history pruning.

## Purpose

Soul can record, list, export, clear, and filter local execution history.

This phase adds safe pruning by count.

## Chat examples

```bash
ruby bin/soul chat "prune execution history keep 25"
ruby bin/soul chat "prune execution history keep 25 confirm"
ruby bin/soul chat "prune execution history keep last 10"
```

## Safety posture

Prune without confirmation is preview-only.

Confirmed prune exports removed entries before deletion by default.

Exports remain local runtime data under:

```text
Soul/runtime/exports/execution_history/
```

Do not commit runtime history or exports.
