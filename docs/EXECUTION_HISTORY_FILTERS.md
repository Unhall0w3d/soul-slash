
# Execution History Filters

Phase 52 adds execution history filters.

## Purpose

Soul can list and export local chat execution history.

This phase adds filters for:

```text
skill_id
status
executed
```

## Chat examples

```bash
ruby bin/soul chat "execution history skill system.status"
ruby bin/soul chat "execution history blocked"
ruby bin/soul chat "execution history executed only"
ruby bin/soul chat "export execution history blocked"
ruby bin/soul chat "export execution history skill system.status jsonl"
```

## Safety posture

Filters only read local runtime history.

Exports remain local runtime data under:

```text
Soul/runtime/exports/execution_history/
```

Do not commit runtime history or exports.
