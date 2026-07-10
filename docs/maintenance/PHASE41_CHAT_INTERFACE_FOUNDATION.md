
# Phase 41 Chat Interface Foundation

Phase 41 adds the first terminal chat interface.

## New files

```text
lib/soul_core/chat_store.rb
lib/soul_core/chat_responder.rb
lib/soul_core/chat_command.rb
docs/CHAT_INTERFACE_FOUNDATION.md
scripts/verify-chat-interface-foundation-phase41.rb
```

## Commands

```bash
ruby bin/soul chat
ruby bin/soul chat "message"
ruby bin/soul chat --list
ruby bin/soul chat --show <chat_id>
ruby bin/soul chat --search <text>
```

## Scope

This phase is intentionally modest.

It adds:

```text
local transcript storage
single-shot terminal chat
interactive terminal chat
deterministic Soul-aware responses
basic chat listing/search/show/pin flags
```

It does not add:

```text
LLM-backed conversation
natural-language skill routing
automatic skill execution
SQLite
web UI
voice
daemon mode
```

## Result

Soul can now be interacted with directly through a terminal chat surface.
