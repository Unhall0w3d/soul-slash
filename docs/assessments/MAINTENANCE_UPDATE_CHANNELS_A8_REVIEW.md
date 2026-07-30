# Maintenance Update Channels A8 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Guided Maintenance update evidence now carries an ordered `channels` list that
names the package source actually assessed. Unsupported optional channels are
omitted. A zero count is emitted only after a successful query, while failed
evidence is marked unavailable without a count and moves the device card to
attention.

Atelier reports pacman plus available AUR and Flatpak channels. Forge, Warden,
and Foundry report APT. Crucible reports DNF5. The Dashboard renders only these
records, canonicalizes duplicate executable labels such as `apt`/`apt-get`,
and treats older private snapshots conservatively until their next refresh.
The legacy numeric update fields remain additive compatibility data.

## Files changed

- `assets/dashboard/dashboard.js`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `scripts/verify-crucible-fedora-status-a0.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_UPDATE_CHANNELS_A8_BRIEF.md`
- `docs/assessments/MAINTENANCE_UPDATE_CHANNELS_A8_REVIEW.md`

## Commands run

```text
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-maintenance-fleet-status-b1.rb
node --check assets/dashboard/dashboard.js
make verify-maintenance-fleet-status
make verify-crucible-fedora-status
make verify-maintenance-device-control
make verify-maintenance-fleet-discovery
git diff --check
```

## Deterministic test results

- Fleet status B1: passed.
- Crucible Fedora status A0: passed.
- Device control C1: passed.
- Portable fleet discovery A1: passed.
- Fixtures prove exact source labels and counts for pacman, AUR, Flatpak, APT,
  and DNF5.
- Fixtures prove a failed query has no numeric count, an absent optional
  channel is omitted, and unavailable update evidence marks the device for
  attention.
- Dashboard source checks prove the unconditional AUR and Flatpak rendering is
  removed and legacy snapshots require a refresh rather than inventing zeros.

## Local LLM eval results

Not applicable. Package applicability, evidence state, counts, and authority
boundaries are deterministic and must not be validated by an LLM.

## Memory keys

Reads: none.

Writes or updates: none.

Forget behavior: not applicable.

The existing owner-private fleet snapshot remains the only persisted status
store.

## Lifecycle states touched

- `complete`
- `failed`

This slice adds no long-running task or new operation lifecycle.

## Risk classification

Class 1: read-only status normalization and Dashboard presentation.
Maintenance and reboot authority are unchanged.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses

- Snap, Zypper, APK, and Nix labels are prepared for presentation, but no count
  appears until a future reviewed collector actually assesses that channel.
- Legacy snapshots deliberately show “evidence requires refresh” because their
  zeros cannot distinguish success from unsupported or failed evidence.
- The compatibility `native`, `aur`, and `flatpak` numeric fields remain until
  all private snapshots and consumers can migrate to `channels`.

## Human review checklist

- [x] Matches the approved brief.
- [x] No unapproved scope expansion.
- [x] No persistence or background behavior added.
- [x] Risk classification is correct.
- [x] Maintenance and reboot gates are unchanged.
- [x] Deterministic regressions are meaningful.
- [x] Failure behavior is predictable.
- [ ] Operator visually reviews source-specific update rows.

## Human review outcome

```text
Outcome: awaiting Operator review
Reviewer: Operator
Date: pending
Decision summary: pending
Required changes: pending
```
