# PatchMon Concept Adaptation A0 — Human Review

Status: candidate-complete; human approval and merge remain pending.

## Implemented

- Added `maintenance.fleet.evidence`, a foreground read-only operation over
  the persisted fleet snapshot and existing retained device receipts.
- Added stable control-target identity joining so private enrollment IDs do not
  break receipt reconciliation.
- Separated receipt execution state from post-action reconciliation state.
- Reconciled only the latest retained transaction per device; older receipts
  remain untouched in the existing owner-private receipt store.
- Added a collapsible Guided Maintenance view with compact verified, pending,
  and attention counts plus the newest retained device transactions.
- Registered the read-only capability for Soul's Host Stewardship awareness.

## Files changed

- `lib/soul_core/fleet_operations_evidence_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/host_stewardship_capability_registry.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-patchmon-concept-adaptation-a0.rb`
- `Makefile`
- `docs/soul/PATCHMON_CONCEPT_ADAPTATION_A0_BRIEF.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/CURRENT_STATE.md`
- this review artifact

The owner-private Project Timeline record is also updated locally and remains
excluded from the public repository.

## Deterministic evidence

Commands run during candidate development:

```text
make verify-patchmon-concept-adaptation
make verify-maintenance-device-control
node --check assets/dashboard/dashboard.js
ruby -c lib/soul_core/fleet_operations_evidence_service.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c lib/soul_core/application_contract.rb
git diff --check
```

The dedicated verifier covers successful reconciliation, remaining updates,
unreachable devices, older observations, unassessed package evidence, reboot
state, failed execution, unavailable sources, privacy exclusions, deterministic
ordering, limits, facade routing, capability discovery, Dashboard boundaries,
and preservation of existing confirmation gates.

A live read against retained owner-local evidence completed with no mutation,
joined five current control targets, and returned no unknown reconciliation
states after stable identity mapping. This is integration evidence, not human
approval of the visual surface or the meaning of any current device condition.

## Local LLM eval

Not run. A0 is deterministic evidence normalization with no model-authored
routing or prose. An LLM eval would not validate its safety or reconciliation
rules.

## Memory and lifecycle

- Memory keys added or used: none.
- Lifecycle states touched: `complete`, `failed`.
- Reconciliation data states: `verified`, `attention`,
  `awaiting_fresh_evidence`, `not_applicable`, `unknown`.
- Risk classification: read-only owner-private operational evidence.
- Mutation authority: none.

## Known weaknesses and deferred work

- A0 is a current-state projection, not a time-series database or historical
  search interface.
- It does not preserve a historical reconciliation verdict separately from the
  underlying receipt; it avoids distortion by reconciling only the latest
  receipt per device.
- Host groups, canary waves, repository provenance, alert lifecycle,
  notification routing, telemetry, automatic maintenance, and One Approval,
  One Workflow policy changes are deliberately deferred.
- Visual behavior still requires authenticated human review at desktop and
  narrow/mobile widths.

## Human review checklist

- [ ] Open **Administration → Guided Maintenance**.
- [ ] Confirm **Execution & reconciliation** is readable and visually compact.
- [ ] Confirm the latest transaction per managed device is understandable.
- [ ] Confirm execution and reconciliation do not read as the same claim.
- [ ] Confirm missing or older evidence does not imply health.
- [ ] Confirm no action or authorization control exists inside this disclosure.
- [ ] Confirm existing Maintain and Reboot gates behave exactly as before.
- [ ] Approve, request changes, or reject the A0 candidate.
