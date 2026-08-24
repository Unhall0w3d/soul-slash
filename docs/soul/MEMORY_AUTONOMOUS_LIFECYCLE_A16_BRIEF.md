# Memory Autonomous Lifecycle A16 Brief

## Status

Human-authorized implementation slice. This brief joins the already approved
A12 derivation and A13 deterministic admission stages into one bounded
foreground operation. It does not authorize scheduling, a persistent worker,
or an always-running improvement bridge.

## Objective

Allow one explicit invocation to process one unit of pending ordinary-memory
work without separate derive and admit gestures. The operation first drains one
previously derived packet when present. Otherwise it derives one bounded A12
packet from pending observations and immediately submits that exact packet to
A13 admission.

## Authority

- The local model may propose memory only through the existing closed A12
  schema. It receives no lifecycle authority.
- A13 code remains the sole admission authority. Protected proposals remain
  `blocked_for_human_review` and never enter canonical memory automatically.
- Ordinary admission remains governed by the reviewed A13 evidence,
  confidence, duplicate, audit, and rollback rules.
- The standing human-approved ordinary-memory policy replaces separate
  per-stage confirmation, not the audit or protection boundaries.

## Execution and recovery

- One foreground invocation processes at most one derivation packet and one
  admission decision.
- Stable sub-request identifiers make an interrupted retry reconcile the same
  derivation and admission work.
- A content-free, append-only, hash-chained cycle journal records the terminal
  combined receipt. Replaying a completed cycle request is idempotent.
- If an older derivation packet is pending, the cycle admits that packet and
  does not ask the model to derive newer observations in the same invocation.
- Failure is terminal and explicit. A later invocation may resume; no process
  remains alive waiting for work or for the operator.

## Boundaries

- No service, timer, watcher, listener, polling loop, background continuation,
  Core switch implementation, external database, deletion, consolidation,
  supersession, speculative recall, or protected-memory promotion.
- No memory content, conversation text, model output, paths, or secrets appear
  in the cycle journal or public receipt.
- Scheduling and Core-aware background orchestration remain a separately
  reviewed A17 slice.

## Acceptance

Deterministic verification must prove pending-packet-first ordering, the
derive-then-admit path, no-work behavior, protected-memory blocking inherited
from A13, stable interruption recovery, replay idempotency, journal-chain
integrity, strict one-packet bounds, content-free receipts, and explicit
foreground-only behavior.
