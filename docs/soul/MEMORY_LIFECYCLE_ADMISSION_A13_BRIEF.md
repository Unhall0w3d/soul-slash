# Memory Lifecycle Admission A13 Brief

## Status

Human-authorized implementation slice. This brief implements the next bounded
step of the approved autonomous-memory roadmap; it does not enable background
execution or live chat wiring.

## Objective

Consume reviewed A12 derivation packets through a deterministic foreground
admission policy. The local model proposes; policy code alone decides whether
an ordinary proposal is activated, retained as a candidate, or rejected.

## Policy

- Verify the complete A12 packet chain, cited observation chain, and canonical
  memory audit chain before mutation.
- Recompute protection classification independently. Protected subjects never
  enter canonical memory and are recorded as `blocked_for_human_review`.
- Require at least one cited user observation for admission.
- Ordinary proposals below `0.70` confidence are rejected.
- Ordinary proposals at or above `0.70` become canonical candidates.
- Automatic activation requires `0.90` confidence for project, preference, or
  episodic memory and `0.95` for semantic memory.
- Exact active duplicates are not recreated. An unrelated existing candidate
  is not automatically promoted.
- Every canonical mutation shares a deterministic transaction identifier and
  remains compensatable through the A10 audit journal.

## Audit and replay

Admission decisions are appended to an owner-private, content-free,
hash-chained JSONL journal. Each outcome records the proposal identifier,
decision, resulting memory identifier when present, evidence digest,
before/after state digests, policy version, and rollback transaction reference.
The source packet digest is the cursor. Replaying an admitted source packet is
idempotent; interruption before the decision append is reconciled from the
proposal metadata already present in canonical memory.

## Boundaries

- Foreground, one source packet per invocation.
- No service, timer, watcher, polling loop, network access, external database,
  Core switch, deletion, supersession, consolidation, or speculative recall.
- No model output is authorization.
- No memory content appears in public receipts or the decision journal.
- Live chat integration and background scheduling remain later reviewed slices.

## Acceptance

Deterministic verification must prove protected-content reclassification,
threshold behavior, user-evidence requirements, exact-duplicate handling,
idempotent replay/reconciliation, source and audit tamper failure, bounded
content-free receipts, append-only decision integrity, and compensatable audit
metadata.
