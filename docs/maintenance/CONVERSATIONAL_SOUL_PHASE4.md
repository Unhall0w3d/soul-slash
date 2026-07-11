# Conversational Soul Phase 4

Milestone:

```text
Conversational Soul
```

Phase:

```text
4
```

## Purpose

Add bounded conversation-aware skill selection and result synthesis while preserving deterministic approval and mutation controls.

## Added

```text
lib/soul_core/conversation_tool_catalog.rb
lib/soul_core/conversation_orchestration_contract.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversational_orchestrator_assessor.rb
docs/CONVERSATIONAL_ORCHESTRATOR.md
scripts/verify-conversational-orchestrator-phase4.rb
```

## Updated

```text
lib/soul_core/conversation_runtime.rb
lib/soul_core/conversation_state_store.rb
lib/soul_core/app.rb
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/MILESTONES.md
CHANGELOG.md
```

## New assessment

```zsh
ruby bin/soul assess conversational-orchestrator
ruby bin/soul assess conversational-orchestrator --json
```

## Behavioral change

Soul can now invoke bounded read-only or review-only skills during conversation, provide their deterministic results to the configured conversation model, and return a synthesized response.

Approval and mutation controls remain deterministic.

## Deferred

```text
durable layered memory
artifact creation and inbox delivery
model-proposed arbitrary tool calls
write-capable model orchestration
open-ended autonomous loops
```
