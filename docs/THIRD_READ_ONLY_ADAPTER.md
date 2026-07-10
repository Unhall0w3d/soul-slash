
# Third Read-Only Adapter

Phase 54 adds the third read-only adapter.

## Executable skills

```text
assistant-skill-catalog
system.status
execution.history.summary
```

## New trigger

```bash
ruby bin/soul chat "execution history summary"
```

Soul summarizes local execution history:

```text
total entries
shown entries
counts by status
counts by skill
latest entry
```

## Safety posture

This adapter reads local runtime metadata only.

Approval-required skills remain blocked.

Runtime history remains private and gitignored.
