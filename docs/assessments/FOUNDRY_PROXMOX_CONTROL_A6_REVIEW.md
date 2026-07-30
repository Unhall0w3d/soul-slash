# Foundry Proxmox Control A6 Review

## Implementation summary

Added Foundry as an explicit opt-in target of the existing device-scoped
Guided Maintenance controller. The enrolled Proxmox card becomes mutable only
when its literal SSH alias exactly matches the separately enabled local
configuration. Detection alone remains read-only.

Foundry maintenance uses two fixed APT command vectors. Reboot sends one fixed
request, requires a changed boot ID, then verifies Proxmox identity and its
three core management services. Existing digest gates, the global operation
lock, timeouts, bounded reconnects, terminal receipts, and post-success fleet
collection are reused unchanged.

## Files changed

- `.env.example`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-device-control-c1.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/FOUNDRY_PROXMOX_CONTROL_A6_BRIEF.md`
- `docs/assessments/FOUNDRY_PROXMOX_CONTROL_A6_REVIEW.md`

## Commands run

```text
ruby -c lib/soul_core/maintenance_device_control_service.rb
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-maintenance-device-control-c1.rb
ruby -c scripts/verify-maintenance-fleet-status-b1.rb
ruby scripts/verify-maintenance-device-control-c1.rb
ruby scripts/verify-maintenance-fleet-status-b1.rb
make verify-maintenance-fleet-discovery
make verify-crucible-maintenance-control
ruby scripts/verify-phase12a-portable-typed-configuration.rb
```

## Deterministic test results

- Device-control C1: passed, including disabled default, exact alias and
  confirmation enforcement, two fixed maintenance commands, one reboot
  request, changed boot identity, and fixed Proxmox readiness.
- Fleet-status B1: passed, including read-only detection, explicit exact-alias
  promotion, and mismatched-alias denial.
- Portable typed configuration: passed with the schema below its 64-setting
  bound and portable public defaults.

## Local LLM eval results

Not applicable. Authority, commands, lifecycle, and readiness are
deterministic and must not be validated by an LLM.

## Known weaknesses

- Foundry currently uses the reviewed root SSH identity rather than a
  root-owned narrow helper. Request data still cannot alter the configured
  alias or fixed command vectors.
- Reboot readiness verifies Proxmox management services, not future guest
  health. The preview therefore warns that all guests are interrupted, but no
  guest-specific readiness is asserted.
- Live package maintenance and live reboot remain deliberately untested until
  the Operator starts each action from its fresh Dashboard preview.

## Memory keys

None.

## Lifecycle states touched

- `complete`
- `awaiting_input`
- `failed`
- `blocked_for_human_review`

No operation remains silently running after returning control.

## Risk classification

Class 5: privileged remote package mutation and reboot. Public defaults remain
off. Local enablement exposes only preview buttons; it does not itself run
maintenance or reboot.

## Safety and persistence check

- No service, timer, watcher, daemon, or scheduled mutation was added.
- No request-supplied host, command, argument, package, or readiness check is
  accepted.
- No automatic package retry or reboot retry exists.
- Receipts remain bounded and owner-private.
- Fleet refresh remains a separate bounded status operation.

## Human review checklist

- [x] Implementation was explicitly authorized.
- [x] Public default remains read-only.
- [x] Exact enrolled alias is required for the mutable card.
- [x] Maintenance and reboot remain separate previews.
- [x] Deterministic regressions pass.
- [x] Dashboard live card exposes both controls after local enablement.
- [ ] Operator reviews any live maintenance plan before execution.
- [ ] Operator reviews any live reboot plan before execution.

## Human review outcome

Local enablement and live Dashboard inspection passed on 2026-07-29. Foundry
rendered as an active maintenance channel at its configured private address
with 28 cached APT updates, no reboot evidence, no guests, and separate
Maintenance and Reboot controls. Both backend previews reported live execution
enabled and the exact `MAINTAIN_FOUNDRY` and `REBOOT_FOUNDRY` gates. No package
mutation or reboot was started; each remains deferred to a separate Operator
click.
