
# Phase 39 Interaction Architecture

Phase 39 pauses new skill expansion and documents the plan for Soul's owned interaction layer.

## Decision

Soul will build its own required interaction core.

Third-party chat frontends may be optional clients later, but they will not define Soul's memory, skill routing, approval gates, or assistant behavior.

## Added docs

```text
docs/INTERACTION_ARCHITECTURE.md
docs/FRONTEND_RESEARCH.md
docs/INFRASTRUCTURE_PLAN.md
docs/CHAT_DATA_MODEL.md
```

## Scope

Phase 39 is documentation-only.

It does not:

```text
add chat commands
create a database
start services
install containers
invoke models
run skills
modify runtime state
```

## Next implementation phase

The next implementation phase should add the terminal chat foundation:

```text
ruby bin/soul chat
ruby bin/soul chat "message"
local chat storage
basic deterministic assistant responses
no LLM required yet
```
