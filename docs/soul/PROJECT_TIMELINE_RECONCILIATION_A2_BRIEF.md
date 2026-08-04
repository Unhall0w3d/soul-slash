# Project Timeline Reconciliation A2 Brief

## Objective

Reconcile Soul's tracked starter timeline, accepted repository evidence, and
the existing revisioned owner-local ledger without replacing private planning
state or creating automatic synchronization.

## Problem

`config/project_tracker_seed.json` initializes a new ledger only once. That is
the correct privacy and authority boundary, but later accepted features can be
missing from an older owner ledger while stale seed statuses can remain visible
to a fresh installation. Ordinary conversation and Git activity deliberately
do not mutate either source.

## Authorized scope

- Correct exact public-seed records whose human-review outcome is already
  documented.
- Add public records for the accepted Soul/Noctalia companion and active
  host-CIS review.
- Preserve pending human gates for YouTube description sync, Chancery,
  portable DHCP identity, and Noctalia Core control.
- Import selected missing records into the existing owner ledger through
  `ProjectTrackerService`, preserving all private-only records and incrementing
  only affected revisions.
- Record the unmerged atomic-citation experiment only in the owner ledger until
  it receives an explicit integration or retirement decision.

## Forbidden scope

- No automatic seed-to-owner synchronization, watcher, timer, or inferred
  status change.
- No wholesale replacement of `Soul/private/project_tracker/state.json`.
- No deletion of private-only items, notes, or historical revisions.
- No claim that passing tests, a merge, or model output constitutes human
  acceptance.
- No mutation of Wazuh, network devices, YouTube, WinBoat, Noctalia, or host
  hardening state from the timeline operation.

## Acceptance

- The public seed has unique valid IDs and truthful reviewed/pending statuses.
- A fresh ledger passes `make verify-project-timeline` and exercises the A2
  semantic status checks.
- The owner ledger retains all pre-reconciliation IDs, adds only reviewed
  missing records, and exposes the current active decisions under **Now**.
- The pre-reconciliation owner ledger remains recoverable outside the project.
- No background behavior or new mutation authority is added.
