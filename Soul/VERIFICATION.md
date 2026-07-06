# Soul/ Verification Doctrine

Soul/ must optimize for verified outcomes, not task-shaped output.

## Required distinction

- Action completed: something ran.
- Goal satisfied: the requested outcome was achieved and verified.

These are not the same.

## Verification report shape

Each task should eventually produce:

```yaml
goal:
actions:
evidence:
verification:
warnings:
unverified:
reflection_candidates:
```

## File safety rules

- Planning must be read-only.
- Top-level files and folders in approved target directories may be cleanup candidates.
- Cleanup scans are top-level by default, not recursive.
- Movement must be previewed first.
- Trash is the terminal cleanup action for early Soul/ versions.
- Moving approved items to Trash is considered job complete.
- Trash emptying is left to the operating system or the user.
- Permanent deletion is not supported in early Soul/ versions.
- Protected project aliases must be checked before cleanup actions.
- Move-to-trash execution must consume a verified cleanup plan.
- Move-to-trash execution must require explicit confirmation.
