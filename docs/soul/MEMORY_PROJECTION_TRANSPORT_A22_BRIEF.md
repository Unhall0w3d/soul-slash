# Memory Projection Transport A22 Brief

Status: implementation candidate. Live population remains unauthorized until a
fresh A22 preview and exact digest are reviewed and confirmed.

## Objective

Implement the production TLS transports and owner-private active-generation
selector required by A21, then expose one bounded foreground preview/execute
command over the canonical local ledger and reviewed embedding index.

## Transport boundary

- Qdrant uses HTTPS REST with the owner-private CA and API key.
- FalkorDB uses Redis RESP over verified TLS with its independent password.
- Connections use fixed open/read timeouts, response-size limits, record bounds,
  and batches of at most 128 writes.
- No credential is placed in process arguments, logs, receipts, or Git.
- There is no retry of a write request. A later invocation may resume an exact
  immutable generation only after full verification.

## Exact verification

- Qdrant scrolls every point with vectors and payloads, reconstructs the closed
  A18 payload, and compares its canonical digest.
- FalkorDB reads every projected node field, label, and explicit edge, rebuilds
  the closed A18 payload, and compares its canonical digest.
- Approximate collection counts, service success responses, timestamps, and
  newest-name inference are insufficient.

## Selector

The active selector lives under owner-private memory state. Its path and every
existing parent component must not be symlinks. Replacement uses a same-directory
0600 temporary file, file fsync, atomic rename, and directory fsync. Selector
validation is closed to the A21 schema and digest-derived resource names.

## Live gate

`preview` may read current canonical memory and the reviewed local index, then
returns only counts, dimensions, digests, derived names, confirmation phrase,
and expected digest. `execute` requires `REBUILD_MEMORY_PROJECTION` and that exact
fresh digest. Any drift blocks before remote mutation.

No timer, daemon, watcher, background retry, automatic Core transition,
retrieval routing, rollback, retirement, or canonical-memory mutation is added.
