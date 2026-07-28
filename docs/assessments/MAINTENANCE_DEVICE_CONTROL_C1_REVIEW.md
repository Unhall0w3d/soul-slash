# Maintenance Device Control C1 Review

Status: human-approved C1 with supervised Forge and Pi-hole maintenance,
Pi-hole reboot, Forge reboot, and post-boot readiness hardening accepted.

Approval recorded: 2026-07-27 in the active development conversation.
Readiness follow-up approval recorded: 2026-07-27 in the active development
conversation.

## Implementation summary

- Replaced the visible A1, A2, and A3 maintenance sections with controls on the
  Maven, Forge, and Pi-hole cards.
- Added exactly two primary actions per card: **Maintenance** and **Reboot**.
- Preserved the reviewed A2/A3 services as Maven's backend authority instead of
  introducing a bypass.
- Added fixed-target Forge and Pi-hole preview/execute operations with
  device-specific confirmation, one global operation lock, bounded foreground
  streaming, redacted receipts, and no automatic retry.
- Added a Forge reboot dependency warning for Pi-hole LXC `100`.
- Added one reboot request followed by bounded reconnect checks, changed
  boot-identity verification, and fixed device-specific readiness checks before
  the final fleet snapshot may be replaced.
- Added private atomic fleet-status persistence and automatic card loading.
- Hardened the global operation lock with owner PID, boot identity, and process
  start identity; verified-stale locks are quarantined before one bounded
  reacquisition attempt.
- Added a 30-second grace period for empty or malformed lock files and
  inode-matched cleanup so a live acquisition race or replacement lock cannot
  be removed.
- Added a reviewed systemd oneshot/timer candidate for noon and midnight
  collection.
- Added post-maintenance and post-reboot fleet recollection.
- Unified every card's leading status chip as
  **Maintenance channel · active/unavailable**.
- Removed Pi-hole's duplicate OpenSSH display while retaining FTL, Unbound, and
  DNS health; added Forge LXC `100` state.

## Files changed

