# Chat Progress Summaries A1 Brief

Status: human-approved for implementation on 2026-07-27

## Outcome

Make one accepted Chat exchange feel immediate and legible without inventing
background work:

- render the submitted user message before Soul finishes;
- change its provisional state to accepted only after the server records it;
- maintain one concise progress summary derived from real lifecycle events;
- recover that summary when the Operator navigates away and returns or reloads
  after a body-stream disconnect; and
- remove the summary cleanly when the terminal assistant message is present.

## Architecture

Progress belongs to the existing application request receipt ledger. A
`chats.send` reservation may append bounded progress events until it reaches its
existing terminal `complete` or `failed` state.

The typed read-only `chats.progress` operation may return active Chat receipts
for one conversation or the bounded active set. It does not start, retry,
cancel, or authorize work.

The Dashboard keeps at most one visible working card per active conversation.
It may refresh progress when loading the conversation or its list. It must not
poll, open a watcher, or create a second execution path.

## Truth and privacy boundary

- State identifiers are allowlisted, bounded strings.
- Summaries are supplied only by deterministic lifecycle emitters already
  inside the accepted operation.
- Summary text is capped at 240 UTF-8 characters.
- Receipts store no user prompt, model response, research payload, secret,
  path, or tool output.
- A progress event is operational state, not durable conversational memory.
- A terminal receipt can never return to an active state.
- A stale incomplete receipt stops appearing as active after four hours.

## Interaction behavior

1. The Operator submits one message.
2. The Dashboard renders `You · sending` immediately.
3. The server reserves the request and records the user message.
4. The first `received` event changes the visible label to `You`.
5. Later real events update one Soul working card in place.
6. Navigation may detach the visual surface, but selecting the conversation
   reads the active receipt and reconstructs the same one-card summary.
7. Terminal completion replaces provisional UI with canonical stored messages.
8. If transport delivery fails after acceptance, the Dashboard checks the
   receipt once and reports continued bounded work honestly. It does not
   restore an already-accepted message as an unsent draft.

## Lifecycle

This slice observes the existing Chat lifecycle:

```text
reserved
→ received
→ context / planning / inspecting / researching / drafting / synthesizing
→ reviewing / finalizing
→ complete / failed / blocked_for_human_review / awaiting_input
```

It adds no new execution lifecycle and no continuation after the accepted
request reaches its owning terminal state.

## Deterministic acceptance

- Receipt progress survives a new store instance.
- Active progress can be queried by conversation and as a bounded list.
- Terminal receipts disappear from active progress and cannot be reopened.
- Invalid states and oversized or invalid UTF-8 summaries fail closed.
- Submitted text renders before the streaming request begins.
- `received` marks the provisional user message accepted.
- One working card is updated rather than appended repeatedly.
- Selecting a conversation reconstructs active progress from the typed API.
- Final reconciliation changes only the conversation that completed.
- A post-acceptance transport failure performs one status reconciliation and
  does not claim the operation failed while its receipt is active.
- No timer, polling loop, WebSocket, EventSource, worker, daemon, service, or
  scheduler is added.

## Explicitly deferred

- Unified durable progress for standalone Music Studio, Visual Studio, Backup,
  and maintenance operations.
- Automatic follow/reconnect after a browser disconnect.
- Concurrent Chat sends across conversations.
- Interruption-aware Voice Presence narration of intermediate progress.
- Model-generated progress prose.
