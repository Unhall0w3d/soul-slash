# Fleet Device Refresh A2 Review

Status: live accepted; approved for merge

## Implemented

- Added typed `maintenance.fleet.device.refresh` application routing.
- Added bounded one-device collection and private snapshot replacement.
- Added per-card **Refresh** controls and visible **Checked** timestamps.
- Corrected enrolled ICMP devices to retain status-only language while their
  control capability remains `inventory_only`.
- Documented the intentionally narrow meaning of status-only reachability.

## Files changed

- `lib/soul_core/maintenance_fleet_status_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/FLEET_DEVICE_REFRESH_A2_BRIEF.md`
- `docs/assessments/FLEET_DEVICE_REFRESH_A2_REVIEW.md`
- `config/project_tracker_seed.json`

## Deterministic verification

Commands:

```text
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
node --check assets/dashboard/dashboard.js
make verify-maintenance-fleet-status
make verify-maintenance-fleet-discovery
make verify-maintenance-device-control
make verify-project-timeline
ruby bin/soul config validate
git diff --check
```

Results:

- Ruby syntax: passed
- Dashboard JavaScript syntax: passed
- Fleet status verifier: passed
- Portable discovery verifier: passed
- Maintenance device-control verifier: passed
- Project timeline verifier: passed
- Configuration validation: passed
- Git whitespace validation: passed
- Selected status-only device received exactly one bounded ping: passed
- Private snapshot preserved all devices and replaced selected evidence: passed
- Typed application operation: passed

## Local LLM evaluation

Not applicable. This is a deterministic device-status operation and UI
control; no language-model behavior authorizes or validates it.

## Memory

No memory keys were added or used.

## Lifecycle states

- `complete`
- `failed`

## Risk classification

Low, read-only local-network observation with private status-cache mutation.

## Known weaknesses

- ICMP reachability proves only that the selected address answered at that
  moment.
- A DHCP address can move; stable reservations remain recommended.
- Rich Amplifi health would require a separate vendor-specific read-only
  adapter and evidence review.

## Human review checklist

- [x] Open Guided Maintenance and confirm the per-device refresh control.
- [x] Refresh the status-only Amplifi card.
- [x] Confirm the individual refresh completes and updates the card.
- [x] Preserve the Amplifi as reachability-only with no mutation authority.

Live acceptance was completed by the Operator on 2026-07-28. The individual
Amplifi refresh worked through the intended Dashboard flow.

## Forge hostname refresh repair

Status: candidate complete; human review required

Date: 2026-07-29

The built-in Proxmox collector stores the remote node hostname as the card ID.
Forge therefore appears as `forge`, while the refresh dispatcher previously
recognized only the internal collector key `proxmox`. An individual Forge
refresh fell through to the enrolled-device registry and failed safely without
updating its observation time.

The repair recognizes a persisted built-in Proxmox card by its exact configured
address plus the existing `platform: proxmox`, SSH-management, and
non-enrollment evidence. Enrolled Proxmox devices retain registry priority, so
Foundry continues through its reviewed enrolled adapter and cannot be
substituted with Forge.

Files changed:

```text
lib/soul_core/maintenance_fleet_status_service.rb
scripts/verify-maintenance-fleet-status-b1.rb
docs/assessments/FLEET_DEVICE_REFRESH_A2_REVIEW.md
```

Lifecycle states remain `complete` and `failed`. No memory key, credential,
service, timer, listener, retry, mutation authority, or background operation
was added. The status-cache replacement remains the only mutation.

Human review:

```text
[x] Forge Refresh returns and advances its Checked timestamp
[x] Forge still exposes its existing fixed Maintenance and Reboot controls
[x] Foundry still refreshes through its enrolled alias
```

The repaired backend path completed a bounded live Forge refresh on 2026-07-29:
Healthy, zero updates, no reboot required, and a new observation time. The
Operator separately confirmed that Foundry's maintenance and reboot lifecycle
completed normally through its enrolled path.
