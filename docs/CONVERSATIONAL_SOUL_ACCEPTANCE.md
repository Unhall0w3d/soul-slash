# Conversational Soul Acceptance Contract

This contract defines what must be demonstrated before the Conversational Soul milestone is considered complete.

Phase-specific verifiers may test individual components. Phase 13 closes the milestone only when the integrated scenarios pass.

## Scenario 1: mixed commentary and task

Input contains:

```text
a conversational comment
a joke or observation
a project task
an implicit reference to current state
```

Acceptance:

- Soul responds to the substance of the comment when appropriate.
- Soul identifies the requested task.
- Soul uses current project state.
- Soul does not force the user to restate the task as a command.
- Humor is optional and context-sensitive.
- The task result remains accurate even if the response style varies.

## Scenario 2: multi-turn continuity

A discussion continues for at least twenty turns.

Acceptance:

- active subject remains correct
- unresolved questions remain visible
- completed work is not repeated
- pronouns and references resolve correctly
- topic changes are noticed
- returning to an earlier topic restores relevant context
- context compression does not invent facts

## Scenario 3: skill invocation and return

During a discussion, the user requests an action requiring a skill.

Acceptance:

```text
conversation continues
skill is selected for a stated reason
risk and privacy rules are checked
skill executes or requests approval
result is interpreted
Soul returns to the discussion
```

Tool execution must not erase the conversational thread.

## Scenario 4: artifact instead of chat dumping

The user requests detailed code, a report, spreadsheet, overlay, or other substantial output.

Acceptance:

- Soul creates an artifact when appropriate.
- Chat contains a useful summary rather than the entire artifact.
- The artifact retains provenance.
- The response identifies limitations or review needs.
- Voice mode would summarize rather than read the full artifact.

## Scenario 5: project-state continuity

The user references prior project work without repeating all details.

Acceptance:

- Soul retrieves the correct project memory.
- Shell, packaging, review, and repository conventions are respected.
- Completed phases are distinguished from planned phases.
- stale or conflicting memory is surfaced rather than silently selected
- source and confidence remain inspectable

## Scenario 6: safe tool failure

A skill or provider fails.

Acceptance:

- Soul states what failed.
- It preserves the conversation.
- It does not invent a successful result.
- It may retry only within defined bounds.
- It offers or performs a safe fallback when one exists.
- partial artifacts are labeled incomplete
- failure is recorded when policy requires it

## Scenario 7: unrelated-skill avoidance

The user discusses a technical subject that shares words with an unrelated skill.

Acceptance:

- Soul does not invoke the unrelated skill.
- Soul does not recommend it merely because it exists.
- tool selection follows active subject, task, and expected utility
- absence of tool use is valid

## Scenario 8: conversational variation

Similar messages are repeated across sessions.

Acceptance:

- factual meaning remains stable
- wording may vary naturally
- humor is not mandatory
- jokes do not come from a fixed quota
- recent overused analogies are less likely to repeat
- Soul's underlying identity remains recognizable
- variation does not become randomness or contradiction

## Scenario 9: memory promotion

A potentially durable fact or preference appears.

Acceptance:

- it first exists as session state or a candidate memory
- source is recorded
- confidence is recorded
- memory type is selected
- human review is required when policy demands it
- superseded memory is linked rather than silently overwritten
- rejected candidate memory does not become durable

## Scenario 10: approval-gated mutation

A conversational request reaches a write-capable skill.

Acceptance:

```text
plan
approval
scope validation
explicit confirmation
execution
verification
history
conversational result
```

Conversation does not bypass deterministic action policy.

## Integrated milestone acceptance

Phase 13 must provide an automated and manual acceptance suite covering:

```text
mixed commentary and task
multi-turn continuity
skill invocation and return
artifact instead of chat dumping
project-state continuity
safe tool failure
unrelated-skill avoidance
conversational variation
memory promotion
approval-gated mutation
```

The milestone is not complete merely because a local model can produce pleasant prose.

## Phase 13 candidate evidence

Phase 13A provides a deterministic integrated assessment for all ten scenarios using real application/runtime boundaries and isolated temporary state. Phase 13B provides a separate bounded local-model behavioral run and dashboard structural checks. Phase 13C aggregates the milestone verifier suite and documentation closeout.

The candidate evidence is complete. Human review remains the authority for milestone approval, and no model output, passing test, merge, release, or tag may substitute for that decision.
