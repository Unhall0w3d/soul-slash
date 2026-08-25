# Memory Retrieval Policy A26 Brief

Status: implementation candidate. The policy selector may be activated only
after the A25 qualification evidence identifies a reviewed profile.

## Objective

Persist one owner-selected retrieval algorithm without moving memory authority
away from the canonical local ledger. Missing, malformed, overly permissive, or
symlinked policy state defaults to the existing local hybrid retrieval path.

## Approved policy scope

- `local_hybrid_a4` is the safe default and rollback target.
- `projection_gate_local_order_a25` admits only projection results at the fixed
  A25 threshold `0.65`, then uses local order where available.
- `projection_gate_local_order_a29` preserves the same ordering rule at the
  production-aligned threshold `0.55`. It is separately named so A25 history is
  never silently redefined.
- Activation and rollback require exact preview digests and fixed confirmation
  phrases.
- The owner-private atomic selector retains one prior policy and up to 64
  content-free audit events containing reason digests rather than reason text.

No memory content, canonical-memory mutation, projection rebuild, service,
timer, Core transition, retry, or conversational routing is authorized here.
