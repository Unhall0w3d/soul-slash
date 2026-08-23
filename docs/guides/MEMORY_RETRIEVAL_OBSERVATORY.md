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
- a bounded content-free constellation and lifecycle map of memory metadata;
- the retrieval index profile, digest binding, dimensions, freshness, and
  availability;
- one explicit diagnostic query with bounded result excerpts and score
  components.

Refresh and diagnostic query are authenticated foreground reads. They do not
poll, start a worker, or change memory. Use the existing reviewed Chat memory
commands for proposals, approval, supersession, and forgetting.

The constellation projects at most 240 memory nodes and 400 explicit duplicate
or supersession links. Node placement is deterministic and may be switched
between layer-oriented constellation and lifecycle layouts. Hover or keyboard
focus reveals only the memory ID, lifecycle state, layer, provenance kind, and
timestamp. The graph does not expose memory content, infer new relationships,
or grant authority.

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
The embedding runtime must be started and stopped separately in the foreground
for the approved task; this feature does not install or enable persistent
runtime infrastructure.

With the four local embedding variables set, `make
memory-retrieval-evaluate-live` runs the same public synthetic query corpus
against that one foreground endpoint. It does not inspect private memory or
select a winner automatically.

## Ordinary Chat context

Ordinary Chat now has a fail-safe semantic admission path. It uses semantic
results only when retrieval reports a fresh compatible `hybrid` index. The
index contributes IDs only: Soul re-reads each record from the canonical ledger
and requires its current state to remain `approved` before including its content
in the system prompt. Existing always-include and same-conversation memories
remain preferred.

If the endpoint is absent, the index is stale or incompatible, the query falls
back, or any local request fails, Chat receives the same approved-only lexical
context it used before A3. Chat does not rebuild the index or start the embedding
runtime automatically.

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
admission mechanics. It does not install an always-on Ollama service,
automatically load a model, rebuild an index, or alter Core lifecycle. Without
an available compatible endpoint, Chat continues to fail safely to
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
