# Reviewed Conversation Memory Controls

This Phase 9 slice exposes the layered memory ledger through deterministic conversation controls.

## Safety model

A request to remember something creates a `candidate`. It does not become trusted conversational context until the user explicitly approves it.

Supersession and forgetting are append-only lifecycle events:

- supersession requires an approved replacement record and literal `confirm`;
- forgetting requires the exact memory ID and literal `confirm`;
- both operations remove records from active retrieval without erasing audit history;
- this surface does not physically purge ledger events.

The model does not parse, approve, or execute these controls. The conversation orchestrator routes them to deterministic code.

## Commands

Propose memory:

```text
remember that Soul uses focused ZIP overlays
remember this as preference: Use compact technical explanations
remember project: Phase 9 reviewed controls are in progress
propose memory as semantic: Durable memory requires explicit approval
```

Review and approve:

```text
list memory candidates
show memory <id>
approve memory <id>
approve memory latest
```

Inspect active memory:

```text
what do you remember?
list approved memory
list project memory
show memory <id>
```

Maintain approved memory:

```text
supersede memory <old-id> with <replacement-id>
supersede memory <old-id> with <replacement-id> confirm
forget memory <id>
forget memory <id> confirm
```

The first supersede or forget form is a preview and performs no mutation.

## Non-command recall

Questions such as `Do you remember when we discussed overlays?` are not treated as write commands. Only the bounded command forms are intercepted.

## Provenance

Conversation proposals retain:

- `source.kind = conversation_request`
- the originating chat ID when available
- confidence `1.0` for the direct user instruction
- explicit-user-request tags
- append-only lifecycle events
