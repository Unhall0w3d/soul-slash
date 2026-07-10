# Downloads Inspect Adapter

Phase 56 enables `downloads.inspect` as a safe read-only adapter.

## Trigger

```bash
ruby bin/soul chat "inspect my downloads"
```

## Reported metadata

```text
entry count
file count
directory count
hidden entry count
total file bytes
largest file bytes
extension counts
```

## Privacy posture

Filenames are omitted.

No files are moved, opened, deleted, or modified.

`downloads.move_to_trash` remains approval-required and blocked.
