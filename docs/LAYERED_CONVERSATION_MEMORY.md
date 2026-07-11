# Layered Conversation Memory

Phase 9 introduces a bounded memory foundation for the Conversational Soul runtime.

## Memory layers

Working memory remains the current chat context, session summary, and earlier-turn digest. Durable records use four explicit layers:

- `project` — stable project facts, decisions, conventions, and current direction.
- `preference` — explicitly approved user interaction or output preferences.
- `episodic` — reviewed facts about a particular event, session, or completed step.
- `semantic` — reviewed lessons, rules, and durable factual knowledge.

The layer is metadata, not a claim of truth. Every durable record also carries provenance, confidence, status, and an audit trail.

## Lifecycle

Records begin as `candidate`. They do not enter model context until an explicit approval transition is recorded.

Supported states are:

- `candidate`
- `approved`
- `superseded`
- `deleted`

Supersession and deletion are logical transitions in an append-only JSONL ledger. They remove records from active retrieval without erasing the audit history.

## Context retrieval

Only active `approved` records are eligible for conversational context. Retrieval is bounded and relevance-based. The rendered context preserves:

- memory ID
- layer
- confidence
- source kind and reference

Candidate, superseded, and deleted records are never presented to the model as conversational facts.

## Safety boundary

This phase does not add automatic memory extraction or conversational write commands. Models cannot promote their own output into durable memory. Human-reviewed mutation controls belong in a later Phase 9 slice.

## Storage

The default ledger is:

```text
Soul/memory/conversation_memory.jsonl
```

The runtime directory remains local and should not be committed.
## Reviewed conversation controls

The next Phase 9 slice exposes deterministic controls for explicit user-directed mutation:

- `remember that <content>` creates a candidate;
- `approve memory <id>` promotes a reviewed candidate;
- `list memory` and `show memory <id>` inspect records;
- supersession and forgetting require exact IDs and literal confirmation;
- all transitions remain append-only and preserve audit history.

Questions that merely ask about an earlier conversation are not interpreted as memory writes.
See `docs/REVIEWED_CONVERSATION_MEMORY_CONTROLS.md` for the complete command contract.

