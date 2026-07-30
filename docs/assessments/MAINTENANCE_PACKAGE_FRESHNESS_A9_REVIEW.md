# Maintenance Package Freshness A9 Review

## Candidate status

```text
candidate_complete_operator_visual_review_pending
```

## Implementation summary

Atelier's per-device status refresh now uses the installed `checkupdates`
utility to obtain current pacman repository evidence in an isolated temporary
database. The normal pacman database is not synchronized or changed. Missing
tooling degrades to explicitly cached `pacman -Qu` evidence, while a failed
fresh query remains unavailable rather than returning a misleading cached
zero.

The Dashboard appends **fresh** or **cached metadata** to the package-channel
summary. Existing AUR, Flatpak, APT, and DNF5 query behavior and every
maintenance/reboot gate remain unchanged.

## Files changed

- `assets/dashboard/dashboard.js`
- `config/project_tracker_seed.json`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_PACKAGE_FRESHNESS_A9_BRIEF.md`
- `docs/assessments/MAINTENANCE_PACKAGE_FRESHNESS_A9_REVIEW.md`

## Commands run

```text
checkupdates --nocolor
make verify-maintenance-fleet-status
make verify-maintenance-device-control
make verify-crucible-fedora-status
make verify-maintenance-fleet-discovery
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-maintenance-fleet-status-b1.rb
node --check assets/dashboard/dashboard.js
git diff --check
systemctl --user restart soul-dashboard.service
one configured MaintenanceFleetStatusService refresh for workstation
```

## Deterministic test results

All listed deterministic suites passed. Fixtures cover successful fresh
evidence, successful no-update exit `2`, absence of a live sync-database
command, missing-tool cached fallback, failed-evidence handling, and the
existing platform-specific channel inventory.

The live configured refresh completed in 7.1 seconds, retained the Atelier
identity and address, reported 14 pacman updates plus zero AUR and Flatpak
updates, and recorded `workstation.native_updates_fresh` with exit `0`.

## Local LLM eval results

Not applicable. Package command identity, exit status, freshness, and counts
are deterministic evidence.

## Memory keys

Reads: none.

Writes: none.

## Lifecycle states touched

- `complete`
- `failed`

## Risk classification

Class 1: bounded read-only package-status refresh. The temporary sync metadata
is reproducible cache material and does not alter installed packages or the
live pacman database.

## Safety and persistence check

```text
Package mutation added: no
Privilege added: no
Persistent service added: no
Timer or polling added: no
Automatic retry added: no
Maintenance/reboot authority changed: no
New private state store added: no
```

## Known weaknesses

- Fresh pacman evidence depends on `checkupdates` from `pacman-contrib`.
- APT counts remain based on cached metadata because a fresh `apt-get update`
  is privileged mutation and belongs to maintenance, not read-only refresh.
- Network or mirror failure marks pacman evidence unavailable for that click.

## Human review checklist

- [x] Matches the approved freshness request.
- [x] Does not use `pacman -Sy`, `pacman -Syy`, or sudo.
- [x] Missing tooling is labeled cached.
- [x] Failed fresh evidence is not mislabeled.
- [x] Live configured backend refresh finds current Atelier updates.
- [ ] Operator confirms the fresh label and count through the Dashboard.

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
