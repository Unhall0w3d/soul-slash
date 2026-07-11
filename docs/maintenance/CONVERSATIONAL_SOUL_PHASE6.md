# Conversational Soul Phase 6

Milestone:

```text
Conversational Soul
```

Phase:

```text
6
```

## Purpose

Implement a bounded read-only host-environment assessment so Soul can answer environment questions from collected facts rather than inference.

## Added

```text
lib/soul_core/host_system_status_collector.rb
lib/soul_core/bounded_host_system_status_assessor.rb
docs/BOUNDED_HOST_SYSTEM_STATUS.md
scripts/verify-bounded-host-system-status-phase6.rb
```

## Updated

```text
lib/soul_core/conversation_evidence_contract.rb
lib/soul_core/conversation_tool_catalog.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/conversational_orchestrator_assessor.rb
lib/soul_core/grounded_evidence_lifecycle_assessor.rb
lib/soul_core/app.rb
docs/HOST_ENVIRONMENT_CAPABILITY_GAP.md
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/MILESTONES.md
CHANGELOG.md
```

## Behavioral change

Generic host-environment and system-status requests now invoke:

```text
host.system_status
```

The existing `system.status` capability is reserved for explicit Soul runtime status.

Host results are structured, persisted as evidence, and returned without model synthesis.

## New assessment

```zsh
ruby bin/soul assess bounded-host-system-status
ruby bin/soul assess bounded-host-system-status --json
```

## Next

Phase 7 begins layered memory.
