
# Phase 29 Alpha Implementation Task Pack

Phase 29 adds proposal-local implementation task packs.

## Purpose

The project now has:

```text
feature direction
model suitability
model policy
Codex handoff contract
Codex dry-run review
```

Phase 29 connects those pieces to the alpha pipeline by generating task packs under a proposal's `alpha/` folder.

## New commands

```bash
ruby bin/soul improve implementation-pack --latest
ruby bin/soul improve implementation-pack --latest --json
ruby bin/soul improve implementation-pack --proposal-rank 1
ruby bin/soul improve implementation-pack --proposal Soul/improvement/proposals/<proposal-folder>
```

Aliases:

```bash
ruby bin/soul improve task-pack --latest
ruby bin/soul improve alpha-task-pack --latest
```

## Scope

Phase 29 does not:

```text
invoke Codex
apply Codex output
write production implementation
promote alpha artifacts
enable providers
read secrets
alter runtime configuration
```

## Result

A task pack is a bounded work order that can later be handed to Codex or reviewed by a human.

It is not production code.
