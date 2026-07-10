# Downloads Cleanup Preview

Phase 57 enables `downloads.cleanup_plan` as a non-mutating review-only adapter.

## Trigger

```bash
ruby bin/soul chat "clean up downloads"
```

## Preview rule

```text
files older than 30 days or larger than 100 MiB
```

## Reported metadata

```text
files scanned
candidate file count
candidate bytes
candidate extensions
candidate age buckets
candidate size buckets
```

## Safety posture

This phase does not move, delete, open, or modify files.

Filenames are omitted.

`downloads.move_to_trash` remains approval-required and blocked.
