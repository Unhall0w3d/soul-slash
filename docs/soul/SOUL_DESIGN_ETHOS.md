# Soul Design Ethos

Soul is designed as a local, skill-oriented assistant that can perform useful work while remaining understandable, bounded, inspectable, and safe to review.

The goal is not to make Soul magically autonomous. The goal is to make Soul predictably capable. Magic is what people call software right before they discover the logs are useless.

## Core philosophy

A Soul skill should be boringly predictable.

A good skill:

- Has a clear beginning and end
- Has bounded scope
- Has bounded runtime
- Has explicit inputs
- Has explicit outputs
- Can explain what it did
- Can fail cleanly
- Can be tested without uncontrolled external state where practical
- Uses shared memory/context when durable information is needed
- Never performs a risky action based only on LLM interpretation
- Produces reviewable logs, summaries, or reflection when appropriate

## Bounded foreground tasks

Soul skills are bounded foreground operations.

They start, perform a clearly scoped action, return a result, write any approved logs/reflection/memory updates, and exit cleanly.

No skill may install, create, enable, or rely on a persistent service, daemon, watcher, scheduled task, cron job, systemd unit, launch agent, Windows service, long-running loop, background polling process, or always-on monitor unless explicitly approved by the human architect in the skill brief.

Soul may remember, resume, and repeat tasks, but it must not persistently run tasks unless a human explicitly approves that architecture.

## Repeatable does not mean persistent

Repeatable means a skill can be invoked again later and use stored context, saved task state, logs, memory, or prior reflection.

Persistent means a process or service remains running in the background to keep checking, watching, polling, or acting.

Soul defaults to repeatable, not persistent.

Correct pattern:

```text
Persist task state: awaiting_location
Exit cleanly
Resume when the user responds
```

Wrong pattern:

```text
Keep a process alive until the user answers
```

Correct pattern:

```text
Store weather.default_location in shared memory and reuse it next time
```

Wrong pattern:

```text
Start a weather watcher service so the next response is faster
```

## Clean exits and predictable failures

Every skill should terminate in a known state:

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

A skill should not disappear into a silent wait, hidden loop, or unbounded retry cycle.

Failures should be specific enough that the next engineering pass can adjust the skill, tests, provider integration, or user-facing message.

## Human approval boundary

Codex may build candidate-complete skills. Codex may iterate against tests and local LLM evals. Codex may prepare review artifacts.

Codex may not approve its own work for merge, release, unattended use, elevated permissions, persistent background behavior, destructive operations, or weakened confirmation gates.

Human review remains the approval boundary.

## Skill boundaries

Skills should be isolated capability modules. A skill should not absorb router logic, memory engine logic, provider abstractions, or unrelated system concerns.

The skill router should route. The memory layer should remember. The task lifecycle layer should manage state. Skills should perform their approved capability inside those lines.

If implementation pressure suggests the boundaries are wrong, Codex must stop and report the issue rather than improvising a new architecture.

## Memory and learning

Memory is shared infrastructure, not a place for every skill to grow its own tiny cave ecosystem.

A skill may use durable memory only through approved shared memory/context APIs or formats. Durable memory keys should be named, documented, typed where practical, and reviewable.

Users must be able to update or forget durable context where appropriate.

## LLM role

LLMs may help interpret user intent, summarize results, generate natural language, and evaluate conversational behavior.

LLMs must not be treated as safety authorities.

An LLM cannot authorize deletion, persistence, privileged operations, confirmation bypass, or architecture changes. It is a language model, not a tiny digital magistrate.

## Candidate-complete standard

A skill is candidate-complete when:

- The approved brief has been implemented within scope
- Deterministic tests pass
- Required local LLM evals pass or failures are documented
- Safety and lifecycle checks pass
- Review artifacts are complete
- Known limitations are documented
- The work is ready for human review

Candidate-complete does not mean approved.
