
# Execution History Controls

Phase 51 adds execution history controls.

## Purpose

Soul already records chat execution history.

This phase adds explicit controls for:

```text
list
export
clear
```

## Chat controls

```bash
ruby bin/soul chat "execution history"
ruby bin/soul chat "export execution history"
ruby bin/soul chat "export execution history jsonl"
ruby bin/soul chat "clear execution history"
ruby bin/soul chat "clear execution history confirm"
```

## Runtime paths

History:

```text
Soul/runtime/executions/chat_executions.jsonl
```

Exports:

```text
Soul/runtime/exports/execution_history/
```

## Safety posture

Clear is blocked unless the message includes:

```text
confirm
```

Exports remain local runtime data.

Do not commit runtime history or exports.
