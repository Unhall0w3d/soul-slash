# Soul/ Design Ethos

Soul/ is a local assistant substrate built around bounded skills, deterministic safety boundaries, verification gates, and human-approved memory.

## Core posture

Soul/ should be useful without becoming an unattended automation daemon.

A skill should:

```text
start
perform a clearly scoped foreground task
ask for missing input when needed
preserve state when waiting for input
return evidence
write approved logs/reflection artifacts
exit cleanly
```

A skill should not quietly leave processes running because a model decided persistence would be convenient.

## Bounded foreground task rule

Soul/ skills are bounded foreground tasks.

No skill may install, create, enable, or rely on a persistent service, daemon, watcher, scheduled task, cron job, systemd unit, launch agent, long-running loop, background polling process, or always-on monitor unless explicitly approved by the human architect in the skill brief.

Correct pattern:

```text
store task state: awaiting_location
exit cleanly
resume from saved state when the user responds
```

Incorrect pattern:

```text
keep a Ruby or Python process running indefinitely waiting for the user
```

## Skill lifecycle

Expected lifecycle:

```text
idle
→ invoked
→ context_check
→ awaiting_input, if required
→ planned, if approval is required
→ executing, only after approval where required
→ complete / failed / canceled / blocked_for_human_review
→ reflection_written, where appropriate
→ exit
```

Allowed terminal states:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Verification posture

Soul/ distinguishes between:

```text
action completed
goal satisfied
verification evidence
warnings
reflection candidates
human-approved memory
```

No green lights without gauges.

## Failure philosophy

A good failure:

```text
explains what failed
preserves safe state
writes useful logs
does not retry forever
does not silently broaden scope
does not install persistent helpers
gives enough information for human or Codex repair
```

A bad failure:

```text
hangs indefinitely
silently retries without bounds
leaves a process running
partially mutates state without logging
allows an LLM to reinterpret safety policy
changes architecture outside the brief
```

## Memory posture

Soul/ should distinguish:

```text
session memory
task state
durable memory
reflection candidates
human-approved lessons/rules
```

Skills should prefer shared memory/context infrastructure over private skill-specific memory stores.

Local configuration such as `.env` may hold operator defaults and secrets, but it is not a substitute for user-approved durable memory.

## Authority model

```text
Human:
architecture, approval, safety authority

Codex:
repo-local implementation worker and test runner

Local LLM:
behavior target and low-risk conversational evaluator

Cloud LLM:
drafting, critique, synthesis, prototype suggestions, review artifacts

Soul/:
bounded execution, evidence, state, reflection, policy enforcement
```

Candidate-complete does not mean approved. It means ready for review.
