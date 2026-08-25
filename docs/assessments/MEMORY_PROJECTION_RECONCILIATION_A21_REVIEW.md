# Memory Projection Reconciliation A21 Review

Status: candidate implementation; no live projection generation executed.

## Implemented

- Digest-derived immutable generation names for Qdrant and FalkorDB.
- One bounded coordinator over injected projection clients and selector storage.
- Exact preview confirmation and plan-digest drift rejection.
- Dual-store verification before owner-local selector activation.
- Compensation limited to exact generations created by the failing invocation.
- Preservation of existing generations and the prior active selector.
- Content-free receipts and explicit local-authoritative fallback.

## Files changed

- `docs/soul/MEMORY_PROJECTION_RECONCILIATION_A21_BRIEF.md`
- `lib/soul_core/memory_projection_reconciler.rb`
- `scripts/verify-memory-projection-reconciliation-a21.rb`
- this review
- `Makefile`
- `docs/CURRENT_STATE.md`

## Deterministic validation

The A21 verifier uses synthetic injected clients and performs no network,
process, database, service, canonical-memory, or persistent host operations. It
covers deterministic previews, stale-digest rejection, operation ordering,
successful activation, partial-write compensation, resumable existing
generations, selector failure, redaction, local fallback, and absence of direct
transport or canonical-mutation primitives.

Results: A21 passed 17 checks; A18 passed 23; A19 passed 23; A20 passed
18; A16 passed 19; A17 passed 18; Memory Observatory facade and Dashboard
passed 15 and 14; semantic Chat context passed 11. Ruby syntax and
`git diff --check` passed.

## Architecture finding

Qdrant supports atomic alias operations within Qdrant. FalkorDB provides
graph-specific query/copy/delete commands, but there is no transaction spanning
both products. Soul therefore selects a verified pair through one owner-private
local selector after both stores verify rather than claiming a distributed
atomic commit.

## Known weaknesses and next gate

- A21 contains no TLS transport adapter and cannot populate the deployed stores.
- The selector store is injected; its symlink-safe, fsync-and-rename owner-private
  implementation belongs in A22.
- Exact membership verification must use bounded database reads rather than
  trusting write responses or approximate counts.
- Live population requires a new preview containing current canonical/index
  digests and a separate exact confirmation.
- Remote generation retirement and rollback remain separate operations.

## Lifecycle, memory, and risk

- Lifecycle states: `blocked_for_human_review`, `complete`, `failed`.
- Canonical mutation: none.
- Projection mutation: injected only in deterministic tests.
- Memory keys: none added or changed.
- Risk: medium/high memory-policy coordinator; independently implemented and
  tested by the primary agent.

## Human review checklist

- [ ] Approve A21 generation and local-selector semantics.
- [ ] Confirm A22 may implement owner-private TLS transports and selector state.
- [ ] Confirm live population remains separately digest-bound.
