# Codex Task Prompt Template

Use this template when giving Codex a skill implementation task.

```text
You are implementing a Soul skill candidate for human review.

Read first:
- AGENTS.md
- docs/soul/SOUL_DESIGN_ETHOS.md
- docs/soul/SKILL_LIFECYCLE.md
- docs/soul/MEMORY_POLICY.md
- docs/soul/RISK_CLASSES.md
- docs/soul/EVAL_LOOP.md
- <path to skill brief>

Task:
Implement <skill_name> according to the skill brief.
Carry the approved implementation through required verification. Do not request
the same approval again; ask only for a new material decision, scope expansion,
or actual authority boundary. Finish unaffected authorized work before pausing.

Hard boundaries:
- Apply the authority order and non-waivable safeguards in `AGENTS.md`.
- Treat the brief and selected role as authority-narrowing layers, not authority
  expansion.
- Preserve shared-worktree changes and stay within the assignment's owned paths
  or read-only scope.
- Stop and report blocked status if the brief requires violating Soul design rules.

Implementation requirements:
- Run deterministic checks for every implementation. Add/update tests only for
  distinct behavior or a credible failure mode not already covered. Give
  safety-sensitive behavior deterministic coverage.
- Implement the smallest complete vertical slice.
- Run the approved test command.
- Run local LLM evals required by the brief after deterministic tests pass.
- Iterate on failures until candidate-complete or blocked.
- Produce/update the skill REVIEW.md.

Stopping conditions:
- All required deterministic tests pass and eval criteria are satisfied.
- Maximum 8 implementation/eval iterations reached.
- The brief is incomplete, contradictory, unsafe, or requires architecture clarification.
- Passing requires violating AGENTS.md or Soul design rules.

If the iteration bound is reached, report the unfinished acceptance criteria,
evidence, and smallest next decision or scoped retry. Do not call the work
complete or silently restart the counter. This coding-task bound is separate
from the implemented skill's runtime limits and does not remove review gates.

Final output required:
- Return the evidence required by the validated assignment envelope.
- Complete the canonical review packet in `docs/soul/HUMAN_REVIEW_GATE.md`.
```

For native Codex subagents, validate the assignment before dispatch:

```bash
scripts/soul-agent-control-plane assignment path/to/assignment.json
```

The assignment must conform to
`docs/soul/schemas/codex_subagent_assignment.schema.json`.
