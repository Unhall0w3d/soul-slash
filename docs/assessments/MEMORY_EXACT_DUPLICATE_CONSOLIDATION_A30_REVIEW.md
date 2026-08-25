# Memory Exact-Duplicate Consolidation A30 Review

Status: implementation candidate; live ordinary-memory execution is not part of
this slice.

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
rewriting, projection reconciliation, or timer integration. The next reviewed
slice may add this operation to the existing Core-aware one-shot lifecycle
worker after live preview evidence confirms the ordinary duplicate scope.

Risk: medium canonical lifecycle mutation, reversible through the existing
compensating audit contract. Human review remains required for merge and the
first live owner-private invocation.

Memory keys added: none. Shared canonical memory state touched by synthetic
tests: `approved` to `superseded`; live preview touched no lifecycle state.
Possible operation lifecycle states are `complete` and `failed`, and every
invocation returns in the foreground. Known weaknesses are the deliberately
narrow equality rule and deferred timer/projection reconciliation.

## Human review checklist

- [ ] Confirm exact equality remains case-sensitive and same-layer only.
- [ ] Confirm protected groups are excluded as a whole.
- [ ] Confirm survivor ordering and one-supersession bound.
- [ ] Confirm canonical audit metadata and rollback reference are sufficient.
- [ ] Approve merge separately from the first live owner-private run.
