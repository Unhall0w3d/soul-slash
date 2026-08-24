# Memory Historical Chat Backfill A15 Review

## Candidate

A bounded foreground reconciliation path from persisted historical Soul chats
into the existing A11 immutable observation ledger.

## Files

- `lib/soul_core/memory_historical_chat_backfill_service.rb`
- `lib/soul_core/conversation_observation_store.rb`
- `scripts/soul-memory-historical-backfill`
- `scripts/verify-memory-historical-chat-backfill-a15.rb`
- A15 brief, Make targets, and current-state documentation

## Deterministic evidence

The synthetic review fixture proves that preview selects only complete,
uncaptured exchanges; archived chats remain eligible; receipts contain no
private text; wrong confirmation and scope drift block; exact execution appends
to the same valid observation chain; replay reaches `no_work`; and symlinked
transcripts fail closed.

Commands:

```text
make verify-memory-historical-chat-backfill
make verify-memory-conversation-observation-capture
make verify-memory-observation-derivation
make verify-memory-lifecycle-admission
make verify-memory-live-qualification
git diff --check
```

## Boundaries

- Risk: medium; owner-private append-only observation mutation.
- Model and lifecycle authority: none.
- Background or persistent execution: none.
- Memory content in receipts: none.
- Existing chats and canonical memory are never rewritten.

## Owner-private preview

The live foreground preview completed without mutation on 2026-08-24. It found
15 uncaptured complete exchanges across 2 chats (30 messages), dated from
2026-08-05 through 2026-08-17. The receipt exposed only counts, timestamps, the
scope digest, and the exact confirmation requirement. Execute remains pending
the explicit `BACKFILL_HISTORICAL_CONVERSATIONS` gate.

## Known weakness and human gate

The candidate fails closed if the retained corpus exceeds 500 chats or 20,000
messages and would then require a future narrowing control rather than silently
skipping history. Owner-private live preview and execution remain a separate
human review step.
