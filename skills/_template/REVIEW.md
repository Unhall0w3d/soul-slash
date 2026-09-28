# Skill Candidate Review

## Skill

Name:

Risk class:

Branch/checkpoint:

Date:

## Candidate status

Choose one:

```text
candidate_complete
blocked
requires_repair
```

## Implementation summary

Describe what was implemented.

## Files changed

```text
- ...
```

## Commands run

```text
- ...
```

## Deterministic test results

```text
Command:
Result:
Notes:
```

## Local LLM eval results

```text
Eval command or method:
Model/endpoint:
Result:
Notes:
```

## Eval prompts

```text
Prompt:
Expected:
Actual:
Pass/Fail:
```

## Memory keys

Reads:

```text
- ...
```

Writes/updates:

```text
- ...
```

Forget behavior:

```text
- ...
```

## Lifecycle states touched

```text
- ...
```

## Safety and persistence check

Confirm all are false unless explicitly approved in the brief:

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Evidence and privacy boundary

For an operation that summarizes external or retained evidence, record the
source readers actually invoked, whether they can refresh or query, how
malformed and partial evidence appears, and the fixture used to prove that
free-form private source text stays out of the response.

## Known weaknesses

```text
- ...
```

## Human review checklist

```text
[ ] Matches approved brief
[ ] No unapproved scope expansion
[ ] No unapproved persistence/background behavior
[ ] Risk class is correct
[ ] Memory behavior is appropriate
[ ] Confirmation gates are intact
[ ] Deterministic tests are meaningful
[ ] Local LLM evals are behavioral only
[ ] Failure behavior is predictable
[ ] Logs/reflection are useful
```

## Human review outcome

```text
Outcome:
Reviewer:
Date:
Decision summary:
Required changes:
```
