# Memory Rebuildable Projection A18 Review

Status: Candidate-complete for human review; no remote deployment performed.

## Implemented

- A human-reviewable Qdrant/FalkorDB projection architecture and privacy
  boundary.
- A deterministic closed projection contract over injected canonical-memory and
  approved-index sources.
- Qdrant points containing embeddings and minimal content-free metadata only.
- FalkorDB nodes containing lifecycle/provenance metadata and edges limited to
  canonical supersession and normalized exact duplicates.
- A content-free public receipt with counts, schemas, source/payload digests,
  dimensions, fallback behavior, and explicit non-authority.
- A deterministic synthetic verifier with no network, process, container,
  persistence, live private-memory, or remote-host access.

## Files changed

- `docs/soul/MEMORY_REBUILDABLE_PROJECTION_A18_BRIEF.md`
- `lib/soul_core/memory_projection_contract.rb`
- `scripts/verify-memory-rebuildable-projection-a18.rb`
- `docs/assessments/MEMORY_REBUILDABLE_PROJECTION_A18_REVIEW.md`
- `docs/CURRENT_STATE.md`
- `Makefile`

## Commands and results

```text
ruby -c lib/soul_core/memory_projection_contract.rb
ruby -c scripts/verify-memory-rebuildable-projection-a18.rb
make verify-memory-rebuildable-projection
make verify-memory-core-aware-worker
make verify-memory-autonomous-lifecycle
make verify-memory-retrieval-observatory
git diff --check
```

Results:

- A10: 38 checks passed.
- A11: 26 checks passed.
- A12: 20 checks passed.
- A13: 26 checks passed.
- A14: 16 checks passed.
- A15: 14 checks passed.
- A16: 19 checks passed.
- A17: 18 checks passed.
- A18: 23 checks passed.
- Retrieval Observatory: A0-A1, facade (15), and Dashboard (14) passed.
- Semantic Chat context: 11 checks passed.
- Private-memory separation: 12 checks passed.
- Ruby syntax and `git diff --check`: passed.

## Deterministic coverage

- stable payload and deterministic point identity;
- approved-only vector membership;
- graph visibility for candidate, approved, superseded, and deleted states;
- explicit supersession and exact-duplicate relationships only;
- no raw content in either projection payload or the public receipt;
- no vectors in the public receipt;
- vector dimension, missing-index, unknown-state, membership, content, and
  source-digest drift fail closed;
- no canonical mutation, network, or process execution.

## Lifecycle, memory, and risk

- Lifecycle states: `complete`, `failed`.
- Canonical memory mutation: none.
- Projection mutation: none in A18.
- Memory content: read only through injected synthetic fixtures during tests;
  live owner-private memory was not inspected.
- Risk: medium architecture boundary. A later deployment handles private memory
  embeddings across the LAN and therefore requires independent primary review.

## Known weaknesses and next gate

- Qdrant and FalkorDB versions, image/package provenance, Foundry resources,
  VMID/address, TLS, authentication, backup inclusion, firewall rules, and
  upgrade/rollback procedures are intentionally undecided here.
- The contract is not wired into Chat retrieval or the 3D Observatory.
- A19 must create an exact deployment plan, prove isolated reconciliation and
  fallback, and require a fresh digest-bound human installation confirmation.

## Human review checklist

- [ ] Confirm raw memory text should remain off the projection host.
- [ ] Confirm Qdrant may store embeddings plus the bounded metadata listed in
      the A18 brief.
- [ ] Confirm FalkorDB relationships remain non-authoritative evidence.
- [ ] Confirm Foundry remains the intended A19 host.
- [ ] Approve, revise, or reject drafting the A19 deployment candidate.
