# Soul Memory Policy

Soul memory exists to make repeated use more useful without making behavior mysterious.

Memory should be explicit, shared, reviewable, and reversible where appropriate.

## Memory classes

### Session memory

Temporary context for the current conversation or invocation. It should not be treated as durable user knowledge.

### Task state

Saved progress for an incomplete multi-turn task. Task state enables clean exits and later resumption without keeping a process alive.

### Durable memory

Reusable facts, preferences, defaults, locations, providers, paths, or other user-approved context that may be used across future skills.

### Reflection

Post-task notes describing what happened, what worked, what failed, and what should improve.

## Shared infrastructure rule

Memory is shared infrastructure, not skill-private storage.

Skills may request, read, update, or forget approved memory keys through the shared memory/context layer.

Skills must not create isolated private memory files or formats unless a human-authored brief explicitly approves it.

## Durable memory rules

Durable memory keys should be:

- Named clearly
- Scoped appropriately
- Documented in the skill review artifact
- Updated only when the user provides or approves the context
- Forgettable or replaceable where appropriate
- Reused by other skills when semantically appropriate

## Example memory keys

```text
user.default_location
weather.default_location
calendar.default_timezone
local_search.default_area
downloads.default_directory
utility.default_provider
```

Prefer general keys when the context is useful across skills. Prefer skill-specific keys only when the context is truly skill-specific.

Example:

```text
Correct:
user.default_location = "Syracuse, NY"
weather.default_location uses user.default_location unless overridden
```

```text
Wrong:
skills/weather/weather_location.json
```

## First-use behavior

When a skill requires durable context that does not exist, it should ask for the missing information and enter `awaiting_input`.

It should not guess durable context from unrelated signals unless explicitly approved.

It should not keep a process alive while waiting.

## Update and forget behavior

When practical, users should be able to say things like:

```text
Use Buffalo for weather instead.
Forget my weather location.
Use Syracuse as my default location.
```

The memory layer should make those changes explicit and reviewable.

## LLM limits

LLMs may help identify that a user is providing, updating, or forgetting context.

LLMs must not silently create durable memory without an approved flow.

LLMs must not authorize risky behavior based on remembered context alone.
