# Maintenance Pacman Runtime A10 Review

## Candidate status

```text
candidate_complete_operator_visual_review_pending
```

## Implementation summary

Atelier's official package query now reproduces the safe isolated-database
semantics of `checkupdates` without relying on its incompatible inner
downloader sandbox. One fixed `fakeroot pacman -Sy` writes only to a temporary
database and runs with `--disable-sandbox` inside Soul's already hardened
systemd namespace. A separate temporary-database `pacman -Qu` supplies the
official count. `yay -Qua` supplies only the AUR count.

No package, live sync database, privilege boundary, service unit, maintenance
gate, or retry behavior changed.

## Files changed

- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_PACMAN_RUNTIME_A10_BRIEF.md`
- `docs/assessments/MAINTENANCE_PACMAN_RUNTIME_A10_REVIEW.md`
- `config/project_tracker_seed.json`

## Commands run

```text
make verify-maintenance-fleet-status
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-maintenance-fleet-status-b1.rb
git diff --check
bounded systemd-run diagnostics matching the Dashboard sandbox
one configured MaintenanceFleetStatusService workstation refresh in that sandbox
```

## Deterministic results

All fleet-status checks pass, including:

- isolated temporary database and cleanup;
- fixed `--disable-sandbox`, `--dbpath`, and `/dev/null` log arguments;
- independent official and AUR rows;
- successful empty official result;
- missing-tool cached fallback;
- failed fresh sync without stale substitution.

## Live result

The exact Dashboard sandbox completed a configured Atelier refresh in 2.8
seconds:

```text
pacman 0 · AUR 0 · Flatpak 0 · fresh
official sync: complete
official query: complete (exit 1 = no rows)
AUR query: complete (exit 1 = no rows)
```

## Local LLM eval

Not applicable. Command identity, bounds, cleanup, exit status, and counts are
deterministic evidence.

## Memory and lifecycle

```text
Memory keys: none
Lifecycle states: complete, failed
Persistent state: existing fleet snapshot only
```

## Risk and known weakness

Class 1 bounded read-only status collection. Fresh official evidence depends on
`fakeroot` and pacman. Disabling pacman's inner downloader sandbox is acceptable
only within Soul's hardened outer service namespace and only with the temporary
`--dbpath`; deterministic checks bind both requirements.

## Human review checklist

- [x] Official and AUR counts are independent.
- [x] No live database synchronization occurs.
- [x] No package mutation or privilege was added.
- [x] Exact Dashboard sandbox verification passed.
- [ ] Operator confirms the normal card no longer says pacman unavailable.

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
