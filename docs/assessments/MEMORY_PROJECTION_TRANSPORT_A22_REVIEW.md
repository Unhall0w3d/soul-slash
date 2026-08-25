# Memory Projection Transport A22 Review

Status: candidate implementation; no remote projection generation executed.

## Implemented

- Verified HTTPS transport for Qdrant with owner-private CA and API key.
- Verified Redis TLS transport for FalkorDB with RESP authentication.
- Fixed connection/read timeouts, request/response bounds, record limits, and
  write batches capped at 128 commands.
- Exact Qdrant point/vector/payload and FalkorDB node/label/field/edge readback.
- Symlink-safe, owner-private active selector with file and directory fsync and
  atomic same-directory replacement.
- One foreground `preview` / digest-bound `execute` command over the canonical
  ledger and reviewed local embedding index.
- Explicit local-authoritative fallback with no retrieval routing change.

## Files changed

- `docs/soul/MEMORY_PROJECTION_TRANSPORT_A22_BRIEF.md`
- `lib/soul_core/memory_projection_transports.rb`
- `scripts/soul-memory-projection-reconcile`
- `scripts/verify-memory-projection-transport-a22.rb`
- this review
- `Makefile`
- `docs/CURRENT_STATE.md`

## Deterministic validation

The A22 verifier uses only temporary selector state and injected in-memory
Qdrant/FalkorDB transports. It does not access credentials, canonical memory,
the network, remote services, or the deployed projection guest. It covers
selector replacement and nested-symlink rejection, exact Qdrant and FalkorDB
verification, wait-for-commit Qdrant writes, read-only FalkorDB verification,
bounded TLS work, exact confirmation syntax, private-file protections, and the
absence of shell/background/retry behavior.

The foreground live preview was also invoked. It failed closed before network
access because the reviewed local embedding index source digest no longer
matches the canonical approved-memory set. No remote or selector mutation
occurred. A fresh reviewed index rebuild is therefore a prerequisite to the
next projection preview.

## Known weaknesses and next gate

- The exact deployed FalkorDB compact response shape and Qdrant TLS operations
  remain unqualified until the first digest-bound execution.
- A fresh approved-memory index must be built with the reviewed local embedding
  profile before an A22 plan digest can be produced.
- Live population still requires review of that fresh plan and its exact
  `REBUILD_MEMORY_PROJECTION` confirmation.
- Remote retrieval routing, generation rollback/retirement, timers, retries,
  and automatic Core transitions remain outside this slice.

## Lifecycle, memory, and risk

- Lifecycle states: `blocked_for_human_review`, `complete`, `failed`.
- Canonical mutation: none.
- Derived local mutation: selector activation only after dual exact verification.
- Remote mutation: immutable generation creation only after exact confirmation.
- Memory keys: none added or changed.
- Risk: high memory-policy and credential-bearing transport boundary; primary
  implementation and independent deterministic validation are required.

## Human review checklist

- [ ] Approve the A22 transport, selector, and foreground command boundary.
- [ ] Refresh and review the approved-memory embedding index.
- [ ] Review the resulting A22 projection plan and exact digest.
- [ ] Authorize the first live immutable-generation population separately.
