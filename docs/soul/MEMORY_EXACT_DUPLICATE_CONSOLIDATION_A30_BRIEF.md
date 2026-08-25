# Memory Exact-Duplicate Consolidation A30 Brief

Status: Operator-approved implementation scope, 2026-08-25

## Objective

Add one conservative autonomous lifecycle operation for ordinary approved
memory: consolidate one exact duplicate per bounded foreground invocation while
preserving the canonical append-only ledger, provenance, rollback, and protected
memory boundaries.

## Closed policy

- Consider only records currently in `approved` state and in the same layer.
- Treat content as identical only after trimming and collapsing whitespace.
  Case, punctuation, spelling, and wording differences are not duplicates.
- Exclude every group containing protected metadata.
- Select the survivor by highest confidence, then oldest creation time, then
  stable memory identifier.
- Supersede at most one duplicate record per invocation. The superseded record
  and its source evidence remain in history.
- Record actor, trigger, reason, policy version, evidence digest, state digest,
  transaction identity, and rollback reference in the canonical audit chain.

## Bounds and authority

The operation is a foreground one-shot with a closed record bound and stable
request identity. It adds no model call, embedding request, semantic comparison,
timer, service, watcher, polling loop, physical deletion, protected-memory
mutation, or projection mutation. It does not infer conflicts or rewrite memory
content. Later integration may reuse the already approved Core-aware lifecycle
timer; A30 does not alter that timer.

## Acceptance

- Exact ordinary duplicates deterministically retain one survivor.
- Near-duplicates, cross-layer records, candidates, and protected records are
  unchanged.
- One invocation changes at most one record and replay is idempotent.
- Audit verification passes before and after mutation.
- Receipts contain identifiers and digests but no memory content.
- Failure remains bounded and does not continue after returning control.
