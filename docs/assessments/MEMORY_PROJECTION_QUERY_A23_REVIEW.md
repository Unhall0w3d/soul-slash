# Memory Projection Query A23 Review

Status: candidate-complete and foreground live-qualified; not routed into Chat
or Voice.

## Implemented

- Bounded Qdrant nearest-neighbor query against only the active generation.
- Bounded FalkorDB read-only lookup of explicit supersession and exact-duplicate
  relationships around returned identifiers.
- Exact selector freshness checks against the current content-free A18 contract.
- Cryptographic binding of all selected generation/resource names to the
  current payload digest.
- Validation of every remote identifier, lifecycle state, source digest,
  content digest, layer, source kind, score, relation, and local endpoint.
- Canonical local join for excerpts and source evidence; remote content is
  ignored even if a server attempts to return it.
- Existing local approved-memory retrieval as the fail-closed fallback for all
  projection, embedding, validation, TLS, or database failures.
- One explicit foreground diagnostic CLI and Make target.

## Files changed

- `docs/soul/MEMORY_PROJECTION_QUERY_A23_BRIEF.md`
- `lib/soul_core/memory_projection_query_service.rb`
- `lib/soul_core/memory_projection_transports.rb`
- `scripts/soul-memory-projection-query`
- `scripts/verify-memory-projection-query-a23.rb`
- this review
- `Makefile`
- `docs/CURRENT_STATE.md`

## Deterministic validation

The A23 verifier uses injected stores, selectors, embeddings, transports, and
fallback retrieval. It covers success, canonical local joining, remote-content
rejection, generation binding, explicit relationships, stale selectors,
misbound resources, unknown identifiers, out-of-scope relationships, remote
failure, strict input limits, malformed empty responses, content-free fallback
reasons, no mutation/background behavior, Qdrant query shape, and FalkorDB
read-only compact-value decoding.

Result: A23 passed 23 checks. A18 through A22 and the existing local retrieval,
Observatory, and semantic Chat verifiers remain required integration checks.

Independent Luna High review identified selector/resource binding,
relationship-scope, malformed-response, invalid-limit, and CLI fallback gaps.
All five were corrected before candidate publication and covered by new
negative fixtures where applicable.

## Live qualification

One foreground query reached the active generation over verified TLS. Qdrant
returned five identifiers and scores, each excerpt was joined from the local
ledger, and FalkorDB returned one explicit `EXACT_DUPLICATE` relationship. No
canonical, projection, or selector mutation occurred.

After the independent-review repairs, a private positive-control query returned
the exact canonical memory as rank 1. The lower-ranked results also confirmed
why an abstention or hybrid-ranking qualification is required before ordinary
Chat/Voice routing. No private query text, memory content, identifier, or score
was copied into the repository.

The query also demonstrated that raw vector top-N output can be weakly relevant
when canonical memory lacks a strong answer. A23 intentionally labels these
scores as untrusted ranking evidence. Chat/Voice integration should not occur
until a later slice compares local hybrid ranking, remote semantic candidates,
abstention thresholds, and query-instruction behavior on a reviewed corpus.

## Lifecycle, memory, and risk

- Lifecycle states: `complete`, `awaiting_input`, `failed`.
- Canonical mutation: none.
- Remote mutation: none.
- Selector mutation: none.
- New memory keys: none.
- Risk: medium/high retrieval-quality and memory-authority boundary.

## Human review checklist

- [ ] Approve A23 remote ranking plus canonical-local-join semantics.
- [ ] Confirm local fallback should remain mandatory.
- [ ] Confirm Chat/Voice routing remains deferred pending comparative quality
  and abstention qualification.
