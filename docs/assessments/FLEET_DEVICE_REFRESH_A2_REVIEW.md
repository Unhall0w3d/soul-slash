# Fleet Device Refresh A2 Review

Status: candidate complete; live Operator review pending

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

- [ ] Open Guided Maintenance and confirm every card shows **Checked**.
- [ ] Refresh the Amplifi card.
- [ ] Confirm the Amplifi remains **Reachable** and its **Checked** time changes.
- [ ] Confirm the status line says only that device was probed.
- [ ] Confirm no Maintenance or Reboot control appears on the Amplifi card.
- [ ] Confirm another device's **Checked** time remains unchanged.
