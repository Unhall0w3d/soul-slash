# Automatic Memory Projection Reconciliation A33 Brief

## Status

Human-authorized implementation slice. This brief records the Operator's
approval to reconcile derived memory indexes automatically after an audited
canonical memory mutation, using the existing A17 timer and Core-aware worker.

## Objective

Keep the local approved-memory index and the optional Qdrant/FalkorDB
projection aligned with the canonical conversation-memory ledger without
requiring a separate manual rebuild after each accepted lifecycle mutation.

## Authority and boundaries

- The canonical JSONL ledger remains the sole memory authority.
- A17/A31 canonical lifecycle work always has priority.
- One activation performs either one canonical lifecycle unit or one complete
  derived projection reconciliation, never both.
- A canonical mutation records a durable, owner-private reconciliation request.
  A later eligible activation may satisfy it.
- A missing request is recoverable: a verified digest mismatch between the
  canonical ledger and local index is itself sufficient to recreate pending
  work after a crash.
- Reconciliation first rebuilds and verifies the local embedding index, then
  prepares and verifies both remote generations, then atomically activates the
  new selector. A changed canonical digest invalidates the run before remote
  activation.
- The existing A21 confirmation gate remains intact for interactive callers.
  The A33 coordinator may consume an exact preview digest internally only
  after matching its durable request to the current canonical audit head.
- Failed remote preparation preserves the prior selector and local fallback.
- Automatic attempts are capped at three consecutive failures. The request
  then enters `blocked_for_human_review`; no later timer activation retries it
  until a newer canonical state supersedes it or a human explicitly resets it.
- Request state and audit receipts contain identifiers, digests, lifecycle
  state, attempt counts, generation identifiers, and bounded reasons only.
  They never contain memory content, embeddings, queries, credentials, paths,
  or remote payloads.
- Free and Creative Core remain ineligible. Core switching is not performed by
  this worker.
- The installed A17 timer, service hardening, cadence, and timeout are reused
  unchanged. No service, timer, daemon, listener, watcher, or polling loop is
  added.

## Superseded boundary

A7 and A31 required projection rebuilds to remain explicit foreground work.
This brief narrowly supersedes that restriction only for digest-bound derived
reconciliation performed by the existing A17 activation after canonical work
has completed. It does not grant broader unattended memory mutation authority.

## Acceptance

Deterministic verification must prove canonical-work priority, later-activation
separation, durable request recovery, exact source/audit binding, local-first
rebuild, dual remote verification, atomic selector activation, rollback to the
previous generation on failure, three-attempt blocking, content-free receipts,
Core skip behavior, restart recovery, and absence of a new persistent unit.
