# Proxmox Repository and Maintenance Diagnostics A7 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Repaired Foundry's fresh Proxmox VE 9 repository configuration for its
unsubscribed, non-production role. The enterprise PVE and Ceph sources were
preserved in a root-private backup and disabled reversibly. The official
`pve-no-subscription` deb822 source was installed, one bounded metadata refresh
succeeded, and a simulated distribution upgrade completed. No package was
installed, upgraded, removed, or autoremove-selected, and no reboot or guest
mutation was requested.

The existing device controller now names one shared `device_scoped_v1`
lifecycle and records its fixed platform adapter in previews, status evidence,
and terminal receipts. Arch/pacman, Proxmox/APT, Pi-hole/Debian APT, and
Fedora/DNF5 retain one Dashboard flow while their adapters own only fixed
commands and readiness checks.

Failed fixed commands now retain a stable diagnostic class, short explanation,
and an optional sanitized excerpt capped at 480 bytes. The Dashboard presents
that evidence in the existing device dialog. It does not infer a repair or
retry the failed command.

## Files changed

- `assets/dashboard/dashboard.js`
- `lib/soul_core/maintenance_device_control_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-device-control-c1.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/PROXMOX_REPOSITORY_AND_MAINTENANCE_DIAGNOSTICS_A7_BRIEF.md`
- `docs/assessments/PROXMOX_REPOSITORY_AND_MAINTENANCE_DIAGNOSTICS_A7_REVIEW.md`

## Commands run

```text
ssh foundry /usr/bin/hostname
ssh foundry /usr/bin/pvesubscription get
ssh foundry /usr/bin/sha256sum <reviewed repository source files>
ssh foundry <fixed root-private repository backup and install operations>
ssh foundry /usr/bin/apt-get update
ssh foundry /usr/bin/apt-get -s -o Debug::NoLocking=1 dist-upgrade
ruby -c lib/soul_core/maintenance_device_control_service.rb
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-maintenance-device-control-c1.rb
make verify-maintenance-fleet-status
make verify-maintenance-device-control
make verify-crucible-maintenance-control
make verify-maintenance-fleet-discovery
git diff --check
```

## Deterministic test results

- Maintenance fleet status B1: passed.
- Maintenance device control C1: passed.
- Crucible maintenance control D1: passed.
- Portable fleet discovery A1: passed.
- The controller regression proves one lifecycle contract and the exact
  `arch_pacman`, `proxmox_apt`, `debian_apt_pihole`, and `fedora_dnf5`
  adapters.
- Failure fixtures prove repository authorization, package lock, DNS, storage,
  interrupted transaction, network, timeout, and generic classifications.
- The failure fixture also proves URL userinfo and sensitive query values are
  redacted, output is bounded, one failed command is attempted once, and no
  subsequent step runs.

## Local LLM eval results

Not applicable. Repository authority, command vectors, redaction,
classification, lifecycle, and confirmation behavior are deterministic
security controls and must not be validated by an LLM.

## Memory keys

Reads: none.

Writes or updates: none.

Forget behavior: not applicable.

The owner-private fleet snapshot and receipt archive continue to use their
existing bounded shared maintenance state.

## Lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `blocked_for_human_review`

No operation remains silently running after control returns.

## Risk classification

- Class 5 for the separately authorized remote repository repair.
- Class 1 for additive, owner-private diagnostic reporting.

The real package upgrade and any reboot remain separate Class 5 Dashboard
actions requiring fresh previews and human clicks.

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

- Package-manager error classification is deliberately conservative and falls
  back to `nonzero_exit` rather than guessing.
- Diagnostic excerpts are retained only in owner-private receipts; they are
  useful for triage but are not a complete command log.
- Repository repair remains an explicit host installation task. Enrollment
  and maintenance never change repositories automatically.
- Foundry's real upgrade and reboot remain intentionally untested in this
  slice.

## Human review checklist

- [x] Matches the approved brief.
- [x] No unapproved scope expansion.
- [x] No new persistence or background behavior.
- [x] Risk classification is correct.
- [x] Confirmation gates remain intact.
- [x] Deterministic regressions are meaningful.
- [x] Failure behavior is bounded and predictable.
- [x] Diagnostics are sanitized and useful.
- [ ] Operator reviews the candidate diff.
- [ ] Operator separately previews any future Foundry upgrade or reboot.

## Human review outcome

```text
Outcome: awaiting Operator review
Reviewer: Operator
Date: pending
Decision summary: pending
Required changes: pending
```
