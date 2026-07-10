
# Phase 46 Skill Invocation Planner

Phase 46 adds skill invocation planning.

## Added / changed

```text
lib/soul_core/skill_invocation_planner.rb
lib/soul_core/skill_invocation_planner_assessor.rb
lib/soul_core/chat_responder.rb
lib/soul_core/app.rb
docs/SKILL_INVOCATION_PLANNER.md
scripts/verify-skill-invocation-planner-phase46.rb
```

## Scope

This phase adds:

```text
candidate skill planning
risk display
confirmation requirement display
executable_now=false guard
planner assessment command
chat-side planning explanations
```

This phase does not add:

```text
actual skill execution
approval prompt persistence
provider calls
filesystem mutation
background jobs
```

## Result

Soul can now describe how it would safely invoke a skill without actually invoking it.
