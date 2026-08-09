# Codex Native Subagent Routing A1 Review

## Candidate

Name: Spark, Luna, and Terra delegation with evidence-based trust

Risk class: Low — development workflow policy and documentation only

Status: `candidate_complete`

## Implementation

The owner-level Codex policy in `~/.codex/AGENTS.md` now lets primary Sol choose
Spark, Luna, or Terra for bounded work. Routing considers task risk, ambiguity,
context, implementation depth, allowance, and handoff cost. Every assignment
must define scope, ownership, acceptance, authority, non-goals, shared-worktree
behavior, and returned evidence.

Evidence-trusted read-only findings are consumed without repeating the same
search. Change-trusted reversible work is not independently reimplemented or
subjected to duplicate test runs after the assigned agent provides the required
evidence. Repository- or brief-mandated checks remain mandatory, and primary
Sol still performs proportionate integration validation. High-risk work and
named Soul safety controls remain primary-owned and independently verified.

The tracked guide distinguishes native Codex subagents from Soul's tool-less
local GPT-OSS Dev Worker.

## Files changed

```text
README.md
docs/CURRENT_STATE.md
docs/assessments/CODEX_NATIVE_SUBAGENT_ROUTING_A1_REVIEW.md
docs/guides/CODEX_SUBAGENTS.md
docs/guides/CORES.md
docs/guides/DEV_WORKER.md
```

Owner-local configuration changed outside the public repository:

```text
~/.codex/AGENTS.md
```

## Validation

- Spark Explorer mapped the existing native-agent and Soul Dev Worker boundary.
- Luna checked terminology, links, scope, and cross-document consistency.
- Terra challenged the trust policy against Soul's repository validation and
  safety requirements.
- Primary Sol applied their exact findings without replaying either review.
- `git diff --check` passes.
- Integration assertions confirm the guide is linked and all three trust levels
  and four model roles are present in both policy and documentation.

## Known weaknesses

- Native subagent availability and allowance reporting are Codex runtime
  capabilities, not controlled by this repository.
- The machine-wide policy is owner-local and intentionally not copied into the
  public repository; the tracked guide describes it without pretending to
  install it for other users.
- Evidence-based trust reduces duplicate work but cannot guarantee a subagent is
  correct. Contradiction, drift, missing evidence, or unexpected scope revokes
  trust for that assignment.

## Persistence and authority

```text
Persistent service added: no
Scheduler or background worker added: no
Repository or shell authority broadened: no
Human approval gate weakened: no
Required repository validation waived: no
Merge authority delegated: no
```

## Human review

```text
[ ] Routing roles match the intended cost and capability balance
[ ] Evidence-trusted work may be consumed without duplicated exploration
[ ] Change-trusted work retains repository- and brief-mandated tests
[ ] High-risk work and Soul safety controls remain independently verified
[ ] Native Codex subagents remain distinct from the local Soul Dev Worker
```

Outcome: pending
