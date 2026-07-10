
# Phase 51 Execution History Controls

Phase 51 adds local controls for chat execution history.

## Added / changed

```text
lib/soul_core/chat_execution_history.rb
lib/soul_core/chat_execution_history_assessor.rb
lib/soul_core/chat_responder.rb
docs/EXECUTION_HISTORY_CONTROLS.md
scripts/verify-execution-history-controls-phase51.rb
```

## Scope

This phase adds:

```text
history export to JSON
history export to JSONL
blocked unconfirmed clear
confirmed clear
chat-side export and clear commands
runtime export path
```

This phase does not add:

```text
cloud sync
history encryption
history filtering by skill
history pruning by age
background jobs
```

## Result

Soul can now list, export, and explicitly clear local chat execution history.
