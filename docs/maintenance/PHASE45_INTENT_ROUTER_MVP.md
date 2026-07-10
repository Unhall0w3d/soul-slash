
# Phase 45 Intent Router MVP

Phase 45 adds deterministic chat intent routing.

## Added / changed

```text
lib/soul_core/intent_router.rb
lib/soul_core/intent_router_assessor.rb
lib/soul_core/chat_responder.rb
lib/soul_core/app.rb
docs/INTENT_ROUTER_MVP.md
scripts/verify-intent-router-mvp-phase45.rb
```

## Scope

This phase adds:

```text
pattern-based intent routing
candidate skill mapping
risk labels
confirmation hints
intent-router assessment command
chat responses that mention mapped skills
```

This phase does not add:

```text
LLM-backed routing
skill execution
approval workflow
tool invocation
provider calls
background services
```

## Result

Soul can classify simple chat utterances into safe deterministic intent categories.
