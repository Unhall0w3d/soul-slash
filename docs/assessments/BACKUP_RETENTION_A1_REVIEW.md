# Backup Retention A1 Review

Status: candidate-complete; human review required

## Implementation summary

- added a bounded owner-private ledger for verified snapshot inventories;
- added preview and exact digest-bound execution for recording a verified
  snapshot;
- detects paths removed between consecutive verified snapshots;
- protects the immediately preceding snapshot for 30 full days after verified
  deletion detection;
- does not reset the clock while a path remains absent;
- resolves a hold after verified reappearance and starts a fresh hold after a
  later deletion;
- added a read-only retention preview that separates actively protected
  candidate snapshots from hold-clear candidates;
- kept all restic `forget` and `prune` execution unavailable.

## Files changed

- `lib/soul_core/backup_retention_ledger.rb`
- `scripts/soul-backup-retention.rb`
- `scripts/verify-backup-retention-ledger-a1.rb`
- `docs/soul/BACKUP_RETENTION_A1_BRIEF.md`
- `docs/soul/BACKUP_AND_RECOVERY.md`
- `docs/soul/BACKUP_AND_DISASTER_RECOVERY_A0_BRIEF.md`
- `docs/assessments/BACKUP_RETENTION_A1_REVIEW.md`
- `docs/assessments/BACKUP_AND_DISASTER_RECOVERY_A0_REVIEW.md`
- `config/project_tracker_seed.json`
- `docs/ROADMAP.md`

## Commands run

```text
ruby -c lib/soul_core/backup_retention_ledger.rb
ruby -c scripts/soul-backup-retention.rb
ruby -c scripts/verify-backup-retention-ledger-a1.rb
ruby scripts/verify-backup-retention-ledger-a1.rb
```

The final review packet will also record repository-wide documentation,
privacy, timeline, and diff checks.

## Deterministic test results

The verifier passes:

- exact confirmation and stale-digest rejection;
- owner-only atomic initialization;
- idempotent replay;
- deletion detection against the prior verified snapshot;
- exact 30-day hold duration;
- day-29 protection and exact day-30 hold clearance;
- no clock reset across later missing snapshots;
- verified reappearance and a later fresh deletion;
- source-root change rejection;
- repository-identity change rejection;
- failed-verification rejection;
- clock-rollback rejection;
- path-escape rejection;
- corrupt- and missing-ledger fail-closed behavior;
- absence of retention execution.

## Local LLM evaluation

None. Snapshot identity, path comparison, time boundaries, and approval binding
are deterministic safety behavior and must not be evaluated by a model.

## Known weaknesses

- the current manual backup procedure does not yet emit the versioned manifest
  directly from restic JSON;
- the ledger proves deletion holds but does not choose a complete retention
  policy;
- hold-clear snapshots may still be required for other recovery reasons;
- no `forget` or `prune` executor exists;
- no off-site copy exists;
- the SanDisk remains inside the workstation's chassis and failure boundary.

## Memory keys

None. The ledger is private backup operational state, not conversational
memory. It resides under the existing encrypted P0 backup surface.

## Lifecycle states touched

- `complete`;
- `awaiting_input`;
- `blocked_for_human_review`.

No operation remains running after return.

## Risk classification

Medium. The ledger affects future retention decisions, but this candidate
cannot delete snapshots or invoke restic. Missing, corrupt, stale, changed, or
unverified inputs fail closed.

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
Skill-private memory store added: no
restic forget/prune execution added: no
```

## Human review checklist

- [ ] Confirm the manifest schema represents the exact verified snapshot.
- [ ] Confirm unchanged source roots must fail rather than infer mass deletion.
- [ ] Confirm 30 full 24-hour periods from verified detection.
- [ ] Confirm verified reappearance resolves the old hold.
- [ ] Confirm hold-clear is not presented as delete authorization.
- [ ] Confirm ledger path and `0600` handling.
- [ ] Confirm `forget` and `prune` remain unavailable.
- [ ] Approve, request repair, or reject the candidate.
