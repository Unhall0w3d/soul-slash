# Memory Lifecycle Maintenance A31 Review

Status: approved, integrated, and live-qualified. The installed A17 timer uses
the A31 coordinator and currently reaches `no_work` without model invocation or
canonical mutation when no eligible work exists.

## Implemented

- Added a bounded maintenance coordinator over the reviewed A16 and A30
  services.
- Wired that coordinator into the existing A17 Core-aware worker.
- Preserved one unit of canonical work per activation and gave ordinary
  observation lifecycle work priority.
- Exposed projection reconciliation as a consequence without performing it.
- Corrected the foreground index CLI to load the private local embedding
  configuration before a manual rebuild, preventing an accidental lexical-only
  replacement of an embedding-backed index.

## Files changed

- `lib/soul_core/memory_lifecycle_maintenance_service.rb`
- `lib/soul_core/memory_core_aware_worker.rb`
- `scripts/soul-memory-lifecycle-worker`
- `scripts/memory-retrieval-observatory.rb`
- `scripts/verify-memory-lifecycle-maintenance-a31.rb`
- `docs/soul/MEMORY_LIFECYCLE_MAINTENANCE_A31_BRIEF.md`
- `docs/assessments/MEMORY_LIFECYCLE_MAINTENANCE_A31_REVIEW.md`
- `Makefile`

## Lifecycle and memory

- Lifecycle states: `complete`, `failed`.
- Canonical mutation: at most one A30 supersession per eligible activation.
- Memory keys: none.
- Audit and rollback: inherited from A30.
- Risk: bounded autonomous canonical lifecycle mutation under the approved A30
  policy; projection rebuild remains outside this authority.

## Validation

- `make verify-memory-lifecycle-maintenance`
- `make verify-memory-core-aware-worker`
- `make verify-memory-autonomous-lifecycle`
- `make verify-memory-exact-duplicate-consolidation`
- `ruby -c` for changed Ruby files
- `git diff --check`

## Known weaknesses

- A canonical consolidation intentionally makes derived local and remote
  projection generations stale until a separately authorized reconciliation.
- Only deterministic exact duplicates are eligible; semantic consolidation is
  not part of this slice.

## Human review checklist

- [x] Confirm ordinary lifecycle priority.
- [x] Confirm one-mutation-per-activation bound.
- [x] Confirm A31 itself performs no projection rebuild; A33 may consume its
  consequence only in a later activation.
- [x] Confirm no new timer or service was added.
- [x] Approve integration into the installed A17 worker.
