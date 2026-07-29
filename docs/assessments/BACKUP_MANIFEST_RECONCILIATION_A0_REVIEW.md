# Backup Manifest Reconciliation A0 Review

## Skill

Name: Backup Manifest Reconciliation A0

Risk class: local configuration write; exact add-only, review-gated

Branch/checkpoint: `codex/backup-manifest-reconciliation-a0`

Date: 2026-07-29

## Candidate status

`candidate_complete`

## Implementation summary

Backup & Recovery can now compare an existing owner source/exclusion manifest
with the same portable policy used by initial Makefile setup. One preview lists
only missing policy entries, binds both current manifest hashes and the policy,
and discloses that no password or Restic operation is involved.

Exact execution:

- shares Backup Administration's non-waiting operation lock;
- rejects wrong confirmation or changed scope;
- preserves existing entries, comments, and blank lines;
- appends only tracked policy entries;
- writes both manifests owner-only with rollback on failure;
- verifies no policy additions remain;
- records a private counts-and-hashes receipt;
- stops and requires a separately authorized verified backup.

The current workstation preview contains five source additions and seven
exclusion additions with zero removals.

## Files changed

```text
- lib/soul_core/backup_manifest_policy.rb
- lib/soul_core/backup_administration_service.rb
- lib/soul_core/application_contract.rb
- lib/soul_core/application_facade.rb
- scripts/soul-backup-config
- scripts/verify-backup-manifest-reconciliation-a0.rb
- assets/dashboard/index.html
- assets/dashboard/dashboard.js
- Makefile
- config/project_tracker_seed.json
- docs/soul/BACKUP_MANIFEST_RECONCILIATION_A0_BRIEF.md
- docs/soul/BACKUP_AND_RECOVERY.md
- docs/CURRENT_STATE.md
- docs/ROADMAP.md
- this review artifact
```

## Commands run

```text
ruby scripts/verify-backup-manifest-reconciliation-a0.rb
ruby scripts/verify-backup-administration-a2.rb
ruby scripts/verify-storage-retention-backup-census-a2.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby -c lib/soul_core/backup_manifest_policy.rb
ruby -c lib/soul_core/backup_administration_service.rb
ruby -c scripts/soul-backup-config
ruby -c scripts/verify-backup-manifest-reconciliation-a0.rb
node --check assets/dashboard/dashboard.js
git diff --check
```

## Deterministic test results

The dedicated fixture passes:

- exact missing-policy preview;
- zero removal/replacement and no password/Restic behavior;
- wrong-confirmation immutability;
- digest drift rejection;
- shared operation-lock rejection;
- exact add-only execution;
- preservation of owner entries/comments/blank lines;
- owner-only manifest and receipt modes;
- receipt privacy;
- idempotent second preview;
- no external command invocation;
- application and Dashboard exposure;
- shared initial/reconciliation policy;
- approved safety boundaries.

Backup Administration, Storage & Retention A1/A2, Self Assessment Dashboard,
application API, Knowledge Vault, syntax, and staged whitespace regressions
passed.

No local LLM evaluation applies; this is a deterministic configuration
transaction.

## Memory keys

Reads: none.

Writes/updates: none.

Forget behavior: not applicable.

## Lifecycle states touched

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
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Restic operation added to reconciliation: no
Password accepted by reconciliation: no
Owner entry removal or replacement: no
```

## Known weaknesses

- Reconciliation proves manifest policy only. A later verified snapshot must
  prove durable source coverage.
- The policy intentionally includes only known Soul continuity paths; future
  artifact classes still require reviewed policy updates.
- A two-file filesystem transaction is implemented with owner-only atomic
  replacements and best-effort rollback because POSIX does not provide one
  atomic rename covering both files.
- Live execution and post-snapshot 32/32 coverage remain untested until the
  Operator accepts this candidate.

## Human review checklist

```text
[ ] Preview shows five source additions and seven exclusions on the workstation
[ ] Preview shows zero removals and no replacement
[ ] Existing custom owner entries/comments are preserved
[ ] No password is requested
[ ] No Restic operation starts
[ ] Apply writes only the reviewed additions
[ ] A fresh backup remains separately gated
[ ] Fresh snapshot brings required census coverage to the expected state
[ ] No unapproved persistence/background behavior exists
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
