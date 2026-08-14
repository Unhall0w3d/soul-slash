# Host Stewardship and File Steward A0–A2 Review

## Candidate

- Risk class: local read plus explicitly confirmed reversible file mutation
- Branch: `codex/host-stewardship-file-steward-a0-a2`
- Date: 2026-08-14
- Status: `candidate_complete`

## Implementation summary

Adds a static Host Stewardship capability registry, foreground-only Host
Presence composition, a new Administration Dashboard surface, and a separately
configured File Steward for bounded inventory, exact rename/move/copy, and
owner-private quarantine/restore.

## Files changed

```text
- lib/soul_core/host_stewardship_capability_registry.rb
- lib/soul_core/host_stewardship_service.rb
- lib/soul_core/file_steward_service.rb
- lib/soul_core/application_contract.rb
- lib/soul_core/application_facade.rb
- assets/dashboard/index.html
- assets/dashboard/dashboard.js
- assets/dashboard/dashboard.css
- scripts/verify-host-stewardship-file-steward-a0-a2.rb
- docs and public configuration listed in the pull request
```

## Deterministic validation

```text
make verify-host-stewardship-file-steward
node --check assets/dashboard/dashboard.js
ruby -c for every changed Ruby implementation and verifier
repository regression verifiers listed in the pull request
git diff --check
```

## Memory and lifecycle

- Shared memory reads: none
- Shared memory writes: none
- Private state: checksum-bound quarantine ledger and mutation receipts only
- Lifecycle states: complete, failed, awaiting_input, blocked_for_human_review
- Permanent delete: unavailable

## Safety and persistence

```text
Persistent service added: no
Daemon or watcher added: no
Scheduled task added: no
Background polling added: no
Confirmation gate weakened: no
Recursive directory mutation added: no
Overwrite added: no
Permanent deletion added: no
```

## Known weaknesses

- Host Presence intentionally summarizes existing sources rather than adding
  SMART/NVMe/Btrfs or process-I/O collectors; those remain declared planned
  capabilities.
- File Steward is limited to exact regular files and configured roots. It is
  not a general-purpose file manager.
- Copy and quarantine limits can reject very large files by design.
- No chat or voice invocation is exposed in this slice; the Operator reviews
  the Dashboard boundary first.

## Human review checklist

```text
[ ] Host Presence labels current versus persisted evidence clearly
[ ] Capability availability is not presented as action authority
[ ] Owner-local roots are appropriately narrow
[ ] Inventory does not disclose absolute configured paths
[ ] Rename/move/copy preview and exact confirmation are understandable
[ ] Overwrite and stale-preview refusal are clear
[ ] Quarantine is described as reversible, not deletion
[ ] Restore refuses an occupied original destination
[ ] Permanent deletion remains absent
[ ] No background or persistent behavior was introduced
```

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
