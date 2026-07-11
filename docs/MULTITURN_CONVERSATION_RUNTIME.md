# Multi-turn Conversation Runtime

Phase 3 introduces the first model-backed conversation loop.

It does not yet provide full tool orchestration. Explicit deterministic skills and approval-gated actions remain routed through the existing deterministic responder.

## Runtime flow

```text
user message stored in ChatStore
-> deterministic-route check
-> provider selection
-> bounded context construction
-> provider-neutral request envelope
-> local model response
-> normalized response envelope
-> assistant message stored in ChatStore
-> runtime conversation state updated
```

## Provider selection

Default behavior:

```text
SOUL_CONVERSATION_MODE=auto
```

In auto mode:

- registered deterministic actions stay deterministic
- ordinary conversation uses a configured provider
- local-only providers are preferred
- cloud providers are excluded unless explicitly allowed
- unavailable providers produce a truthful fallback

Select a provider:

```zsh
export SOUL_CONVERSATION_PROVIDER="local.openai_compatible"
```

Force deterministic behavior:

```zsh
export SOUL_CONVERSATION_MODE="deterministic"
```

Force model conversation for non-action messages:

```zsh
export SOUL_CONVERSATION_MODE="model"
```

Cloud conversation remains disabled unless:

```zsh
export SOUL_ALLOW_CLOUD_CONVERSATION="1"
```

## Context limits

Defaults:

```text
SOUL_CONVERSATION_MAX_MESSAGES=20
SOUL_CONVERSATION_MAX_CHARACTERS=16000
SOUL_CONVERSATION_MAX_OUTPUT_TOKENS=1024
SOUL_CONVERSATION_TIMEOUT_SECONDS=120
SOUL_CONVERSATION_TEMPERATURE=0.65
```

Older turns are condensed into a bounded transcript digest. This is context management, not durable memory.

## Runtime state

Per-chat runtime state is written under:

```text
Soul/runtime/conversation_state/
```

It records:

```text
turn count
active subject hint
active task hint
last response mode
last provider
fallback reason
context digest
context statistics
```

This state is generated, private, and gitignored.

## Safety boundary

The model cannot directly:

```text
execute shell commands
move files
approve actions
consume approval tokens
promote memory
change configuration
claim a tool ran
```

Known deterministic action requests continue through the existing skill, gate, approval, and history layers.

Full model-guided tool orchestration belongs to Phase 4.
