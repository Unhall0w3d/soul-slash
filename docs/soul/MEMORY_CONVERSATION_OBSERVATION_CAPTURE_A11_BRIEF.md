# Memory Conversation Observation Capture A11 Brief

Status: Operator-approved implementation scope, 2026-08-24

## Objective

Automatically retain every successfully completed local Soul conversation turn
as immutable source observations. Observations are evidence for later memory
derivation; they are not themselves approved memory and never enter ordinary
chat context merely because they were captured.

## Authority and storage

- Capture is local-only standing authority.
- The ignored owner-private memory root contains an append-only conversation
  observation ledger separate from operational chat files.
- Each successful exchange appends the exact persisted user and assistant
  messages as one bounded batch.
- The ledger records message, chat, request, role, interface, timestamp, content
  digest, prior-event digest, and event digest.
- Exact duplicate exchanges are idempotent. A reused message identity with
  different content fails closed.
- Observation content is never returned by status, integrity, or capture
  receipts.

The operational chat store remains the immediate conversation surface. The
canonical memory ledger remains the authority for derived lifecycle memory.
The Soul Vault remains the human-readable knowledge surface. A later lifecycle
slice may derive candidates from observations without rewriting them.

## Completion and failure behavior

- Capture runs in the foreground after both messages have been persisted and
  before the application request receipt is finalized.
- A capture failure does not erase or rewrite the already-completed chat turn.
  The chat response remains available and reports a bounded failed capture
  receipt so a later foreground reconciliation can repair the missing mirror.
- No retry, worker, watcher, timer, service, or background continuation is
  introduced.
- The operation is bounded to exactly two messages and a size-limited local
  ledger scan.

## Privacy and deletion

- Observation content remains in ignored owner-private storage and is never
  written to Git, logs, public receipts, or remote services.
- Credentials or secrets said in conversation are retained locally as raw
  observations but are not automatically promoted into memory.
- Existing delete-and-forget remains an explicit protected operation. It may
  remove operational chat files and logically tombstone derived memories, but
  this slice does not physically purge immutable observation history.
- Physical purge, export, retention-policy changes, and bulk rewriting remain
  separate human decisions.

## Explicit non-goals

- No automatic classification, promotion, demotion, consolidation, inference,
  embeddings, or speculative recall.
- No model invocation or Core switching.
- No live import of historical chats and no Soul Vault migration.
- No Qdrant, FalkorDB, Redis, container, listener, service, or scheduler.
- No Dashboard mutation or 3D visualization work.

## Acceptance

- A successful application chat exchange produces exactly two ordered source
  observations.
- Request replay does not duplicate observations.
- Content, identity, role, and ordering are preserved exactly.
- Capture receipts and integrity summaries expose counts and digests but no
  message content.
- Malformed, oversized, symlinked, escaped, duplicate-conflicting, or
  hash-invalid ledgers fail closed.
- Chat completion remains readable if capture fails after chat persistence.
- Existing chat, voice, memory retrieval, and private-memory tests remain
  compatible.
