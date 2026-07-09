
# Alpha Implementation Task Pack

The alpha implementation task pack turns a proposal-local alpha artifact into a bounded implementation package.

It does not invoke Codex. It does not apply patches. It does not write production implementation. It only writes task-pack files inside the proposal's `alpha/` folder.

## Commands

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

## Generated files

```text
implementation_task_pack.json
implementation_task_pack.md
codex_handoff_contract.json
human_review_checklist.md
rollback_plan.md
```

These are written under:

```text
Soul/improvement/proposals/<proposal>/alpha/
```

## Boundaries

The implementation task pack must not:

```text
invoke Codex
apply patches
write production implementation
promote alpha artifacts
alter runtime configuration
read secrets
```

## Purpose

The pack gives a future Codex or human implementation task a bounded shape:

```text
allowed files
forbidden files
acceptance criteria
verifier expectations
security boundaries
human review checklist
rollback plan
```

## Next phase

Phase 30 should add an alpha implementation review gate.
