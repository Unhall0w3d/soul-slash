
# Chat Interface Foundation

Phase 41 introduces Soul's first terminal chat surface.

## Commands

```bash
ruby bin/soul chat
ruby bin/soul chat "what skills do you have?"
ruby bin/soul chat --list
ruby bin/soul chat --show <chat_id>
ruby bin/soul chat --search <text>
ruby bin/soul chat --pin <chat_id>
ruby bin/soul chat --unpin <chat_id>
```

## Storage

Initial chat storage is local JSON/JSONL:

```text
Soul/runtime/chats/
```

This is development storage, not the final long-term database model.

## Behavior

The first responder is deterministic.

It can answer early Soul-specific prompts such as:

```text
what skills do you have?
who are you?
what should we build next?
status
```

## Boundaries

This phase does not:

```text
call an LLM
execute skills automatically
create SQLite storage
create a web UI
create voice input/output
run background services
send data to cloud providers
```

## Purpose

This gives Soul a mouth before giving it more hands.
