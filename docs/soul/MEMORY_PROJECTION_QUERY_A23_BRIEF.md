# Memory Projection Query A23 Brief

Status: implementation candidate. Chat and Voice routing remain unauthorized.

## Objective

Add one bounded foreground read path that uses the active Qdrant generation to
rank canonical memory identifiers and the paired FalkorDB generation to return
only explicit reviewed relationships.

## Authority and privacy

- The local conversation-memory ledger remains the only content authority.
- Qdrant returns identifiers, scores, and content-free metadata. Soul rejects
  unknown, duplicate, non-approved, stale-digest, or metadata-mismatched hits.
- Memory excerpts and source evidence are joined only from the current local
  canonical record after validation.
- FalkorDB returns only `SUPERSEDED_BY` and `EXACT_DUPLICATE` edges whose
  endpoints still exist locally. It cannot introduce inferred relationships.
- Remote data is untrusted derived evidence and cannot mutate, promote, delete,
  rewrite, or authorize canonical memory.

## Freshness and fallback

Before every query, Soul rebuilds the content-free A18 contract in memory and
requires the active selector's payload and source digests to match it exactly.
The generation, Qdrant collection, and FalkorDB graph suffixes must also match
the current payload digest; independently valid resource names are insufficient.
Missing or stale selector state, local-index drift, embedding failure, TLS or
database failure, malformed responses, or validation failure routes to the
existing approved local retrieval service. Remote failure never blocks ordinary
memory retrieval.

## Bounds

- Query text: at most 200 characters.
- Results: 1..20.
- Relationships: at most 40.
- One local embedding input and one bounded remote query per store.
- Existing transport timeouts and response-size limits remain in force.

No Dashboard, Chat, Voice, timer, daemon, retry, Core transition, selector
mutation, remote write, generation rollback, or retirement is added.
