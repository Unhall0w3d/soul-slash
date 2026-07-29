# Crucible Backup Replication A2 Review

Status: live accepted on Maven

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

- During the first live acceptance pass, a browser accessibility inspection
  unexpectedly surfaced the masked password input's current value to the
  assisting model. It did not enter commands, receipts, logs, persisted browser
  state, or Git, and later automation remained scoped away from the credential
  field. The repository credential must nevertheless be rotated as a separate
  local, interactive administration action.
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

## Live acceptance

On 2026-07-29 the Operator completed a fresh encrypted local capture and the
manual Crucible copy gate through Administration → Backup & Recovery. The
target initialized as an independent encrypted repository, received all three
local snapshots, passed repository metadata verification, and exposed the
cross-repository ID mismatch that prompted the lineage repair above.

After deploying the repair, a fresh Dashboard preview reported three source
snapshots, three destination snapshots, and no missing source lineages. The
bounded copy/check gate then completed without transferring duplicate data and
recorded a private verified receipt. The page-held repository password was
forgotten immediately afterward. Snapshot and receipt identifiers remain in
owner-private state rather than this repository.

## Memory, state, and lifecycle

No memory keys are used. Receipts use existing owner-private backup state.
Calls terminate as `complete`, `awaiting_input`, `blocked_for_human_review`, or
`failed`; no process survives the request.

## Risk

Class 4 encrypted off-device storage mutation. No destructive operation exists.

## Human review

- [x] Deterministic verification passes.
- [x] Existing local backup behavior remains passing.
- [x] No secrets appear in arguments, receipts, persisted browser state, or Git.
- [x] No deletion, scheduler, or background retry was added.
- [x] Live initialize/copy/check and repaired lineage reconciliation through
  the Dashboard.
- [ ] Rotate the local and Crucible repository credentials through a bounded
  local interactive procedure; do not enter replacement credentials in Chat.
