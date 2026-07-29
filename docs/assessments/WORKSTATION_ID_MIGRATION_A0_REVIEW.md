# Workstation Identity Migration A0 Review

Status: candidate implementation; human review required

## What was implemented

- Replaced the fleet's emitted owner-workstation ID `maven` with the portable
  canonical ID `workstation`.
- Added bounded read compatibility for old snapshot IDs, topology references,
  one-device refresh requests, and the former environment variable names.
- Added canonical `SOUL_FLEET_WORKSTATION_ADDRESS` and
  `SOUL_FLEET_WORKSTATION_LABEL` configuration.
- Made Dashboard workstation controls and active documentation
  deployment-neutral while preserving the configured human-facing label.

## Files changed

- `.env.example`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `config/project_tracker_seed.json`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/maintenance_fleet_discovery_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-device-control-c1.rb`
- `scripts/verify-maintenance-fleet-discovery-a1.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- current-state, roadmap, guide, brief, and this review artifact

## Commands and deterministic results

All candidate checks passed:

```text
ruby syntax checks
make verify-maintenance-fleet-status
make verify-maintenance-fleet-discovery
make verify-maintenance-device-control
ruby scripts/verify-phase12a-portable-typed-configuration.rb
node --check assets/dashboard/dashboard.js
jq empty config/project_tracker_seed.json
git diff --check
```

## Local LLM evals

Not applicable. Device identity migration, backward compatibility, and safety
boundaries are deterministic contracts.

## Known weaknesses

- Compatibility intentionally covers only the former `maven` identity.
- Historical review prose and immutable receipts may continue to say Maven.
- Owner-private state is migrated by one explicit fresh collection after the
  repository change is deployed; reading alone does not silently rewrite it.

## Memory and state

No conversational memory keys are added. The existing owner-private fleet
snapshot remains the only current-state store touched by live migration.

## Lifecycle states

- valid collection, legacy read, or refresh: `complete`
- invalid or unavailable snapshot: `failed`

No operation remains running after return.

## Risk classification

Class 2 local metadata and compatibility migration. No host, package, service,
network, backup, or privilege mutation is authorized by this slice.

## Human review checklist

- [x] Canonical collection output uses `workstation`.
- [x] Legacy `maven` snapshot and request inputs remain readable.
- [x] Legacy environment variables remain compatible.
- [x] Dashboard controls use the configured display label.
- [x] All deterministic regressions pass.
