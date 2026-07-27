# Backup Retention A1 Brief

Status: candidate-complete; human review required

## Objective

Preserve at least one recoverable restic snapshot containing every deleted
source path for 30 full days after the deletion is first detected by a
successful, verified snapshot.

This slice implements the deletion-hold ledger and a deterministic retention
preview. It does not run, wrap, approve, or expose `restic forget` or
`restic prune`.

## Approved policy

- Detection occurs only when a newer snapshot has completed verification and
  is explicitly recorded in the ledger.
- The first recorded snapshot establishes a baseline and cannot report
  deletions.
- A path present in the previous verified snapshot and absent from the next
  verified snapshot receives one hold.
- The hold protects the immediately preceding snapshot for exactly 30 full
  24-hour periods from the newer snapshot's verified timestamp.
- Later snapshots in which the path remains absent do not restart the clock.
- A verified reappearance resolves the hold. A later deletion starts a new
  hold against the newer prior snapshot.
- A missing ledger, corrupt ledger, changed source-root set, failed snapshot
  verification, non-monotonic snapshot time, stale digest, or malformed path
  blocks the operation.
- A hold-clear snapshot is not automatically eligible under a complete
  retention policy and is never authorization to delete it.

## Bounded implementation

`SoulCore::BackupRetentionLedger` accepts at most:

- 64 source roots;
- 100,000 normalized absolute snapshot paths;
- 100,000 deletion holds;
- a 32 MiB owner-private ledger;
- 10,000 candidate snapshot IDs in one retention preview.

Snapshot and repository identifiers must be full 64-character SHA-256
identifiers. Paths must be sorted, unique, absolute, normalized, and contained
by the unchanged verified source roots. The exact repository identity must not
change, and every source root must itself appear in the snapshot inventory.

The owner-private ledger is atomically replaced with mode `0600` and directory
metadata is synchronized. Observation requires a read-only preview, the exact
phrase `RECORD_VERIFIED_BACKUP_SNAPSHOT`, and the digest emitted by that
preview. Exact replay is idempotent.

Retention preview reports:

- active and expired deletion holds;
- candidate snapshots protected by an active hold;
- candidate snapshots that are hold-clear;
- an exact preview digest;
- `execution_available: false`.

Path names remain in the encrypted backup set's private operational ledger.
Review previews expose path digests rather than path names.

## Snapshot manifest contract

A manifest has schema `soul.backup_snapshot_manifest.v1` and records:

```json
{
  "schema_version": "soul.backup_snapshot_manifest.v1",
  "snapshot_id": "<full restic snapshot SHA-256>",
  "verified_at": "2026-07-27T12:00:00Z",
  "repository_id": "<restic repository SHA-256 identifier>",
  "source_roots": [
    "/home/USER/Projects/soul/Soul"
  ],
  "paths": [
    "/home/USER/Projects/soul/Soul/private/project_tracker/state.json"
  ],
  "verification": {
    "check_mode": "metadata",
    "result": "passed"
  }
}
```

The manifest must be created from the exact successfully captured snapshot,
not from a fresh scan of the live source after backup. A future productized
backup transaction should emit it directly from restic's machine-readable
snapshot inventory after `restic check` succeeds.

## Lifecycle

- preview success: `complete`, mutation `none`;
- missing or malformed input: `awaiting_input`;
- corrupt/stale operational state: `blocked_for_human_review`;
- approved ledger observation: `complete`;
- exact replay: `complete`, mutation `none`.

No process remains alive after any operation returns.

## Not included

- live `forget` or `prune`;
- automatic snapshot selection;
- scheduled backup or retention;
- a daemon, watcher, timer, or background loop;
- an off-site copy;
- live-tree restore;
- automatic creation of manifests from restic output.

Those remain separate human gates.
