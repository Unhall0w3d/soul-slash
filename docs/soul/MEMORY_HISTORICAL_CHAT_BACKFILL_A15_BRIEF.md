# Memory Historical Chat Backfill A15 Brief

## Status

Human-authorized implementation scope, 2026-08-24.

## Objective

Reconcile complete persisted Soul chat exchanges created before A11 capture was
deployed into the same immutable owner-private observation chain. Backfill
creates source evidence only; it does not derive, admit, retrieve, consolidate,
or delete memory.

## Authority and flow

- One explicit foreground preview selects the oldest uncaptured complete
  user-to-assistant exchanges from persisted active or archived chats.
- The preview exposes counts, timestamps, an exact scope digest, and a fixed
  confirmation phrase without exposing message content or chat identities.
- Execute re-reads every source file and requires the unchanged digest and exact
  confirmation before appending through the existing A11 observation store.
- Existing observation identities are skipped. Repeated invocations advance
  through remaining history and eventually report `no_work` without requiring
  confirmation.
- Incomplete turns, deleted transcripts, unsupported role sequences, and chats
  beyond the current bounded batch are not manufactured or inferred.

## Bounds

- At most 500 chat records and 20,000 messages are inspected per invocation.
- At most 50 complete exchanges from at most 25 chats, or 100 messages, are
  appended per execution.
- Each transcript retains the existing 10,000-message ChatStore scan ceiling;
  every message also retains A11's content and identity limits.
- Chat roots and transcript entries must remain regular, non-symlinked paths
  beneath the project.
- Partial execution is safe to retry because exact A11 identities are
  idempotent and the canonical observation ledger is append-only.

## Non-goals

- No model invocation, proposal derivation, lifecycle admission, Core switch,
  remote database, scheduler, worker, timer, watcher, daemon, or retry loop.
- No raw content in receipts, Git, logs, or public documentation.
- No physical purge, chat rewrite, retention change, canonical-memory mutation,
  Qdrant/FalkorDB projection, or 3D visualization change.

## Acceptance

- Previously captured exchanges are not duplicated.
- Archived chats remain eligible; incomplete exchanges remain excluded.
- Scope drift and wrong confirmation block before append.
- Exact execution appends one ordered observation pair per selected exchange.
- A completed backfill reports no work, and the full A11 chain remains valid.
- Unsafe paths and malformed or oversized histories fail closed.
