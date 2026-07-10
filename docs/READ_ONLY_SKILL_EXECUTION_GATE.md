
# Read-Only Skill Execution Gate

Phase 47 introduces a read-only skill execution gate.

## Purpose

The chat layer can now route intents and create invocation plans.

This phase adds a read-only execution gate that determines whether a skill is:

```text
read-only
allowlisted
adapter-backed
blocked by confirmation
blocked because execution is not enabled yet
```

## Commands

```bash
ruby bin/soul assess read-only-skill-gate
ruby bin/soul assess read-only-skill-gate --json
```

Aliases:

```bash
ruby bin/soul assess read-only-execution
ruby bin/soul assess skill-execution-gate
```

## Safety posture

Phase 47 does not execute skills by default.

Every assessment sample must report:

```text
executed: false
```

Approval-required skills remain blocked.

## Future use

A later phase can choose one read-only adapter and allow actual execution through the gate.
