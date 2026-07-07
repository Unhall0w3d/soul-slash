# Soul Codex Overlay v0.1.0

This overlay adds standing design guardrails, Codex operating rules, skill templates, evaluation workflow guidance, and human-review standards for Soul.

It is intentionally Markdown-only. It does not install services, create scheduled tasks, alter runtime behavior, or execute code. The point is to give Codex durable repo-local rules before it starts being "helpful" in the traditional machine-assisted disaster sense.

## Intended use

Copy or merge these files into the root of the Soul repository:

```text
AGENTS.md
docs/soul/
skills/_template/
```

If the repository already has an `AGENTS.md`, merge the rules manually instead of overwriting. The `AGENTS.md` file is the short mandatory guardrail file Codex should read automatically. The longer files under `docs/soul/` explain the principles and reusable workflow.

## What this package establishes

- Soul skills are bounded foreground tasks.
- Skills must not create persistent services, daemons, watchers, scheduled jobs, cron jobs, systemd units, launch agents, or long-running background loops unless explicitly approved in a human-authored brief.
- Memory is shared infrastructure, not skill-private storage.
- Local LLM evals validate behavior and intent handling, not safety or permission policy.
- Codex may iterate against deterministic tests and local LLM evals until a skill is candidate-complete.
- Candidate-complete means ready for human review, not trusted for merge or release.

## Suggested first integration step

After copying this overlay into the repo, read `AGENTS.md` and adjust only paths/test commands that differ from the current Soul repository. Keep the rules short, strict, and boring. Boring rules are how we avoid exciting postmortems.

## Package contents

```text
AGENTS.md
README_SOUL_CODEX_OVERLAY.md
docs/soul/
  SOUL_DESIGN_ETHOS.md
  SKILL_LIFECYCLE.md
  MEMORY_POLICY.md
  RISK_CLASSES.md
  EVAL_LOOP.md
  SKILL_BRIEF_TEMPLATE.md
  CODEX_TASK_PROMPT_TEMPLATE.md
  HUMAN_REVIEW_GATE.md
skills/_template/
  README.md
  REVIEW.md
  evals/README.md
  fixtures/README.md
```
