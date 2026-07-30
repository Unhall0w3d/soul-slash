# Nightly DRS Transaction A1 Review

## Skill

Name: Nightly DRS Transaction A1

Risk class: encrypted local and off-device backup mutation; no deletion

Branch/checkpoint: `codex/nightly-drs-transaction-a1`

Date: 2026-07-29

## Candidate status

`candidate_complete`

## What was implemented

Backup & Recovery now exposes one supervised parent transaction that:

1. revalidates the exact local capture scope;
2. creates one encrypted Restic snapshot;
3. verifies local repository metadata;
4. inventories the snapshot and advances the 30-day deletion ledger;
5. prepares a fresh exact Crucible reconciliation;
6. copies missing snapshot lineage and verifies the remote repository;
7. requires the new local snapshot ID to appear as preserved original lineage
   on Crucible;
8. writes one terminal parent DRS receipt.

If the local leg succeeds and Crucible later fails, the valid local snapshot is
preserved and the parent result terminates as a disclosed partial mutation.
The next manual or future scheduled reconciliation can copy every missing
lineage ID.

A1 accepts the existing page-session password and retains no credential. It
installs no service or timer and performs no automatic retention.

## Files changed

```text
Makefile
assets/dashboard/index.html
assets/dashboard/dashboard.js
config/project_tracker_seed.json
docs/CURRENT_STATE.md
docs/ROADMAP.md
docs/soul/BACKUP_AND_RECOVERY.md
docs/soul/NIGHTLY_DRS_TRANSACTION_A1_BRIEF.md
docs/assessments/NIGHTLY_DRS_TRANSACTION_A1_REVIEW.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/backup_administration_service.rb
lib/soul_core/dashboard_http_application.rb
scripts/verify-nightly-drs-transaction-a1.rb
```

## Commands run

```text
make verify-nightly-drs-transaction
make verify-backup-administration
make verify-crucible-backup-replication
make verify-backup-credential-rotation
make verify-project-timeline
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby -c lib/soul_core/backup_administration_service.rb
ruby -c scripts/verify-nightly-drs-transaction-a1.rb
node --check assets/dashboard/dashboard.js
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
git diff --check
```

## Deterministic test results

The dedicated fixture proves:

- exact local-plus-Crucible preview binding;
- no mutation after wrong confirmation or stale digest;
- active Music and shared model leases block capture;
- concurrent backup work fails immediately;
- local success survives remote failure with a terminal partial receipt;
- successful remote copy contains the new local snapshot's exact original
  lineage;
- the password appears only in bounded Restic child environments;
- no password reaches argv or persisted receipts;
- no `forget`, `prune`, or remote deletion runs;
- the application facade and request-bound administration stream expose only
  the allow-listed DRS operations;
- the Dashboard separates preview and execution;
- no credential persistence or scheduling primitive is present.

Existing backup administration, Crucible replication, credential rotation,
project timeline, and shared application API regressions pass.

## Local LLM eval

Not applicable. Scope, credential transport, repository mutation, lineage, and
lifecycle behavior are deterministic.

## Memory keys

Reads: none.

Writes/updates: none.

Forget behavior: not applicable.

## Task lifecycle states touched

```text
complete
awaiting_input
blocked_for_human_review
failed
```

Every invocation is foreground-only, performs at most one local capture and
one remote reconciliation attempt, and terminates.

## Risk and persistence review

```text
Local encrypted snapshot creation: yes, exact reviewed scope
Crucible encrypted data addition: yes, missing lineage only
Local snapshot deletion: no
Remote snapshot deletion: no
Automatic retention or prune: no
Credential persisted: no
Service or daemon added: no
Timer or scheduler added: no
Watcher or polling loop added: no
Automatic retry added: no
Live restore or source mutation added: no
```

## SSH configuration finding

Default OpenSSH resolution is still unavailable because
`/etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf` is owned by `nobody` with
mode `0777`; OpenSSH rejects it as unsafe. The reviewed owner config at
`~/.ssh/config` is mode `0600` and succeeds against Crucible. Backup
replication already forces that exact file through both its identity probe and
Restic SFTP command, so A1 preserves the reviewed behavior and does not modify
the unrelated system fragment.

## Known weaknesses

- A1 still requires the Dashboard page to remain open and the password to be
  held in that page session.
- A process crash between component operations may leave a valid local
  snapshot without a parent terminal receipt. Existing component receipts and
  repository inventory still expose the recoverable state; A2 must add
  start/interruption evidence for unattended execution.
- The shared operation lock covers each component operation. The safe gap
  between local completion and remote preview permits another separately
  authorized backup operation to finish; the remote reconciliation then copies
  all currently missing lineage and must still include the A1 snapshot.
- Any regular shared model lease blocks capture. A stale lease therefore fails
  closed and requires separate model-runtime reconciliation.
- No local capacity threshold beyond the accepted mount/repository preflight is
  added in A1. A2 should expose capacity evidence before timer activation.
- Host-bound credential enrollment, missed-run rules, timer state, failure
  notification, and restore rehearsal remain A2/A3 work.

## Human review checklist

```text
[ ] Preview shows one local capture and one Crucible attempt
[ ] Wrong or stale authority cannot create a snapshot
[ ] Active Music or Visual/model work blocks capture
[ ] Local success is retained and clearly disclosed after remote failure
[ ] Success proves the new snapshot lineage on Crucible
[ ] Parent and component receipts contain no password
[ ] No retention, prune, or remote deletion occurs
[ ] Dashboard progress and terminal wording are clear
[ ] No service, timer, credential, or retry was added
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
