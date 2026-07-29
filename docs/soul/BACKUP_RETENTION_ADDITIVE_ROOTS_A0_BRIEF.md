# Backup Retention Additive Roots A0 Brief

Status: human-approved for implementation on 2026-07-29

## Outcome

Allow the deletion-retention ledger to advance after a reviewed backup manifest
reconciliation adds verified source roots, without weakening the existing
fail-closed behavior for source removal or replacement.

The operation must accept only an exact set expansion: every source root in the
last ledger snapshot must remain in the newly verified manifest. The approval
scope must disclose and bind the additions. A removed prior root must continue
to block deletion inference and all ledger mutation.

## Included

- Strict source-root superset validation during verified snapshot observation.
- Exact addition counts and path digests in preview and completion evidence.
- Approval-digest binding for the complete additive-root scope.
- Deterministic tests for additions, removals, replacements, replay, and
  deletion-hold continuity.
- Backup documentation and Project Timeline updates.

## Fixed safety boundaries

- Repository identity must remain unchanged.
- Verified snapshot time must advance monotonically.
- Every previously recorded source root must remain present.
- Removing one root while adding another is a replacement and must fail closed.
- Only normalized roots inside a passed, verified snapshot manifest qualify.
- Added roots do not authorize pruning, forgetting, or source removal.
- Existing deletion clocks and protective snapshot lineage must be preserved.
- Wrong confirmation, stale digest, replay drift, or invalid manifests must
  change no ledger state.
- No Restic command, password flow, scheduler, service, retry loop, or
  background continuation is added.

## Lifecycle

- `complete`: preview produced, exact additive observation recorded, or an
  exact prior observation replayed.
- `awaiting_input`: manifest or root transition is invalid, or confirmation is
  absent.
- `blocked_for_human_review`: approval digest is stale or an unsafe runtime
  condition is detected.
- `failed`: an atomic ledger write fails safely.

No operation remains active after returning.

## Deterministic acceptance

- An exact source-root superset previews and records only the additions.
- Addition path digests and counts are included in the bound approval scope.
- Existing deletion holds remain unchanged across an additive expansion.
- A later deletion under any retained or added root starts the normal 30-day
  hold against the immediately preceding verified snapshot.
- Removing a prior root blocks without changing the ledger.
- Replacing a prior root blocks without changing the ledger.
- Exact replay remains idempotent and altered replay remains blocked.
- Existing Backup Retention, Backup Administration, reconciliation, and census
  regressions pass.

## Human review boundary

Passing tests makes this candidate-complete only. The Operator separately
approves merge and runs a fresh verified backup so the local retention ledger
and transaction receipt can finalize against the reconciled source set.
