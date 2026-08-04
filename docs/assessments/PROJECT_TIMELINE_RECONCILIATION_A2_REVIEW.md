# Project Timeline Reconciliation A2 Review

## Candidate result

The tracked truth sources are reconciled without changing the first-use-only
seed contract. The owner-local update is additive and revision-preserving.

## Public corrections

- Wazuh A4d2/PR #137 acceptance and multi-endpoint boundaries are recorded.
- Lattice and Loom move from `needs_review` to archived `validated`.
- YouTube description sync remains `needs_review` because live OAuth and the
  initial reviewed batch are still open.
- Portable fleet discovery returns to `needs_review` because its A3 DHCP
  retarget and ignored-list live gate is still open.
- The Crucible sudo-hardening ID is canonicalized without duplicating the
  already accepted work.
- Accepted public-safe Noctalia companion work is archived as `validated`.
- Noctalia Core control remains `needs_review` pending its full live checklist.
- Host CIS hardening is represented as `in_progress`: Crucible has no open
  decisions, while Atelier retains reviewed residual decisions.

## Owner-ledger reconciliation

The existing ledger is updated only through `ProjectTrackerService`. Missing
seed records are imported by exact ID, existing records are updated at their
current revision, and all owner-only historical/future records remain intact.
The atomic Dev-review citation experiment is added only to the owner ledger as
`needs_review`; its unmerged commit is not represented as accepted public
functionality.

## Verification

```text
make verify-project-timeline
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
ruby -rjson -e 'JSON.parse(File.read("Soul/private/project_tracker/state.json"))'
git diff --check
```

Additional reconciliation checks compare exact IDs, prove that no prior owner
item disappeared, and confirm that the owner-local file remains mode `0600`.

## Safety and lifecycle

- Persistent service, timer, watcher, listener, or schedule added: no
- Automatic status inference added: no
- Private item deletion: no
- External or host mutation: no
- Owner backup before reconciliation: `/tmp/soul-project-timeline-state-before-a2.json`
- Lifecycle: explicit bounded timeline create/update operations only

## Human review checklist

- [x] Public seed semantic checks pass.
- [x] No owner-local timeline item was removed.
- [x] The Dashboard **Now** column presents the actual remaining review work.
- [x] Implemented inventory contains the accepted switch and Noctalia companion records.
- [x] No sensitive deployment value entered tracked files.

## Human review outcome

Accepted by the Operator on 2026-08-04 after authenticated review of the live
Project Timeline. The reconciled **Now** column and implemented inventory are
approved without further changes.
