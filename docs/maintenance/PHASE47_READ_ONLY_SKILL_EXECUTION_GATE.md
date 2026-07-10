
# Phase 47 Read-Only Skill Execution Gate

Phase 47 adds a read-only execution gate.

## Added / changed

```text
lib/soul_core/read_only_skill_execution_gate.rb
lib/soul_core/read_only_skill_execution_gate_assessor.rb
lib/soul_core/chat_responder.rb
lib/soul_core/app.rb
docs/READ_ONLY_SKILL_EXECUTION_GATE.md
scripts/verify-read-only-skill-execution-gate-phase47.rb
```

## Scope

This phase adds:

```text
read-only allowlist modeling
adapter-backed readiness modeling
approval-required blocking
dry-run execution gate assessment
chat-side gate explanations
```

This phase does not add:

```text
actual skill execution
provider calls
filesystem mutation
approval persistence
background jobs
```

## Result

Soul can now decide whether a planned skill would be allowed through a read-only execution gate.
