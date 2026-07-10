
# Chat Execution History

Phase 50 adds chat execution history.

## Purpose

Soul can now execute read-only chat skills through the gate.

This phase records those gate results locally.

## Runtime path

```text
Soul/runtime/executions/chat_executions.jsonl
```

This path must remain gitignored.

## Recorded fields

```text
timestamp
source
message
skill_id
status
ok
executed
risk
confirmation_required
exit_status
blocked_by
```

## Chat command

```bash
ruby bin/soul chat "execution history"
```

## Safety posture

The history file is local runtime state.

It may contain prompts, skill IDs, timestamps, and execution metadata.

Do not commit it.
