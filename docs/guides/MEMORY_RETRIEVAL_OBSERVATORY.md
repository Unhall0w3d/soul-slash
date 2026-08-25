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
- bounded content-free 2D constellation, 3D depth, and lifecycle views of
  memory metadata;
- the retrieval index profile, digest binding, dimensions, freshness, and
  availability;
- one explicit diagnostic query with bounded result excerpts and score
  components.

Refresh and diagnostic query are authenticated foreground reads. They do not
poll, start a worker, or change memory. Use the existing reviewed Chat memory
commands for proposals, approval, supersession, and forgetting.

The visualizer projects at most 240 memory nodes and 400 explicit duplicate or
supersession links. Placement is deterministic and may be switched among a
layer-oriented constellation, a lifecycle layout, and a rotatable Canvas depth
view. The 3D coordinates are presentation only: they do not claim semantic
distance or infer relationships. Hover or keyboard focus reveals only the
memory ID, lifecycle state, layer, provenance kind, and timestamp. The graph
does not expose memory content or grant authority.

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
make verify-memory-runtime-private-review
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
export SOUL_MEMORY_EMBEDDING_PROFILE=qwen3-embedding:0.6b-q8_0
export SOUL_MEMORY_EMBEDDING_DIMENSIONS=1024
export SOUL_MEMORY_EMBEDDING_PROTOCOL=ollama
export SOUL_MEMORY_EMBEDDING_QUERY_INSTRUCTION='Given an operator question, retrieve relevant approved memory that helps answer it'
make memory-retrieval-rebuild
```

The optional instruction is applied only to queries. Approved memory documents
remain unprompted when indexed. It must be one line and at most 500 characters.

The endpoint must be loopback HTTP, inputs are capped at 8,000 characters,
batches at 64, dimensions at 1,024, and responses and timeouts are bounded.
Installations that have not adopted A7 must start and stop the embedding
runtime separately in the foreground. A7 provides an optional exact inactive,
unenabled `soul-memory-embedding.service`; the selected-Core startup path and
confirmed Core transitions are its only lifecycle owners. The endpoint is
available on non-Free Cores, is stopped before Free Core activation, and keeps
the model demand-loaded for at most five idle minutes. Endpoint failure still
falls back to lexical retrieval.

With the four local embedding variables set, `make
memory-retrieval-evaluate-live` runs the same public synthetic query corpus
against that one foreground endpoint. It does not inspect private memory or
select a winner automatically.

## Ordinary Chat context

Ordinary Chat and Voice Presence share a fail-safe semantic admission path.
The active production policy uses projection evidence only as a gate and then
preserves canonical local ordering. Projection contributes IDs only: Soul
re-reads each record from the canonical ledger and requires its current state
to remain `approved` before including its content in the system prompt.
Existing always-include and same-conversation memories remain preferred.

If the endpoint or remote projection is absent, stale, incompatible, or fails,
the route returns to local hybrid or approved-only lexical retrieval. Chat does
not rebuild an index, rebuild a projection, or start an embedding runtime as
part of the query.

## Production route qualification

The active owner-private selector is
`projection_gate_local_order_a29` with a fixed projection threshold of `0.55`.
The earlier A25 `0.65` policy remains an immutable rollback target and retained
historical evidence. A29 corrected an environment-parity defect in the earlier
diagnostic command, then qualified the public `ApplicationFacade`
`memory.observatory.query` route against the reviewed private corpus: 11/11
positive hits, 5/5 negative abstentions, zero forbidden hits, and mean positive
reciprocal rank `0.881818` across 16 cases. Receipts withhold query and memory
content.

```bash
make memory-retrieval-policy-status
make memory-production-qualify
make verify-memory-production-closure
```

## Live profile qualification

`qwen3-embedding:0.6b-q8_0` was evaluated locally through Ollama on the public
11-query A4 corpus. With the reviewed query instruction and `hybrid-a4-v1`
ranking it produced recall `1.0`, precision `0.954545`, reciprocal rank `1.0`,
correct abstention for all `3/3` absent queries, mean latency `35.294 ms`, and
maximum latency `44.108 ms`. The lexical baseline measured recall `0.909091`,
precision `0.677273`, and reciprocal rank `0.78125`.

The first live run used the prior lexical-heavy ranking and an ambiguous
`spacecraft flight` fixture. It showed no gain over lexical retrieval. An
instruction-only experiment also showed no gain. Component inspection showed
that the shared weighting made semantic-only admission impractical while also
protecting lexical fallback. A4 therefore uses separate profiles:
`hybrid-a4-v1` favors semantic evidence when a compatible vector is present,
while `lexical-a1-v1` preserves the existing fallback. One terrain paraphrase
also admitted a related vehicle-flight memory, so the non-perfect precision is
reported rather than hidden.

## Current qualification boundary

A4 qualifies the local model, query format, ranking, abstention, and safe Chat
admission mechanics. A7 qualifies a 1024-token NVIDIA coexistence ceiling and
adds reviewed Core-aware endpoint lifecycle without automatic index rebuilding.
Without an available compatible endpoint, Chat continues to fail safely to
approved-only lexical context.

## Supervised private review

Memory Observatory also exposes two explicit A5 controls:

- **Refresh runtime evidence** reads only the configured loopback Ollama
  `/api/tags` and `/api/ps` endpoints. It can report installation and residency,
  but it cannot load a model or approve Core coexistence.
- **Run supervised private review** evaluates the fixed owner-private case file
  `Soul/private/memory/retrieval_review_cases.json` once in the foreground.

The case document is closed and versioned. It accepts no Dashboard-supplied
path, endpoint, model, or query:

```json
{
  "schema_version": "soul.memory_retrieval.private_review.v1",
  "cases": [
    {
      "id": "opaque_case_id",
      "query": "An owner-authored retrieval question",
      "expected_approved_memory_ids": ["memory_id"],
      "forbidden_approved_memory_ids": [],
      "result_limit": 5
    }
  ]
}
```

Results disclose case IDs, memory IDs, digests, and aggregate quality metrics;
they withhold query and memory content and are not written back to memory. A5
does not install a service, switch Cores, download a model, rebuild the index,
or declare a runtime placement safe.
