# Enrolled Proxmox Inventory A5 Review

Status: candidate-complete; live evidence collected; awaiting Dashboard
acceptance and merge approval.

## What was implemented

- Added deterministic recognition of an enrolled PVE kernel plus executable
  `pveversion`.
- Added bounded read-only collection of PVE version, cached APT updates,
  running/available kernels, reboot evidence, and LXC/QEMU guest summaries.
- Kept the enrolled identity, alias, and `inventory_only` control boundary.
- Corrected one-device refresh so an enrolled Proxmox card cannot be replaced
  with Forge.
- Updated the Dashboard to render read-only Proxmox status instead of hiding it
  behind generic `not queried` language.
- Added guest-state chips and an explicit message that maintenance and reboot
  authority remain disabled.

## Files changed

- `assets/dashboard/dashboard.js`
- `config/project_tracker_seed.json`
- `docs/assessments/ENROLLED_PROXMOX_INVENTORY_A5_REVIEW.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/ENROLLED_PROXMOX_INVENTORY_A5_BRIEF.md`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`

## Commands run

```text
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-maintenance-fleet-status-b1.rb
ruby scripts/verify-maintenance-fleet-discovery-a1.rb
make verify-maintenance-fleet-status verify-maintenance-fleet-discovery
git diff --check
```

## Deterministic results

- PVE classification requires both reviewed `-pve` kernel evidence and the
  fixed executable probe.
- Rich evidence remains read-only and uses no shell.
- Guest details are allowlisted and bounded.
- Refresh retains the enrolled Foundry identity and never substitutes Forge.
- Generic SSH inventory and Fedora DNF5 behavior remain intact.
- The Dashboard exposes current status without adding mutation controls.

## Live result

Foundry was reached through its newly reviewed literal alias. The adapter
identified `pve-manager/9.2.2`, running kernel `7.0.2-6-pve`, no newer selected
kernel, no reboot marker, no current guests, and 28 cached-metadata APT update
records. The resulting card remained non-mutating.

During the same review Crucible was confirmed online at its reviewed address
and VM 200 was running on Forge. Its dedicated known-host file contained a
stale ED25519 key. The newly presented fingerprint matched the exact address
whose neighbor MAC matched VM 200's configured virtual NIC. The stale entry was
backed up and replaced; bounded SSH hostname and kernel checks then succeeded.

## Local LLM evaluation

Not applicable. Classification, collection, and rendering are deterministic.

## Known weaknesses

- Cached APT simulation does not refresh repository metadata.
- Guest inventory is descriptive and grants no guest-control authority.
- A separately reviewed adapter is still required before Foundry can expose
  maintenance or reboot actions.

## Memory keys

None.

## Lifecycle states touched

- collection/refresh: `complete`, `failed`
- host: `healthy`, `updates_available`, `attention`, `offline`

## Risk classification

Class 2 authenticated read-only host inventory. No mutation authority.

## Human review checklist

- [ ] Refresh Guided Maintenance and confirm Foundry identifies as Proxmox.
- [ ] Confirm current PVE version, update count, kernel, reboot, and guest
      evidence are visible.
- [ ] Confirm Foundry still has no Maintain or Reboot button.
- [ ] Confirm Crucible returns online after refresh.
