# Conversational Orchestrator

Phase 4 adds a bounded orchestration layer between chat input, deterministic skills, and the conversation provider.

## Decisions

The orchestrator chooses among:

```text
direct_model
deterministic_passthrough
skill_only
skill_then_model
evidence_followup
capability_gap
deterministic_fallback
```

The final two decision types were added by the Phase 5 grounding repair.

## Informational skill synthesis

A conversational request such as:

```text
Inspect Downloads and tell me what it means.
```

follows:

```text
recognize relevant registered skill
-> execute deterministic route
-> persist evidence
-> place evidence in model context
-> validate synthesized claims
-> return to the conversation
```

The model does not fabricate or directly execute the skill.

## Bounded skill chains

At most two informational steps may run per turn.

Current synthesis-capable tools:

```text
assistant-skill-catalog
downloads.inspect
downloads.cleanup_plan
execution.history.summary
```

`system.status` is intentionally evidence-only because its scope is Soul runtime health, not host health.

## Deterministic boundaries

The following remain deterministic:

```text
approval issuance
approval listing
approval revocation
Downloads move dry-run
Downloads move-to-trash
history mutation controls
adapter registry controls
identity responses
Soul runtime status
persisted-evidence follow-ups
host capability-gap responses
```

## Relevance controls

Tool selection requires subject-specific patterns or a mapped deterministic intent.

No tool use is a valid orchestration result.

Invocation also requires a deterministic request shape. Soul distinguishes an
action request, an informational question, a terse explicit request, and
ordinary conversational context before domain-specific routing. Thus `I'm
reviewing system status` remains conversation while `Check system status` runs
the bounded collector. Asking whether an unavailable capability is supported
returns declared capability information; only a task-shaped request to use it
may enter the existing human-reviewed capability-gap lane.

Request shape does not authorize an operation, select a model capability, or
replace downstream validation and exact approval gates.

## Failure behavior

If a deterministic skill succeeds but synthesis fails or violates grounding:

```text
the deterministic evidence is preserved
the failure is stated
unsupported prose is rejected
conversation state remains available
```

## Future boundaries

Durable user/project memory begins after the grounded host-assessment capability is established.
