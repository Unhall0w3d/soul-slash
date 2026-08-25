# Memory Fusion Chat and Voice A27 Brief

Status: implementation candidate. Runtime use depends on an A26 owner-private
policy selector activated from reviewed A25 evidence.

## Objective

Route ordinary conversation through the selected retrieval policy without
changing canonical memory authority. Voice Presence submits through the same
ApplicationFacade `chats.send` path as typed Chat, so both receive one context
policy rather than separate memory implementations.

## Runtime behavior

- Missing, malformed, local-only, or unreadable policy state uses the existing
  local retrieval result unchanged.
- The production projection-gated policy requires a fresh exact A23 projection
  result, fixed score `>=0.55`, and a healthy local hybrid result. The original
  A25 profile remains immutable at `0.65` for audit history.
- Projection candidates remain canonical local-ledger joins. Their admitted set
  is ordered by local rank where available.
- Projection failure, fallback, stale identity, malformed results, or local
  embedding loss returns the already-computed local result.
- Semantic context re-reads every selected ID from the current canonical
  approved ledger before prompt use.

No memory mutation, policy mutation, projection rebuild, retry, service, timer,
Core transition, or separate Voice memory store is authorized.