- `.env.example`
- `Makefile`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_DEVICE_CONTROL_C1_BRIEF.md`
- `docs/assessments/MAINTENANCE_DEVICE_CONTROL_C1_REVIEW.md`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `lib/soul_core/maintenance_fleet_status_deployment.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/soul-maintenance-fleet-status`
- `scripts/soul-maintenance-fleet-status-schedule`
- `scripts/soul-maintenance-resume`
- `scripts/soul-maintenance-transaction`
- `scripts/verify-maintenance-device-control-c1.rb`

The previously reviewed B1 files remain part of the same uncommitted candidate.

## Commands run

```text
ruby -c lib/soul_core/maintenance_device_control_service.rb
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c lib/soul_core/maintenance_fleet_status_deployment.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c lib/soul_core/dashboard_http_application.rb
node --check assets/dashboard/dashboard.js
make verify-maintenance-fleet-status
make verify-maintenance-device-control
make verify-maintenance-rehearsal
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-reboot-restore
ruby scripts/verify-phase12c-foreground-dashboard.rb
scripts/soul-maintenance-fleet-status
make fleet-status-schedule-plan
make fleet-status-schedule-install CONFIRM=INSTALL_SOUL_FLEET_STATUS_TIMER
git diff --check
```

A transient systemd oneshot with the exact proposed hardening was also run
once. It successfully collected all three devices and terminated.

After stale-lock hardening, the focused verifier and the B1, A1, A2, A2B, and
A3 regression verifiers were rerun successfully.

## Deterministic results

The C1 verifier passes and proves:

- one fixed device per preview and no fleet-wide action;
- the remote mutation gate defaults to disabled;
- request-supplied hosts and Maven through the remote adapter are rejected;
- wrong or stale digests execute nothing;
- a live lock owner remains authoritative;
- a dead-owner lock is quarantined before one bounded reacquisition;
- a recycled live PID with a different process start identity is treated as
  stale rather than as the original owner;
- young empty locks remain blocking during the acquisition-race grace period;
- old malformed locks are quarantined after that grace period;
- cleanup cannot delete a replacement lock with a different inode;
- Pi-hole maintenance uses three fixed, shell-free steps and never reboots;
- Forge reboot discloses Pi-hole impact;
- a remote reboot sends at most one request;
- changed boot identity is required before reboot success;
- reconnect exhaustion stops for human review without reboot retry;
- successful operations recollect status;
- failed operations retain the prior snapshot;
- the status snapshot is private, atomic, bounded, schema-checked, and
  reloadable;
- the timer is noon/midnight, persistent, and status-only;
- the Dashboard has two generated actions per device;
- card channel status is unified and OpenSSH duplication is absent; and
- remote operations use the bounded administration stream with progress.

All A1, A2, A2B, and A3 maintenance regressions pass. After the exact approved
B1/C1 files were staged, the Phase 12C verifier and its earlier-regression
chain passed completely.

## Live read-only and visual results

One real collection completed with all three devices reachable and wrote:

```text
Soul/private/host_maintenance/fleet_status.json
mode: 0600
```

The exact proposed systemd sandbox also completed a live read-only collection
in approximately seven seconds.

Visual review confirmed:

- Maven, Forge, and Pi-hole cards load automatically from persisted status;
- each card shows Maintenance and Reboot only;
- action rows align at the bottom of equal-height cards;
- all cards show **Maintenance channel · active**;
- Forge shows **LXC 100 · running**;
- Pi-hole shows FTL, Unbound, and DNS without a duplicate OpenSSH chip;
- the Forge maintenance preview is fixed to APT update/full upgrade; and
- the Forge reboot preview visibly warns that Pi-hole LXC `100` is interrupted.

## Supervised live acceptance

One exact Forge-only maintenance transaction was authorized with
`MAINTAIN_FORGE`. It ran the two reviewed fixed APT vectors with no reboot and
no retry. Both steps exited `0`; the terminal receipt was
`device_receipt_9192a74a3625e208`. Post-operation evidence showed Forge healthy,
zero outstanding updates, current kernel `7.0.14-6-pve`, no reboot indication,
and Pi-hole LXC `100` still running.

The first request encountered an empty operation lock left from an earlier
abandoned process. No command ran. The empty seven-hour-old artifact was
quarantined, and the newly reviewed transaction then completed. This incident
directly motivated the stale-lock hardening in this candidate.

One exact Pi-hole maintenance transaction was authorized with
`MAINTAIN_PIHOLE`. Its fixed APT and `pihole -up` steps all exited `0`, with no
reboot or retry. Receipt `device_receipt_713c515392cb4f19` was complete;
post-operation FTL, Unbound, blocking, DNS, package, and LXC evidence was
healthy.

One exact Pi-hole reboot was authorized with `REBOOT_PIHOLE`. Exactly one
reboot request was sent. Pi-hole returned on the first reconnect check with a
new boot identity; receipt `device_receipt_f6b016c37f4ba527` was complete.
Independent checks confirmed FTL, Unbound, SSH, blocking, and direct DNS
resolution were active.

The immediate post-reboot fleet collection observed active services and DNS
before `pihole -v` returned parseable version evidence, temporarily leaving the
card version blank. A second bounded collection restored
`Core v6.4.3 · Web v6.6 · FTL v6.7`. The follow-up candidate now keeps a reboot
inside its bounded reconnect lifecycle until fixed device-specific readiness
checks pass, preventing this partial snapshot from replacing the prior one.
Forge additionally requires Pi-hole guest service, version, DNS-listener, and
blocking evidence after LXC `100` reports running; guest running state alone
cannot complete the host reboot lifecycle.

One exact Forge reboot was then authorized with `REBOOT_FORGE` against the
hardened candidate. Exactly one reboot request was sent. Forge returned with a
new boot identity at reconnect 6, but Pi-hole version evidence remained
`not_ready` through reconnect 10 even though Proxmox, LXC state, services, DNS,
and blocking evidence were already available. Reconnect 11 passed all five
fixed readiness checks and only then replaced the fleet snapshot. Receipt
`device_receipt_1eb39ab94fb81dde` was complete.

The final persisted evidence showed Forge and Pi-hole healthy, Proxmox
`9.2.5`, kernel `7.0.14-6-pve`, LXC `100` running, complete Pi-hole
`Core v6.4.3 · Web v6.6 · FTL v6.7` version evidence, active FTL/Unbound/DNS,
zero updates, and no reboot indication. An independent direct DNS query against
The Operator-configured Pi-hole address also succeeded. This live result demonstrates that the
readiness gate prevents the partial post-boot snapshot observed by the earlier
Pi-hole reboot.

## Local LLM eval results

None. Target authorization, command allowlisting, digest validation, reboot
count, reconnect bounds, persistence, and timer contents are deterministic
safety behavior and are not delegated to a model.

## Known weaknesses

- The noon/midnight status-only timer is installed and active.
- The approved private dashboard environment now keeps remote live execution
  enabled. Every transaction still requires a fresh digest and exact
  device-specific confirmation.
- Maven A2 remains locally disabled and Maven A3 remains unavailable until its
  existing one-shot resume unit and live gate are separately accepted.
- Maven first requires the existing visible native-evidence handoff. The card
  dialog exposes this as a secondary preparation step.
- Forge and Pi-hole maintenance use fixed unattended APT `-y` with
  `--force-confold`; this policy has now completed one supervised transaction
  on each device.
- Pi-hole maintenance includes fixed `/usr/local/bin/pihole -up`; its first
  supervised run completed successfully.
- Remote maintenance may legitimately take a long time. It remains a bounded
  streaming request with progress, a 45-minute per-command bound, and no retry.
- A browser/network disconnect does not authorize another operation; the
  global lock and terminal receipt remain authoritative until the bounded
  request terminates.
- Verified-stale operation locks are retained as owner-private
  `operation.lock.stale-*` forensic artifacts. They are not automatically
  pruned in this candidate.
- Forge reboot necessarily interrupts Pi-hole because Pi-hole is its LXC
  guest. Device-scoped authority cannot remove that physical dependency.
- The former controls remain hidden in the document as a compatibility surface
  for the established Maven handlers and deterministic regressions; they are
  absent from the visible interface.

## Memory keys

None. Fleet snapshots and operation receipts are bounded operational state
under the existing private host-maintenance root.

## Lifecycle states touched

- `complete`
- `awaiting_input`
- `failed`
- `canceled`
- `blocked_for_human_review`
- internal reboot phase `waiting_for_reconnect`

No maintenance or reconnect operation is retried automatically or left
unbounded.

## Risk classification

Class 5.

The candidate adds fixed-target remote package mutation, reboot authority, and
a scheduled status-only systemd timer. The timer is installed and the approved
remote live gate is enabled; each mutation remains separately digest-bound and
confirmation-bound.

## Safety and persistence check

```text
Fleet-wide maintenance or reboot operation: no
Request-supplied host, alias, executable, or command: no
Shell or model-generated command vector: no
Remote live gate enabled: yes, after human acceptance
Maven A2/A3 bypass: no
Automatic reboot after maintenance: no
Reboot request retry: no
Maintenance retry: no
Concurrent maintenance operations: no
Live lock bypass: no
Stale lock reacquisition attempts: at most one
Password in Dashboard, Chat, Voice, file, argv, or env: no
Status timer mutation authority: status cache only
Persistent status worker or polling loop: no
Timer installed during candidate completion: yes, after exact human confirmation
Live package update or reboot during candidate completion: supervised Forge and Pi-hole maintenance; one supervised Pi-hole reboot
```

## Human review checklist

- [x] Confirm there must never be a fleet-wide Maintenance or Reboot action.
- [x] Review the two-button card layout and unified channel status.
- [x] Review Forge's Pi-hole dependency warning.
- [x] Review the fixed Forge APT vectors.
- [x] Review the fixed Pi-hole APT and `pihole -up` vectors.
- [x] Accept or change the `--force-confold` unattended configuration policy.
- [x] Review the 45-minute command and bounded reconnect limits.
- [x] Confirm Maven must continue through its existing A2/A3 gates.
- [x] Review the exact noon/midnight timer units.
- [x] Install the status timer only with
  `CONFIRM=INSTALL_SOUL_FLEET_STATUS_TIMER`.
- [x] Run one supervised maintenance action against one device.
- [x] Inspect its receipt and refreshed card before selecting another device.
- [x] Review dead-owner, empty-race, malformed-lock, and replacement-inode
  recovery behavior.
- [x] Run one supervised reboot only after reviewing dependency impact.
- [x] Review fixed post-boot readiness commands and failure behavior.
- [x] Approve, request repair, or reject the C1 candidate — approved.
