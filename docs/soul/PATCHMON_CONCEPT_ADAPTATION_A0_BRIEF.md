# PatchMon Concept Adaptation A0 Brief

Status: human-approved for candidate implementation on 2026-08-15.

## Purpose

Adapt the useful operational concepts observed in PatchMon to Soul's existing
local-first maintenance fabric without importing PatchMon code or broadening
Soul into a generic remote-management platform.

A0 creates one read-only, versioned operations-evidence projection. It joins
the most recent persisted fleet snapshot with existing retained device
maintenance receipts so the Operator can distinguish:

- what Soul last observed about each enrolled device;
- what fixed, reviewed operation actually ran;
- whether newer fleet evidence exists after that operation; and
- whether the newer evidence is consistent with the operation's narrow goal.

Execution success and post-run verification are deliberately separate facts.

## Approved operation

`maintenance.fleet.evidence`

The operation is foreground, read-only, and bounded. It reads retained local
evidence only. It does not collect fresh fleet status, execute maintenance,
reboot a device, acknowledge an alert, or mutate a receipt.

## A0 contract

Schema: `soul.maintenance.fleet_evidence.a0.v1`

The response contains:

- a bounded per-device evidence index;
- a bounded, newest-first index of the latest retained transaction per device;
- execution state copied from the retained receipt;
- reconciliation state derived from timestamped fleet evidence;
- a compact summary of pending verification, attention, and verified work;
- explicit source availability and contract boundaries.

Allowed reconciliation states are:

- `verified` — newer device evidence exists and is consistent with the narrow
  operation goal;
- `attention` — newer evidence exists but reports an operation-relevant
  condition requiring review;
- `awaiting_fresh_evidence` — the operation terminated, but no newer device
  observation exists;
- `not_applicable` — the receipt did not complete successfully, so success
  reconciliation would be misleading;
- `unknown` — the retained evidence is incomplete or cannot support a claim.

For maintenance, `verified` requires newer reachable evidence and an assessed
update total of zero. For reboot, `verified` requires newer reachable evidence;
the existing reboot receipt remains the authority for its own boot-identity and
readiness checks. Unassessed package state never becomes a healthy claim.

## Privacy and bounds

- At most 64 devices and 64 latest retained transactions are projected. Older
  receipts remain in their existing receipt store and are not reinterpreted
  against today's device state.
- Device addresses, MAC addresses, raw command arguments, stdout, stderr,
  credentials, paths, and diagnostic excerpts are excluded.
- Public fixtures use generic device identities only.
- Source failures become explicit availability gaps, not healthy defaults.
- Output ordering is deterministic for fixed inputs and clock.

## Authority boundaries

A0 adds no agent, service, daemon, watcher, listener, timer, schedule, polling
loop, automatic patching, fleet-wide action, arbitrary SSH command, new package
manager adapter, new sudo authority, or new reboot authority.

Existing maintenance and reboot preview, digest, confirmation, and
device-scoped authority gates remain unchanged. The Dashboard may render the
projection and refresh it after an already-authorized operation, but rendering
it grants no authority.

## Lifecycle and failure behavior

The operation terminates as `complete` or `failed`, always with
`mutation: none`. It does not wait for future observations. Pending
reconciliation is represented as data and re-evaluated on a later invocation.

## Deterministic acceptance

- The application contract and facade expose only the read operation.
- Completed maintenance with newer clean evidence becomes `verified`.
- Completed maintenance without newer evidence remains
  `awaiting_fresh_evidence`.
- Newer evidence with remaining updates or an unreachable device becomes
  `attention`.
- Failed or canceled receipts become `not_applicable`.
- Missing sources are explicit and never rendered as healthy.
- Sensitive receipt and fleet fields do not appear in serialized output.
- Devices and transactions remain bounded and deterministically ordered.
- Existing maintenance control verification continues to pass.

## Explicitly deferred

Historical time-series storage, host groups, canary waves, repository
provenance, alert acknowledgement, notification routing, telemetry agents,
scheduled collection, automatic maintenance, and One Approval, One Workflow
policy changes remain separate future slices.
