
# Second Read-Only Execution Adapter

Phase 49 enables the second read-only execution adapter.

## Executable skills

```text
assistant-skill-catalog
system.status
```

## New trigger

```bash
ruby bin/soul chat "check repo health"
```

Soul executes:

```bash
ruby bin/soul assess doctor-surface --json
```

and summarizes the result.

## Safety posture

Approval-required skills remain blocked.

Read-only skills without adapters remain blocked with:

```text
adapter_not_implemented
```

## Why this matters

Soul now has more than one real read-only execution path from chat.

That means the gate is no longer a one-off demo. It is becoming an actual pattern.
