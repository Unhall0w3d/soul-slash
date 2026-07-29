# Backup Retention Additive Roots A0 Review

## Skill

Name: Backup Retention Additive Roots A0

Risk class: owner-private retention-ledger write; exact review-gated

Branch/checkpoint: `codex/backup-retention-additive-roots-a0`

Date: 2026-07-29

## Candidate status

`candidate_complete`

## Implementation summary

The deletion-aware retention ledger may now advance across a reviewed backup
scope expansion only when the newly verified source-root set contains every
root recorded by the immediately preceding verified snapshot.

The observation preview and exact approval digest include the number and
SHA-256 digests of added roots. Exact execution records the same evidence,
advances the verified snapshot, and preserves existing deletion holds and their
original clocks. Removing a prior root—or swapping one prior root for a new
one—still fails closed before mutation.

This repairs the live post-reconciliation transaction boundary without
introducing a recovery bypass. The already verified snapshot and accepted
Crucible replica remain safe; after merge, one fresh normal Dashboard backup
will finalize the local ledger and transaction receipt through the ordinary
flow.

## Files changed

```text
- lib/soul_core/backup_retention_ledger.rb
- scripts/verify-backup-retention-ledger-a1.rb
- config/project_tracker_seed.json
- docs/soul/BACKUP_RETENTION_ADDITIVE_ROOTS_A0_BRIEF.md
- docs/soul/BACKUP_AND_RECOVERY.md
- docs/CURRENT_STATE.md
- docs/ROADMAP.md
- this review artifact
```

## Commands run

```text
ruby -c lib/soul_core/backup_retention_ledger.rb
ruby -c scripts/verify-backup-retention-ledger-a1.rb
ruby scripts/verify-backup-retention-ledger-a1.rb
make verify-backup-administration
make verify-backup-manifest-reconciliation
make verify-storage-retention-census
make verify-project-timeline
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
git diff --check
```

## Deterministic test results

The retention fixture passes:

- strict additive source-root preview and exact execution;
- addition count and path-digest approval binding;
- preservation of an existing deletion hold across expansion;
- normal 30-day protection for a later deletion inside an added root;
- fail-closed root removal and replacement with no ledger mutation;
- exact replay idempotence and altered replay rejection;
- 30-day hold creation, continuity, expiry, and reappearance behavior;
- repository, verification, time, path-containment, and corrupt-ledger checks;
- proof that no Restic forget/prune execution exists.

Backup Administration, Backup Manifest Reconciliation, and Storage & Retention
Census regressions pass. The tracked Project Timeline seed parses as JSON.

No local LLM evaluation applies; this is a deterministic retention transaction.

## Memory keys

Reads: none.

Writes/updates: none.

Forget behavior: not applicable.

## Task lifecycle states touched

```text
- complete
- awaiting_input
- blocked_for_human_review
- failed
```

Every operation terminates before returning.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Repository identity change allowed: no
Prior source-root removal allowed: no
Prior source-root replacement allowed: no
Restic forget or prune added: no
Existing deletion clock reset: no
```

The 3:00 AM nightly DRS item added to Later is planning metadata only and grants
no timer, credential, or unattended execution authority.

## Known weaknesses

- The interrupted live transaction has a verified manifest and Crucible copy
  but no matching finalized local retention-ledger observation or backup
  receipt.
- The repair intentionally does not synthesize missing receipts from historical
  evidence. One fresh normal backup is required after merge.
- A future intentional root removal requires a separately reviewed migration;
  this slice correctly continues to reject it.
- Cleanup execution and nightly unattended backup remain separate future work.

## Human review checklist

```text
[ ] Additive expansion discloses only expected root digests and counts
[ ] Every previously recorded source root remains present
[ ] Existing deletion holds and original timestamps remain unchanged
[ ] Root removal and replacement still fail closed
[ ] No Restic prune/forget or unattended behavior was added
[ ] Current verified snapshot and Crucible replica remain available
[ ] After merge, one fresh Dashboard backup finalizes ledger and receipt
[ ] The resulting census remains 32/32 with zero gaps
[ ] Merge readiness is approved independently from tests
```

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
