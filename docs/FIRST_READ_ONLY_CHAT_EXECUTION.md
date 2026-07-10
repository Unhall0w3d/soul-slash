
# First Read-Only Chat Execution

Phase 48 enables the first actual read-only chat execution path.

## Executable skill

```text
assistant-skill-catalog
```

## Trigger

```bash
ruby bin/soul chat "what skills do you have?"
```

Soul executes:

```bash
ruby bin/soul assess assistant-skill-catalog --json
```

and summarizes the result.

## Safety posture

Only the first read-only skill path is executable.

Approval-required skills remain blocked.

Most read-only skills still return:

```text
adapter_not_implemented
```

## Why this matters

Soul can now safely move from:

```text
I know which skill this maps to.
```

to:

```text
I ran one read-only skill through the gate and summarized the result.
```

Tiny step. Real wiring.
