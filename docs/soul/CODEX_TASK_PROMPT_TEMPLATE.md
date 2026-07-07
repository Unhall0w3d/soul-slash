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

Hard boundaries:
- Do not add persistent services, daemons, watchers, scheduled tasks, cron jobs, systemd units, launch agents, Windows services, long-running loops, or background polling.
- Do not weaken confirmation gates or safety behavior.
- Do not create skill-private memory when shared Soul memory/context should be used.
- Do not broaden scope beyond the brief.
- Do not perform unrelated architecture rewrites.
- Stop and report blocked status if the brief requires violating Soul design rules.

Implementation requirements:
- Add/update deterministic tests.
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

Final output required:
- Summary of implementation
- Files changed
- Commands run
- Test results
- Local LLM eval results
- Known weaknesses
- Memory keys added/used
- Risk class
- Human review checklist
```
