# Automatic Memory Projection Reconciliation A33 Review

Status: candidate-complete for human review. Deterministic validation passes;
live timer-driven reconciliation after a real canonical mutation remains
untested and is not implied by these checks.

## Implemented

- Added an owner-private, atomic reconciliation request checkpoint and bounded
  content-free JSONL audit.
- Added restart recovery that derives pending work from verified canonical,
  local-index, and active-selector digest drift even if a request write was
  interrupted.
- Added a local-index-first reconciliation sequence that rechecks the canonical
  audit head before and after rebuilding, consumes the existing A21 exact plan
  gate internally, verifies both remote stores, and activates one generation.
- Added a three-consecutive-failure bound. A blocked request is not retried
  until a newer canonical source digest supersedes it.
- Added an A33 coordinator around A31. Canonical work retains priority and only
  records later projection work; reconciliation cannot occur in that same
  activation.
- Reused the installed A17 timer and service unchanged. Projection dependencies
  are lazily constructed only after Core eligibility and canonical no-work are
  established.

## Files changed

- `lib/soul_core/memory_projection_reconciliation_request_store.rb`
- `lib/soul_core/memory_automatic_projection_reconciliation_service.rb`
- `lib/soul_core/memory_lifecycle_projection_coordinator.rb`
- `lib/soul_core/memory_projection_runtime_factory.rb`
- `scripts/soul-memory-lifecycle-worker`
- `scripts/verify-memory-automatic-projection-reconciliation-a33.rb`
- `scripts/verify-memory-lifecycle-maintenance-a31.rb`
- `docs/soul/MEMORY_AUTOMATIC_PROJECTION_RECONCILIATION_A33_BRIEF.md`
- `docs/assessments/MEMORY_AUTOMATIC_PROJECTION_RECONCILIATION_A33_REVIEW.md`
- `docs/CURRENT_STATE.md`
- `Makefile`

## Lifecycle, memory, and risk

- Lifecycle states: `complete`, `failed`, `blocked_for_human_review`, and
  content-free request states `pending`, `complete`, `canceled`.
- Canonical mutation authority: unchanged from A31.
- Derived mutation authority: local approved-memory index replacement and one
  verified Qdrant/FalkorDB generation activation.
- Memory keys: none. Private request and audit files are operational derived
  state, not a second memory authority.
- Risk: autonomous replacement of rebuildable derived state. Canonical memory,
  protected-memory policy, physical deletion, Core switching, credentials, and
  publication remain outside A33.

## Deterministic validation

- `make verify-memory-automatic-projection-reconciliation` — passed, 15 checks.
- `make verify-memory-lifecycle-maintenance` — passed, 15 checks.
- `make verify-memory-core-aware-worker` — passed, 18 checks.
- `make verify-memory-projection-reconciliation` — passed, 17 checks.
- Ruby syntax checks for every changed executable/library — passed.
- `git diff --check` — passed.

## Known weaknesses and live review

- No real canonical mutation was created merely to exercise A33.
- The installed A17 unit has not yet run this candidate branch; deployment
  digest/status and a supervised later-activation reconciliation remain human
  review steps after merge.
- Cancellation uses a separate exact preview/digest/confirmation CLI and Make
  target. No Dashboard cancellation control is added in this slice.
- Three failed attempts require a newer canonical digest or a separately
  reviewed operator reset path; A33 intentionally provides no silent reset.

## Human review checklist

- [ ] Confirm canonical work and projection work never share one activation.
- [ ] Confirm request/audit receipts expose no memory content or credentials.
- [ ] Confirm Free and Creative Core skip before projection dependencies load.
- [ ] After merge, review the new installation digest before reinstalling the
  existing A17 unit.
- [ ] Supervise one canonical mutation followed by a later timer activation and
  confirm local index, both remote stores, and selector converge.
- [ ] Confirm a forced remote failure preserves the previous selector/local
  fallback and increments the bounded attempt count.
