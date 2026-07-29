# Crucible Backup Replication A2 Review

Status: candidate implementation; human review required

## Implemented

Backup & Recovery now presents Crucible's encrypted second-copy state and one
manual initialize/copy/verify gate. The service verifies the fixed SSH target,
inventories both repositories, initializes only when absent, copies missing
tagged snapshots, runs a target metadata check, proves coverage through
restic's preserved `original` snapshot lineage, and records an owner-private
receipt. Destination storage IDs are intentionally different because the
target repository has independent encryption.

## Files changed

- `.env.example`
- `Makefile`
- Dashboard HTML and JavaScript
- application contract, facade, and administration stream allow-list
- `lib/soul_core/backup_administration_service.rb`
- deterministic verifier, brief, guides, current state, roadmap, and tracker

## Deterministic results

```text
ruby -c lib/soul_core/backup_administration_service.rb                         PASS
ruby -c scripts/verify-crucible-backup-replication-a2.rb                      PASS
node --check assets/dashboard/dashboard.js                                    PASS
make verify-crucible-backup-replication                                       PASS
make verify-backup-administration                                             PASS
make verify-project-timeline                                                  PASS
ruby scripts/verify-phase12a-portable-typed-configuration.rb                  PASS
make test-fast                                                                PASS
git diff --check                                                              PASS
```

## Local LLM evals

Not applicable. Repository identity, authorization, password handling, command
vectors, and snapshot coverage are deterministic contracts.

## Known weaknesses

- Live initialization and transfer speed remain untested until the Operator
  supplies the password through the Dashboard.
- The first accepted slice performs no remote deletion, so Crucible can retain
  snapshots later removed locally.
- Nightly execution requires a separate reviewed noninteractive credential and
  systemd timer design.

## Live lineage repair

The first live initialize/copy/check run on 2026-07-29 copied all three source
snapshots and passed target metadata verification, but the original candidate
then failed closed because it compared destination storage IDs directly with
source storage IDs. Restic deliberately changes IDs when copying snapshots
between independently encrypted repositories and preserves the source identity
in each destination snapshot's `original` field.

The repaired verifier validates both ID fields, binds previews to source and
destination lineage inventories, proves exact coverage using `original || id`,
and records both source and destination identities in the owner-private
receipt. Its deterministic runner now assigns different destination IDs so the
fixture cannot regress to the invalid same-ID assumption. The broader Backup
Administration, Project Timeline, portable configuration, and live fast-model
checks remain passing.

## Memory, state, and lifecycle

No memory keys are used. Receipts use existing owner-private backup state.
Calls terminate as `complete`, `awaiting_input`, `blocked_for_human_review`, or
`failed`; no process survives the request.

## Risk

Class 4 encrypted off-device storage mutation. No destructive operation exists.

## Human review

- [x] Deterministic verification passes.
- [x] Existing local backup behavior remains passing.
- [x] No secrets appear in arguments, receipts, browser persistence, or Git.
- [x] No deletion, scheduler, or background retry was added.
- [ ] Live initialize/copy/check and repaired lineage reconciliation through
  the Dashboard.
