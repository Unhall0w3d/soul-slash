# Crucible Fedora Deployment A0 Review

Status: candidate-complete; human review required

## What was implemented

- Deployed one Fedora 44 Cloud Base KVM guest named **Crucible** on Forge.
- Configured VMID 200, two vCPUs, 4 GiB RAM, a 40 GiB system disk, a separate
  100 GiB backup disk, VirtIO networking, autostart, cloud-init, and the QEMU
  guest agent.
- Created one dedicated Maven-held SSH key and injected it into the non-root
  `souladmin` account.
- Disabled Proxmox cloud-init package upgrades before first successful boot.
- Rejected the initially evaluated Server Guest Generic image after proving it
  lacked cloud-init; no in-guest mutation occurred on that image.
- Verified the replacement Cloud Base image against Fedora's published byte
  size and SHA-256.
- Enrolled Crucible in owner-private fleet state and collected a persisted
  Dashboard card.
- Added bounded read-only DNF5, kernel, reboot, SSH, and guest-agent evidence
  for enrolled Fedora devices.
- Formatted only the independently allocated 100 GiB disk as XFS, mounted it
  by UUID at `/srv/soul-backup` with `nodev,nosuid,noexec`, and prepared an
  empty owner-only `restic` directory.
- Rebooted Crucible once and verified a changed boot ID, cloud-init completion,
  service readiness, and persistent backup-disk mounting.

## Files changed

- `Makefile`
- `assets/dashboard/dashboard.js`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-crucible-fedora-status-a0.rb`
- `docs/guides/CRUCIBLE_FEDORA.md`
- `docs/soul/CRUCIBLE_FEDORA_BACKUP_MAINTENANCE_A0_BRIEF.md`
- `docs/soul/CRUCIBLE_OFF_DEVICE_BACKUP_A1_BRIEF.md`
- `docs/assessments/CRUCIBLE_FEDORA_DEPLOYMENT_A0_REVIEW.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`

Owner-local changes remain outside Git:

- the dedicated private/public key pair;
- the pinned SSH host key;
- the literal `crucible-maintenance` SSH alias;
- the enrolled-device registry record; and
- the persisted fleet snapshot.

## Commands run

Deployment used bounded `qm` image import, disk resize, cloud-init generation,
boot, shutdown, and status commands over the existing Forge maintenance
channel. Guest qualification used fixed SSH commands for:

- cloud-init state;
- OS, kernel, hostname, and boot identity;
- SSH and QEMU guest-agent state;
- DNF5 version, update, and reboot evidence;
- stable disk identity, filesystem, mount, ownership, and capacity; and
- one controlled reboot with bounded reconnect checks.

Repository verification:

```bash
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-crucible-fedora-status-a0.rb
make verify-crucible-fedora-status
make verify-maintenance-fleet-status
git diff --check
```

## Deterministic results

- Fedora-specific status verifier: passed.
- Existing maintenance fleet regression verifier: passed.
- Ruby syntax checks: passed.
- Diff whitespace validation: passed.

The Fedora verifier proves:

- DNF5 `check-upgrade` exit 100 is accepted as available-update evidence;
- update rows and available kernel evidence are normalized;
- DNF5 reboot JSON is distinct from available kernel evidence;
- SSH and guest-agent readiness are represented;
- every remote command is fixed, shell-free, and bounded; and
- the Dashboard displays evidence without enabling mutation controls.

## Live evidence

- Fedora Cloud Base 44 booted and cloud-init reached `done`.
- The dedicated key authenticated as `souladmin`.
- DNF5 5.4.1.0 was present before any guest update.
- SSH and QEMU guest-agent services were active.
- The independent data disk was empty and unmounted before formatting.
- XFS mount verification reported no fstab errors.
- The controlled reboot produced a different boot ID.
- `/srv/soul-backup` returned after reboot with the reviewed hardening options.
- `/srv/soul-backup/restic` remained owned by `souladmin` with mode `0700`.

## Local LLM evals

Not run. This slice is deterministic infrastructure qualification; an LLM
cannot validate disk identity, authorization, package safety, or persistence.

## Known weaknesses and deferred gates

- The initial DHCP address must receive an Operator-managed reservation before
  the fixed SSH alias is treated as durable.
- The off-device restic repository is intentionally not initialized.
- No snapshot has been copied to Crucible yet.
- DNF5 Maintenance and Reboot controls remain disabled.
- Proxmox snapshots, rollback, privilege delegation, post-update reboot, and
  readiness verification require separate exact briefs.
- The reference guest shares Forge with Pi-hole; Forge failure remains a common
  dependency even though Crucible is off Maven.

## Memory and state

No Soul conversational memory keys were added. Owner-private operational state
uses the existing shared fleet registry and snapshot infrastructure under
`Soul/private/host_maintenance/`.

## Lifecycle states

- successful deployment and collection: `complete`
- missing or invalid input: `awaiting_input`
- command or qualification failure: `failed`
- later repository initialization and mutation: `blocked_for_human_review`

No process remains waiting for input and no retry loop continues after return.

## Risk classification

Class 5 infrastructure and storage mutation.

The only formatted device was the reviewed empty Crucible data disk. The
Maven-local restic repository, Forge boot storage, Pi-hole container, and
Crucible system disk were outside that mutation.

## Human review checklist

- [ ] Crucible appears in Guided Maintenance.
- [ ] The card shows Fedora, DNF5 evidence, kernel attention, and both active
  services.
- [ ] The card offers Refresh but no Maintenance or Reboot action.
- [ ] The Operator creates or confirms a DHCP reservation.
- [ ] The off-device directory remains uninitialized until the next exact gate.
- [ ] Review the separate second-copy repository gate.
- [ ] Review the separate DNF5 mutation and reboot gate.
