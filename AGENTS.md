# AGENTS.md

These instructions apply to all Codex or agentic coding work in this repository unless a more specific human-authored brief explicitly overrides them.

## Prime directive

Soul skills must be bounded, foreground operations with clear start, completion, failure, cancellation, and review behavior.

Codex must produce candidate-complete work for human review. Passing tests or evals does not mean the work is approved for merge, release, or unattended use.

## Hard prohibitions

Codex must not add, enable, install, generate, or rely on any of the following unless the human-authored skill brief explicitly approves it:

- Persistent services
- Daemons
- File watchers
- Network listeners
- Scheduled tasks
- Cron jobs
- systemd units
- launchd agents
- Windows services
- Long-running background loops
- Unbounded polling loops
- Background continuation after the skill returns control to the user

Codex must not weaken confirmation gates, destructive-action protections, safety checks, path protections, memory policies, or review requirements.

Codex must not create skill-private memory stores when shared Soul memory/context infrastructure should be used.

Codex must not treat LLM output as authorization for risky, destructive, persistent, or privileged behavior.

Codex must not broaden the requested skill beyond the approved brief.

Codex must not perform unrelated architectural rewrites while implementing a skill.

## Required implementation behavior

Codex must:

- Read the relevant skill brief before implementation.
- Preserve the existing architecture unless the brief explicitly authorizes a change.
- Implement the smallest complete vertical slice that satisfies the brief.
- Add or update deterministic tests with the implementation.
- Run the approved test commands before declaring the work candidate-complete.
- Run local LLM evals only as behavioral validation, not as safety approval.
- Stop and report a blocked state if the brief is incomplete, contradictory, unsafe, or requires violating these rules.
- Produce or update a human review artifact for each skill candidate.

## Skill lifecycle requirement

A skill must terminate as one of:

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

A skill must not remain silently running after returning a response.

## Bounded execution requirement

Every skill implementation must have bounded runtime behavior. Where practical, it must include timeouts, retry limits, operation limits, or explicit failure behavior.

A skill may persist state and resume on a future invocation. It must not keep a process alive waiting for the user.

## Memory requirement

Durable user context must use the shared Soul memory/context layer. Skills may request, read, update, or forget approved memory keys through shared infrastructure. Skills must not invent isolated memory formats without explicit approval.

## Local LLM eval requirement

Local LLM evals may validate:

- Intent routing
- Conversational phrasing
- Follow-up handling
- Ambiguity behavior
- Response usefulness

Local LLM evals must not validate:

- Safety policy
- File operation permissions
- Confirmation requirements
- Persistent execution
- Privileged actions
- Destructive behavior

## Required completion artifact

For each skill candidate, Codex must create or update a review artifact documenting:

- What was implemented
- Files changed
- Commands run
- Deterministic test results
- Local LLM eval results
- Known weaknesses
- Memory keys added or used
- Task lifecycle states touched
- Risk classification
- Human review checklist

See `docs/soul/HUMAN_REVIEW_GATE.md` and `skills/_template/REVIEW.md`.
# Soul/ Cloud LLM + Codex Guardrails

Cloud LLMs may be used only for drafting, synthesis, critique, prototype suggestions, and review artifacts.

Cloud LLM outputs must not be applied directly to the repo.

Cloud LLMs must not receive secrets, API keys, credentials, private memory, or private repo content unless explicitly permitted by a human-approved skill brief.

Cloud LLMs must not decide safety classification, approval, persistence, memory promotion, or merge readiness.

Cloud-assisted outputs must remain candidate artifacts for human review.

Soul/ prefers no-key providers for low-trust experiments. For serious cloud-assisted drafting/review, manual API-key providers may be used only when they currently document no-credit-card free API access and the key is created manually by the user.

Soul/ must not scrape, fake, farm, or programmatically create provider accounts or API keys. Programmatic credential acquisition is allowed only through official documented OAuth, device-code, or CLI authentication flows approved in the relevant skill brief.

Soul/ skills are bounded foreground tasks. They must not install, create, enable, or rely on persistent services, daemons, watchers, scheduled tasks, cron jobs, systemd units, launch agents, long-running loops, background polling processes, or always-on monitors unless explicitly approved by the human architect in the skill brief.
