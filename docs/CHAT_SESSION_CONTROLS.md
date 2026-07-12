
# Chat Session Controls

Phase 42 hardens the first terminal chat surface.

## Commands

```bash
ruby bin/soul chat
ruby bin/soul chat "message"
ruby bin/soul chat --resume <chat_id> "message"
ruby bin/soul chat --list
ruby bin/soul chat --recent
ruby bin/soul chat --show <chat_id>
ruby bin/soul chat --search <text>
ruby bin/soul chat --pin <chat_id>
ruby bin/soul chat --unpin <chat_id>
ruby bin/soul chat --rename <chat_id> --title "new title"
ruby bin/soul chat --delete <chat_id>
```

## Improvements

```text
cleaner chat list output
recent chat view
resume chat with a new message
show full transcript
basic transcript search
pin/unpin chats
rename chats
delete chats
message counts
pin ordering
```

## Storage

Still local JSON/JSONL:

```text
Soul/runtime/chats/
```

This remains development storage. SQLite comes later.

## Boundaries

Phase 42 does not:

```text
call an LLM
execute skills automatically
create SQLite storage
create a web UI
create voice I/O
start background services
```

## Result

Soul's terminal chat surface is now usable enough to support the next layer: assistant-facing skill descriptions and intent routing.
