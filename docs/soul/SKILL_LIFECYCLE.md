# Soul Skill Lifecycle

This document defines the expected lifecycle for Soul skills.

## Standard lifecycle

```text
idle
→ invoked
→ context_check
→ awaiting_input, if required
→ planned, if action requires approval
→ executing, only after approval when required
→ complete / failed / canceled / blocked_for_human_review
→ reflection_written, when applicable
→ exit
```

## Terminal states

Every skill run must end in one of these states:

### complete

The skill performed the requested bounded task successfully and has returned a final response.

### failed

The skill could not complete due to a known error, unsupported condition, missing external dependency, provider failure, validation failure, or other predictable failure.

The failure should include a useful reason.

### awaiting_input

The skill needs additional user input before continuing. The process must not stay alive while waiting. State should be saved and resumed on the next invocation or response.

### canceled

The user or policy canceled the task.

### blocked_for_human_review

The implementation or runtime path reached a condition that requires architectural, safety, permission, or product judgment.

## Long-running behavior

Skills must not use indefinite loops or background wait states.

Acceptable:

- Bounded retry with maximum attempt count
- Timeout around network calls
- Persisted task state for future resumption
- Explicit failure when a dependency is unavailable

Not acceptable without explicit human approval:

- Daemons
- Watchers
- Always-on monitors
- Hidden background tasks
- Scheduled polling
- Processes kept alive after returning to the user

## Multi-turn tasks

Multi-turn behavior should be represented as persisted task state, not process persistence.

Example:

```text
User: Check the weather for me.
Soul: What location should I use?
State: awaiting_input(location)
Process: exits

User: Syracuse, NY.
Soul: Stores approved location, performs lookup, continues task.
```

## Planning and execution split

Any skill that performs local state changes, filesystem changes, external writes, or other meaningful actions should separate planning from execution.

Plan-producing skills must not execute.

Execution must consume a verified plan and satisfy any required confirmation gate.

## Reflection

Reflection is a post-task artifact. It may describe what happened, what worked, what failed, and what should be improved.

Reflection must not become a hidden background process or a second execution path.
