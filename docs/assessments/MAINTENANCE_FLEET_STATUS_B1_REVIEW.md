# Maintenance Fleet Status B1 Review

Status: human-approved and incorporated into the approved C1 device-control
candidate on 2026-07-27.

## Implementation summary

- Added one parameterless, bounded `maintenance.fleet.status` operation.
- Added read-only collection for the Maven workstation, dynamically discovered
  Forge Proxmox node, and Pi-hole LXC.
- Added normalized reachability, package, kernel, reboot, service, Pi-hole,
  DNS, and Proxmox LXC evidence.
- Added a three-device status surface and evidence-driven operations topology
  to **Administration → Guided Maintenance**.
- Preserved the existing A1, A2, A2B, and A3 mutation and reboot boundaries.
- At the B1 boundary, added no timer, scheduler, poller, watcher, retry loop,
  daemon, or persistent status cache. C1 subsequently added a reviewed private
  snapshot and status-only noon/midnight timer, documented in
  `MAINTENANCE_DEVICE_CONTROL_C1_REVIEW.md`.
- Added a dedicated Make verification target and operator documentation.

## Files changed

- `Makefile`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_FLEET_STATUS_B1_BRIEF.md`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/assessments/MAINTENANCE_FLEET_STATUS_B1_REVIEW.md`

## Commands run

```text
make verify-maintenance-fleet-status
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
node --check assets/dashboard/dashboard.js
make verify-maintenance-rehearsal
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-reboot-restore
ruby scripts/verify-phase12c-foreground-dashboard.rb
git diff --check
systemctl --user restart soul-dashboard.service
systemctl --user is-active soul-dashboard.service
```

The installed dashboard was also opened locally, the Guided Maintenance
surface was selected, and **Collect fleet status** was invoked once for visual
and live integration review.

## Deterministic results

The focused B1 verifier passes and proves:

- one terminal, read-only lifecycle with no host mutation;
- normalized workstation update and kernel evidence;
- dynamic Forge discovery and LXC `100` evidence;
- Pi-hole version, blocking, service, DNS, and package evidence;
- device cards and topology derived from the same evidence;
- fixed SSH aliases, fixed argument vectors, bounded timeouts, and no shell;
- no credentials or raw command output in returned evidence;
- one offline device remains visible without retry or loss of healthy-device
  evidence; and
- only the parameterless fleet-status application operation is exposed.

All A1, A2, A2B, and A3 maintenance regression verifiers pass. Ruby syntax,
JavaScript syntax, and `git diff --check` pass.

After the exact approved B1/C1 files were staged, the broader Phase 12C
verifier and its earlier-regression chain passed completely.

## Live integration result

The installed dashboard service remained active after restart. One live
foreground collection completed with:

```text
reachable: 3 / 3
Maven: healthy
Forge: healthy; Proxmox VE 9.2.5; kernel 7.0.14-6-pve
Pi-hole: healthy; Core 6.4.3; Web 6.6; FTL 6.7
Pi-hole FTL: active
Unbound: active
OpenSSH: active
DNS query: active
reboot indicators: 0
kernel attention indicators: 0
```

The visual review confirmed a coherent desktop layout, readable summary
metrics, three device cards, and a topology whose Forge identity is derived
from live evidence.

An initial integration run revealed that `checkupdates` cannot refresh its
temporary database inside the dashboard's filesystem namespace. The first
implementation incorrectly normalized that failure as zero. The candidate now
uses `pacman -Qu` for the workstation's cached native count and labels both
workstation pacman and remote APT counts as cached. The dashboard service
hardening was not weakened.

## Known weaknesses

- Workstation pacman and remote APT counts use current cached system metadata;
  they are not equivalent to an explicit repository refresh.
- AUR and Flatpak listing freshness depends on their upstream clients and
  network availability.
- The topology is an operational overview, not automated network discovery.
- Remote access depends on the fixed owner-managed SSH aliases and their
  dedicated keys remaining valid.
- D1 moved workstation, Proxmox, and Pi-hole display addresses to portable
  environment configuration and added the optional status-only Cisco phone
  adapter. See `CISCO_PHONE_FLEET_STATUS_D1_REVIEW.md`.
- B1 does not execute updates, restart services, operate guests, reboot,
  configure backups, enforce retention, or test recovery.
- No narrow/mobile visual acceptance has yet been recorded; approval accepts
  this as a known responsive-layout follow-up.

## Memory keys

None. Fleet evidence is request-scoped operational state and is not persisted
as conversational memory.

## Lifecycle states touched

- `complete`
- `failed`
- device-level `offline`

Every invocation terminates in the foreground. Partial device failure is
normalized inside a complete response so healthy-device evidence remains
available.

## Risk classification

Class 2.

This candidate performs bounded local and SSH-based observation against fixed
targets. It has no package, service, guest, reboot, backup, retention, or
recovery mutation authority.

## Safety and persistence check

```text
Password accepted by Dashboard, Chat, Voice, file, argv, or env: no
Private key or SSH configuration returned as evidence: no
Request-supplied host or command arguments: no
Shell command vector: no
Automatic retry: no
Background polling or refresh: no
Package metadata refresh: no
Persistent status cache: no at B1 boundary; private bounded cache added by reviewed C1
Package, service, guest, reboot, or backup mutation: no
```

## Human review checklist

- [x] Review the normalized device fields and cached-metadata labels.
- [x] Confirm Maven, Forge, and Pi-hole identities and addresses.
- [x] Confirm LXC `100` is the intended Pi-hole containment edge.
- [x] Review the topology labels, including the planned second-copy edge.
- [x] Confirm the desktop layout is readable at the normal workstation size.
- [ ] Review the narrow/mobile layout before accepting responsive behavior.
- [x] Confirm the fixed SSH aliases and credential boundary.
- [x] Confirm existing A1, A2, A2B, and A3 controls remain unchanged.
- [x] Approve, request repair, or reject this B1 candidate — approved as part
  of C1.
- [ ] Do not treat B1 acceptance as authorization for multi-device updates,
  backup execution, retention deletion, or recovery testing.
