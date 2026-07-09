
# Alpha Implementation Review Gate

The alpha implementation review gate validates proposal-local implementation task packs.

It does not invoke Codex. It does not apply patches. It does not promote alpha artifacts. It does not write production implementation.

## Commands

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

## Required task-pack files

```text
implementation_task_pack.json
implementation_task_pack.md
codex_handoff_contract.json
human_review_checklist.md
rollback_plan.md
```

These files must live under:

```text
Soul/improvement/proposals/<proposal>/alpha/
```

## Review checks

```text
required files exist
task pack JSON is valid
Codex handoff contract JSON is valid
required task pack keys exist
required handoff contract keys exist
human review checklist exists
rollback plan exists
Codex invocation remains blocked
production implementation writes remain blocked
promotion remains blocked
```

## Result states

```text
review_ready
review_ready_with_warnings
blocked
```

A passing review does not approve implementation for production. It only says the implementation task pack is structurally ready for human review or a bounded Codex handoff.
