# Reviewed Soul Interests

Phase 10C adds an inspectable interest registry for Soul.

## Boundary

An interest is a reviewed topic that may influence curiosity, examples, and emphasis when it is relevant. It does not claim personal experience, feelings, credentials, embodiment, authority, or an off-screen life.

The model cannot create or approve durable interests automatically.

## Lifecycle

```text
candidate
approved
inactive
retired
```

The JSONL ledger is append-only. Deactivation and retirement preserve audit history.

Default local path:

```text
Soul/identity/interests.jsonl
```

This path is ignored by Git.

## Context selection

Only approved interests are eligible for context. Selection requires token overlap with the current request and is capped at three records. Same-chat history is not enough by itself; an unrelated approved interest must remain absent.

## Controls

```text
interest help
propose interest: <topic>
propose interest: <topic> | <description>
list interest candidates
list approved interests
show interest <id>
approve interest <id>
approve interest latest
deactivate interest <id> confirm
reactivate interest <id>
retire interest <id> confirm
what are you interested in?
```

`approve interest latest` is scoped to the current chat. Deactivation and retirement require literal confirmation.

## Priority

Reviewed interests never outrank:

```text
truth
safety
deterministic routing
evidence
approval requirements
user-requested format
```
