# Selectable Recovery Rehearsal A3 Review

## Candidate

Name: Selectable local and Crucible recovery rehearsal

Risk class: High — authenticated restore writes a complete private snapshot
into an Operator-selected directory

Branch: `codex/selectable-recovery-rehearsal`

Status: `candidate_complete`; live qualification pending

## Implementation summary

The existing bounded restore gate now accepts either the local encrypted
repository or Crucible's independently encrypted second copy. It also accepts
an exact existing empty owner-only directory. Preview binds directory identity,
repository identity, local snapshot lineage, actual restore snapshot, selected
paths, and the no-promotion boundary into one digest.

A full snapshot restored to a selected directory becomes a recovery rehearsal.
After restic content verification, Soul hashes the staged inventory and verifies
that every source root from the captured snapshot manifest exists. The receipt
reports high-level private-state, conversations, creative archive, Knowledge
Vault, and service-configuration coverage. It stops for human review.

## Files changed

```text
assets/dashboard/dashboard.js
assets/dashboard/index.html
Makefile
docs/ROADMAP.md
docs/assessments/SELECTABLE_RECOVERY_REHEARSAL_A3_REVIEW.md
docs/soul/BACKUP_AND_RECOVERY.md
docs/soul/SELECTABLE_RECOVERY_REHEARSAL_A3_BRIEF.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/backup_administration_service.rb
scripts/verify-backup-administration-a2.rb
```

## Deterministic evidence

`make verify-backup-administration` proves managed staging compatibility,
selected empty-directory recovery, exact manifest-root coverage, local-to-remote
Crucible lineage mapping, fixed SFTP restore, unsafe target rejection,
nonblocking exclusion, and credential non-persistence.

`make verify-crucible-backup-replication` proves the pre-existing copy and
lineage contract remains intact.

`make verify-operator-backup`, `make verify-nightly-drs-transaction`, and
`make verify-nightly-drs-automation` prove the shared profile and DRS contracts
remain intact. `make test-fast` confirms the configured local runtime remains
available. `make test-soul` and `make doctor` also pass; the doctor retains the
pre-existing warning that the legacy `llama-server.service` name is inactive
while the configured local endpoint itself is healthy.

## Local LLM evaluation

Not applicable. Repository selection, filesystem authority, credential handling,
and restore verification are deterministic safety behavior.

## Memory

Reads: none.

Writes: none. Recovery receipts are operational evidence, not model memory.

## Lifecycle states

```text
complete
awaiting_input
failed
blocked_for_human_review
```

## Safety and persistence

```text
Live-tree promotion added: no
Automatic deletion or retention added: no
Arbitrary remote target added: no
Persistent service or timer added: no
Automatic retry added: no
Repository password persisted: no
LLM authority added: no
```

## Known weaknesses

- A selected directory is text-entered because browser directory pickers do not
  expose a trustworthy absolute host path to the local service.
- Same-user filesystem replacement remains an operating-system race boundary;
  Soul revalidates exact inode and emptiness immediately before spawning restic.
- A full rehearsal proves byte recovery and documented-root coverage, not live
  service promotion or successful login using restored credentials.
- Live Crucible qualification remains an explicit human gate.

## Human review checklist

```text
[ ] Create an empty mode-0700 recovery directory outside live and backup trees
[ ] Unlock the intended profile and select its newest replicated snapshot
[ ] Select Crucible encrypted second copy
[ ] Leave path includes blank for a full rehearsal
[ ] Confirm the preview shows local lineage, remote snapshot, exact target, and full rehearsal
[ ] Execute and retain the blocked-for-human-review receipt
[ ] Inspect representative private state, conversations, creative projects/exports, Soul Vault, and service configuration
[ ] Confirm the live Soul tree and both repositories remain unchanged
```

## Human outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Selected profile:
Source snapshot:
Crucible snapshot:
Recovery directory:
Receipt:
Notes:
```
