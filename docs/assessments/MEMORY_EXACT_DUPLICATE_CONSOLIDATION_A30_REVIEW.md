# Memory Exact-Duplicate Consolidation A30 Review

Status: approved and integrated through the A31 Core-aware lifecycle worker.
The first bounded owner-private consolidation completed under the reviewed
policy, and the disposable projection was rebuilt separately afterward.

## Implemented

- One bounded foreground consolidation cycle over approved ordinary memory.
- Same-layer, whitespace-normalized exact matching only.
- Deterministic survivor selection by confidence, age, and stable identifier.
- One supersession maximum per invocation with canonical audit metadata and an
  exact compensating rollback reference.
- Protected group, near-duplicate, cross-layer, candidate, and content-disclosure
  exclusions.

## Files changed

- `lib/soul_core/memory_exact_duplicate_consolidation_service.rb`
- `scripts/soul-memory-consolidate-exact`
- `scripts/verify-memory-exact-duplicate-consolidation-a30.rb`
- `Makefile`
- `docs/soul/MEMORY_EXACT_DUPLICATE_CONSOLIDATION_A30_BRIEF.md`
- `docs/guides/MEMORY_RETRIEVAL_OBSERVATORY.md`
- `docs/CURRENT_STATE.md`
- this review artifact

## Validation

Run `ruby scripts/verify-memory-exact-duplicate-consolidation-a30.rb` and the
existing audit, lifecycle, Observatory, retrieval, and A29 closure suites.

The focused verifier passes 15 checks. Audit reconstruction passes 38 checks;
A16 lifecycle passes 19; A17 Core-aware worker passes 18; the A29 closure matrix
passes all 12 constituent checks/suites; Observatory facade passes 15; semantic
Chat context passes 11; Ruby syntax and `git diff --check` pass. No local LLM
evaluation is used because lifecycle authority and mutation safety require
deterministic validation.

The live content-free preview inspected 33 approved records, reported one
eligible exact-duplicate pair, and performed no mutation. Opaque live memory
identifiers and content are intentionally not recorded in this public artifact.

## Known limits and next gate

A30 does not perform semantic consolidation, conflict resolution, content
rewriting, physical deletion, or projection reconciliation. A31 integrated the
operation into the existing Core-aware one-shot lifecycle worker while
preserving the one-mutation bound. Projection reconciliation remains a
separate consequence and authority.

Risk: medium canonical lifecycle mutation, reversible through the existing
compensating audit contract. Merge and the first live owner-private invocation
were approved and completed.

Memory keys added: none. Shared canonical memory state touched by synthetic
tests: `approved` to `superseded`; live preview touched no lifecycle state.
Possible operation lifecycle states are `complete` and `failed`, and every
invocation returns in the foreground. Known weaknesses are the deliberately
narrow equality rule and deferred timer/projection reconciliation.

## Human review checklist

- [x] Confirm exact equality remains case-sensitive and same-layer only.
- [x] Confirm protected groups are excluded as a whole.
- [x] Confirm survivor ordering and one-supersession bound.
- [x] Confirm canonical audit metadata and rollback reference are sufficient.
- [x] Approve merge separately from the first live owner-private run.
