# Memory Projection Transport A22 Review

Status: implemented and live-qualified; first exact generation active.

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

The foreground live preview initially failed closed before network access
because the reviewed local embedding index source digest no longer matched the
canonical approved-memory set. The bounded embedding workflow rebuilt a fresh
33-entry index and produced an exact A22 plan. The Operator confirmed that plan
with `REBUILD_MEMORY_PROJECTION` and its digest.

Live qualification exposed two transport defects. Atelier did not resolve the
archive FQDN, so transport now uses the reviewed private IPv4 address and
verifies the certificate's exact IP SAN. FalkorDB compact replies wrap returned
values in typed cells, so the adapter now decodes that bounded response shape
before exact comparison. Each failed attempt compensated only the generation
it had created and left the selector absent. After both repairs, Qdrant verified
33 1024-dimensional points, FalkorDB verified 34 nodes and 5 explicit edges,
and selector activation completed for `generation_1ccc750e83aa93068398`.

## Known weaknesses and next gate

- The deployed Qdrant TLS path, FalkorDB RESP/TLS compact response path,
  dual-store exact verification, compensation, and initial selector activation
  are live-qualified.
- Future canonical-memory changes still require a fresh approved-memory index,
  a fresh projection preview, and a new exact confirmation.
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

- [x] Approve the A22 transport, selector, and foreground command boundary.
- [x] Refresh and review the approved-memory embedding index.
- [x] Review the resulting A22 projection plan and exact digest.
- [x] Authorize the first live immutable-generation population separately.
