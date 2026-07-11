# Conversational Soul Phase 5

Milestone:

```text
Conversational Soul
```

Phase:

```text
5
```

## Purpose

Repair the evidence lifecycle exposed by manual Phase 4 testing.

## Added

```text
lib/soul_core/conversation_evidence_contract.rb
lib/soul_core/conversation_evidence_store.rb
lib/soul_core/conversation_grounding_policy.rb
lib/soul_core/grounded_evidence_lifecycle_assessor.rb
docs/GROUNDED_TOOL_EVIDENCE.md
docs/HOST_ENVIRONMENT_CAPABILITY_GAP.md
scripts/verify-grounded-evidence-lifecycle-phase5.rb
```

## Updated

```text
lib/soul_core/conversation_tool_catalog.rb
lib/soul_core/conversation_orchestration_contract.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_state_store.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/conversational_orchestrator_assessor.rb
lib/soul_core/app.rb
docs/CONVERSATIONAL_ORCHESTRATOR.md
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/MILESTONES.md
CHANGELOG.md
```

## Behavioral changes

```text
system.status returns scoped deterministic evidence
tool evidence persists across turns
follow-up questions reuse the evidence
host-environment requests expose a capability gap
unsupported synthesized environmental claims are rejected
```

## New assessment

```zsh
ruby bin/soul assess grounded-evidence-lifecycle
ruby bin/soul assess grounded-evidence-lifecycle --json
```

## Roadmap change

The milestone stopping point moves from Phase 9 to Phase 11.

Phase 6 is now reserved for a bounded read-only host assessment before layered memory begins.
