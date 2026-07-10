
# Soul Chat Data Model

This document defines the initial direction for Soul chat/session persistence.

The first implementation may be simpler than this model, but it should not contradict it.

## Storage

Initial storage should use SQLite.

Development path:

```text
Soul/runtime/soul.db
```

Long-term user path:

```text
~/.local/share/soul/soul.db
```

## chats

Represents a conversation.

Fields:

```text
id
title
project_id
created_at
updated_at
pinned
pin_order
archived
summary
last_message_at
metadata_json
```

## messages

Represents one user, assistant, system, or tool message.

Fields:

```text
id
chat_id
role
content
created_at
token_estimate
skill_invocation_id
metadata_json
```

Roles:

```text
user
assistant
system
skill
tool
error
```

## projects

Represents a workspace or topic grouping.

Fields:

```text
id
name
description
created_at
updated_at
metadata_json
```

## skill_invocations

Tracks planned and executed skill calls.

Fields:

```text
id
chat_id
message_id
skill_id
status
requires_confirmation
confirmed_at
started_at
completed_at
input_json
output_json
error_text
metadata_json
```

Statuses:

```text
planned
awaiting_confirmation
running
complete
blocked
failed
cancelled
```

## assistant_decisions

Tracks routing decisions for auditability.

Fields:

```text
id
chat_id
message_id
intent
decision
confidence
reason
created_at
metadata_json
```

Example decisions:

```text
respond_directly
ask_clarification
plan_skill
run_read_only_skill
request_confirmation
generate_codex_handoff
```

## artifacts

Tracks generated files or local artifacts referenced in chats.

Fields:

```text
id
chat_id
message_id
path
kind
created_at
description
metadata_json
```

## search

Use SQLite FTS5 over:

```text
messages.content
chats.title
chats.summary
projects.name
projects.description
```

## Privacy and locality

Chat data should remain local unless the user deliberately exports or syncs it.

Soul should not silently upload transcripts to a model provider.

If a cloud provider is used, the exact sent context should be inspectable.
