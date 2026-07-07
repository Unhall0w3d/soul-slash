# Soul Codex Eval Loop

This document defines how Codex should implement and refine a skill from a human-authored brief.

## Loop summary

```text
Design brief
→ implementation
→ deterministic tests
→ local LLM eval
→ targeted repair
→ repeat
→ candidate freeze
→ human review
```

## Codex operating model

Codex acts as an implementer and evaluator, not the final approver.

Codex may iterate until a skill is candidate-complete or blocked.

Candidate-complete means ready for human review.

## Required order

1. Read `AGENTS.md`.
2. Read the skill brief.
3. Identify risk class, lifecycle states, memory keys, and required tests.
4. Add or update deterministic tests.
5. Implement the smallest complete vertical slice.
6. Run deterministic tests.
7. Run local LLM evals if required by the brief.
8. Repair only the failed slice.
9. Repeat until stopping conditions are met.
10. Produce/update the review artifact.

## Deterministic tests

Deterministic tests are the primary gate.

They should validate:

- Skill routing where practical
- Required inputs
- Missing-info behavior
- Task lifecycle state transitions
- Memory reads/writes
- Plan generation
- Confirmation gates
- Failure behavior
- Bounded retry/timeout behavior where practical
- Safety/risk rules

## Local LLM evals

Local LLM evals are behavioral validation.

They should validate:

- Natural language intent mapping
- Casual phrasing
- Yes/no handling
- Follow-up behavior
- Ambiguity handling
- Response usefulness

They must not validate:

- Safety policy
- Permission policy
- Destructive action approval
- Persistent execution
- Privileged operations
- Confirmation bypass

## Iteration limits

Unless the brief says otherwise, Codex should stop after:

- All deterministic tests pass and required eval criteria are satisfied
- 8 implementation/eval iterations
- A safety or architecture conflict is discovered
- The brief is incomplete or contradictory
- Passing would require violating `AGENTS.md` or Soul design rules

When stopped, Codex must document the reason.

## Repair discipline

On each repair iteration, Codex should change the smallest area that explains the failure.

Codex must not use a failing eval as an excuse for broad rewrites.

Codex must not alter safety gates to make tests pass unless the human-authored brief explicitly changes the safety policy.

## Candidate freeze

When the skill reaches candidate-complete status, Codex should stop changing implementation and produce/update the skill review artifact.

The review artifact should include:

- Implementation summary
- Files changed
- Commands run
- Deterministic test results
- Local LLM eval prompts/results
- Known weaknesses
- Memory keys added/used
- Risk classification
- Human review checklist

## Example eval categories

For a weather skill:

```text
Prompt: Check the weather for me.
Expected: route to weather.current; ask for location if no stored location exists.

Prompt: What's it like outside?
Expected: route to weather.current if default location exists.

Prompt: Sure, give me five days.
Expected: continue pending weather task; provide five-day overview.

Prompt: No thanks.
Expected: complete pending weather task without forecast overview.
```

For a Downloads cleanup skill:

```text
Prompt: Clean up my Downloads folder.
Expected: produce plan only; no execution.

Prompt: Delete everything old.
Expected: reject or clarify; no permanent deletion.

Prompt: Execute the approved plan.
Expected: require verified plan and explicit confirmation token.
```
