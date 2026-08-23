# Memory Retrieval and Observatory

Soul keeps durable conversation memory in one append-only, owner-reviewed
ledger. The Memory Observatory adds a read-only view and an optional disposable
retrieval index; neither can create, approve, supersede, delete, or authorize
anything.

## What the Observatory shows

Open **Administration → Memory Observatory** to inspect:

- record counts by lifecycle state, layer, and source kind;
- up to 100 recent append-only lifecycle events;
- exact-content duplicate observations and explicit supersession links;
- the retrieval index profile, digest binding, dimensions, freshness, and
  availability;
- one explicit diagnostic query with bounded result excerpts and score
  components.

Refresh and diagnostic query are authenticated foreground reads. They do not
poll, start a worker, or change memory. Use the existing reviewed Chat memory
commands for proposals, approval, supersession, and forgetting.

## Retrieval authority

`ConversationMemoryStore` remains canonical. Only records whose current state
is `approved` are eligible for the index. The index lives beneath ignored
owner-private memory state and is exactly rebuildable from the ledger.

Every index records its source digest, payload digest, embedding profile,
dimension, entry count, and generation time. If it is missing, stale,
malformed, symlinked, digest-invalid, or profile-incompatible, a query falls
back to approved-only lexical retrieval. Similarity is recall evidence, not a
truth or authorization decision.

## Foreground commands

```bash
make memory-retrieval-evaluate
make memory-retrieval-evaluate-live
make memory-retrieval-status
make memory-retrieval-rebuild
make memory-retrieval-query MEMORY_QUERY='approved retrieval preferences'
make verify-memory-retrieval-observatory
```

`memory-retrieval-evaluate` uses only a synthetic public corpus and
deterministic fixture vectors. `memory-retrieval-rebuild` performs one bounded
atomic replacement and exits. With no embedding configuration, it builds a
lexical index.

## Optional local embeddings

Semantic retrieval is opt-in and requires one explicitly configured loopback
HTTP endpoint. Soul does not download a model, start a service, switch Cores,
or contact a cloud provider.

```bash
export SOUL_MEMORY_EMBEDDING_ENDPOINT=http://127.0.0.1:11434/api/embed
export SOUL_MEMORY_EMBEDDING_PROFILE=qwen3-embedding:0.6b
export SOUL_MEMORY_EMBEDDING_DIMENSIONS=1024
export SOUL_MEMORY_EMBEDDING_PROTOCOL=ollama
make memory-retrieval-rebuild
```

The endpoint must be loopback HTTP, inputs are capped at 8,000 characters,
batches at 64, dimensions at 1,024, and responses and timeouts are bounded.
The embedding runtime must be started and stopped separately in the foreground
for the approved task; this feature does not install or enable persistent
runtime infrastructure.

With the four local embedding variables set, `make
memory-retrieval-evaluate-live` runs the same public synthetic query corpus
against that one foreground endpoint. It does not inspect private memory or
select a winner automatically.

## Current qualification boundary

The deterministic A0 corpus and A1/A2 mechanics qualify ranking, abstention,
fallback, privacy, application-facade, and Dashboard behavior. Choosing a
production embedding profile and allowing derived semantic results into normal
Chat context require a separate controlled live comparison and Operator review.
