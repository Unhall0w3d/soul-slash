# Soul Skill Brief Template

Use this template to define a skill before Codex implements it.

A brief should be specific enough that Codex can implement, test, evaluate, repair, and produce a candidate-complete skill without inventing architecture.

## Skill name

`namespace.skill_name`

Example:

`weather.current`

## Purpose

Describe what the skill does in one or two paragraphs.

## Risk class

Choose one from `docs/soul/RISK_CLASSES.md`.

```text
Class 0: Read-only local or conversational
Class 1: Read-only external lookup
Class 2: Local state write, non-destructive
Class 3: Local user-data modification
Class 4: External write/action
Class 5: Privileged, destructive, persistent, or security-sensitive
```

## Approved scope

The skill may:

- ...

## Explicitly out of scope

The skill must not:

- ...

Always include persistence boundaries:

- Must not create services, daemons, watchers, scheduled tasks, cron jobs, systemd units, launch agents, Windows services, long-running loops, or background polling unless explicitly approved.

## Inputs

List expected inputs.

```text
Required:
- ...

Optional:
- ...
```

## Outputs

List expected outputs.

```text
User-facing:
- ...

Structured/logged:
- ...
```

## Memory behavior

List memory keys read, written, updated, or forgotten.

```text
Reads:
- ...

Writes:
- ...

Updates:
- ...

Forget behavior:
- ...
```

If no durable memory is needed, state that explicitly.

## Task lifecycle

Describe expected state transitions.

```text
invoked
→ context_check
→ awaiting_input, if required
→ executing
→ complete / failed / canceled / blocked_for_human_review
→ reflection_written, if applicable
→ exit
```

## First-use behavior

Describe what happens when required durable context is missing.

Example:

```text
If no default location exists, ask the user for a location, save task state as awaiting_input(location), and exit cleanly.
```

## Follow-up behavior

Describe accepted follow-ups and how they map to task continuation.

Example:

```text
Affirmative: yes, yeah, sure, go ahead, please do
Negative: no, nope, nah, no thanks
```

## Provider/dependency behavior

Describe external APIs, local commands, or dependencies.

Include timeout/retry expectations.

## Safety and confirmation gates

Describe required approvals, previews, dry-runs, plans, or confirmation tokens.

If none are required, state why.

## Deterministic tests required

List required tests.

- ...

## Local LLM evals required

List required eval prompts and expected behavior.

- Prompt: ...
  Expected: ...

## Failure behavior

Define predictable failures and expected messages/states.

- ...

## Logging and reflection

Describe logs, review artifacts, or reflection entries.

## Done criteria

The skill is candidate-complete when:

- Approved scope is implemented
- Out-of-scope behavior is not present
- Deterministic tests pass
- Required local LLM evals pass or failures are documented
- Memory behavior is documented
- Review artifact is complete
- Skill exits cleanly in all tested paths
- Human review checklist is ready
