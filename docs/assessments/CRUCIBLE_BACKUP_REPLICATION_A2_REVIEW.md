# Crucible Backup Replication A2 Review

Status: candidate implementation; human review required

## Implemented

Backup & Recovery now presents Crucible's encrypted second-copy state and one
manual initialize/copy/verify gate. The service verifies the fixed SSH target,
inventories both repositories, initializes only when absent, copies missing
tagged snapshots, runs a target metadata check, proves coverage, and records an
owner-private receipt.

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
ruby scripts/verify-phase12a-portable-typed-configuration.rb                  PASS
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
- [ ] Live initialize/copy/check through the Dashboard.
