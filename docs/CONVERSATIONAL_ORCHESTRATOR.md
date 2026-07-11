# Conversational Orchestrator

Phase 4 adds a bounded orchestration layer between chat input, deterministic skills, and the conversation provider.

## Decisions

The orchestrator chooses one of:

```text
direct_model
deterministic_passthrough
skill_only
skill_then_model
deterministic_fallback
```

## Informational skill synthesis

A conversational request such as:

```text
Can you check the system status and tell me what it means?
```

now follows:

```text
recognize relevant registered skill
-> execute deterministic system.status route
-> place the structured result in model context
-> ask the model to explain it naturally
-> return to the conversation
```

The model does not fabricate or directly execute the skill.

## Bounded skill chains

Phase 4 permits at most two informational steps per turn:

```text
SOUL_CONVERSATION_MAX_TOOL_STEPS=2
```

The hard maximum is two even if a larger value is configured.

Current synthesis-capable tools:

```text
system.status
assistant-skill-catalog
downloads.inspect
downloads.cleanup_plan
execution.history.summary
```

These tools are read-only or review-only.

## Deterministic boundaries

The following remain deterministic passthroughs:

```text
approval issuance
approval listing
approval revocation
Downloads move dry-run
Downloads move-to-trash
history mutation controls
adapter registry controls
identity responses
```

The model cannot convert a conversational sentence into mutation authority.

## Relevance controls

Tool selection requires subject-specific patterns or a mapped deterministic intent.

Example:

```text
What Ruby optimizations would improve Soul's codebase?
```

does not match Downloads cleanup merely because both subjects might use the word “cleanup.”

No tool use is a valid orchestration result.

## Failure behavior

If a deterministic skill succeeds but model synthesis fails:

```text
the deterministic result is preserved
the synthesis failure is stated
no successful model response is invented
conversation state remains available
```

## Future boundaries

Phase 4 records memory-request and artifact-request signals, but does not implement durable memory or artifact creation.

Those belong to later phases:

```text
Phase 5: layered memory
Phase 7: artifact-aware conversation
```
